// Ghost — OpenAI Provider implementation.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../models/message.dart';
import '../../models/provider.dart';
import '../../infra/errors.dart';

final _log = Logger('Ghost.LLMProvider');

/// Implementation of OpenAI's GPT models.
class OpenAIProvider implements AIModelProvider {
  OpenAIProvider({
    required this.apiKey,
    this.model = 'gpt-4o',
    this.baseUrl = 'https://api.openai.com/v1',
    String? displayName,
    String? providerId,
    this.supportsChat = true,
    this.isReasoningModel = false,
    this.numCtx,
  }) : _displayName = displayName,
       _providerId = providerId ?? 'openai';

  final String apiKey;
  final String model;
  final String baseUrl;
  final String? _displayName;
  final String _providerId;

  /// If true, this is a reasoning model (e.g. deepseek-reasoner) that requires
  /// special message handling — tool call history must be sanitized.
  final bool isReasoningModel;

  /// Optional Ollama-specific context window size (num_ctx).
  /// When set, passed via `options.num_ctx` in the request body so Ollama
  /// uses a larger context window than its per-model default.
  final int? numCtx;

  @override
  String get providerId => _providerId;

  @override
  final bool supportsChat;

  @override
  String get modelId => model;

  @override
  String get displayName => _displayName ?? 'OpenAI GPT';

  @override
  ModelCapabilities get capabilities {
    final lower = model.toLowerCase();

    // GPT-4o and GPT-4o-mini support vision
    if (lower.contains('gpt-4o') || lower.contains('gpt-4-turbo')) {
      return const ModelCapabilities(supportsText: true, supportsImage: true);
    }

    return ModelCapabilities.textOnly();
  }

  @override
  Future<AIResponse> chat({
    required List<Message> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    double temperature = 0.7,
    List<ToolDefinition>? tools,
    int? numCtx,
    void Function(String chunk)? onPartialResponse,
  }) async {
    final url = Uri.parse('$baseUrl/chat/completions');

    final apiMessages = <Map<String, dynamic>>[];

    if (systemPrompt != null) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }

    final skippedToolCallIds = <String>{};

    for (final m in messages) {
      // Reasoning models (deepseek-reasoner) require `reasoning_content` in
      // assistant messages that have tool_calls.
      if (isReasoningModel &&
          m.role == 'assistant' &&
          m.metadata.containsKey('tool_calls')) {
        if (!m.metadata.containsKey('reasoning_content')) {
          // Record skipped IDs to skip corresponding tool outputs
          final calls = m.metadata['tool_calls'] as List<dynamic>;
          for (final c in calls) {
            final id = (c as Map<String, dynamic>)['id'];
            if (id != null) skippedToolCallIds.add(id);
          }
          continue;
        }
      }

      if (isReasoningModel && m.role == 'tool') {
        final id = m.metadata['tool_call_id'];
        if (id == null || skippedToolCallIds.contains(id)) {
          continue;
        }
      }

      final dynamic content;
      if (m.role == 'user' && m.attachments.isNotEmpty) {
        final parts = <Map<String, dynamic>>[];
        if (m.content.isNotEmpty) {
          parts.add({'type': 'text', 'text': m.content});
        }
        for (final a in m.attachments) {
          if (a.mimeType.startsWith('image/')) {
            parts.add({
              'type': 'image_url',
              'image_url': {'url': 'data:${a.mimeType};base64,${a.data}'},
            });
          }
        }
        content = parts;
      } else {
        content = m.content;
      }

      final msg = <String, dynamic>{'role': m.role, 'content': content};

      // Only send reasoning_content back in history for DeepSeek-style
      // reasoning models (isReasoningModel=true). Ollama/Gemma reject this field.
      if (isReasoningModel && m.metadata.containsKey('reasoning_content')) {
        msg['reasoning_content'] = m.metadata['reasoning_content'];
      }

      // Add tool_call_id for tool outputs
      if (m.role == 'tool' && m.metadata.containsKey('tool_call_id')) {
        msg['tool_call_id'] = m.metadata['tool_call_id'];
      }

      // Add tool_calls for assistant messages
      if (m.role == 'assistant' && m.metadata.containsKey('tool_calls')) {
        final calls = m.metadata['tool_calls'] as List<dynamic>;
        if (calls.isNotEmpty) {
          msg['tool_calls'] = calls.map((c) {
            final call = c as Map<String, dynamic>;
            return {
              'id': call['id'],
              'type': 'function',
              'function': {
                'name': call['name'],
                'arguments': jsonEncode(call['arguments']),
              },
            };
          }).toList();
        }
      }

      apiMessages.add(msg);
    }

    // For Ollama: pass num_ctx via options to extend the context window.
    // Ollama's default num_ctx for local models is often 4096 which is too
    // small when Ghost's system prompt + all tool definitions are included.
    // Also skip max_tokens for Ollama — it maps to num_predict and is
    // separate from num_ctx; leaving it unset lets the model use its full
    // output budget.
    final isOllama =
        _providerId == 'ollama' ||
        _providerId == 'ipex-llm' ||
        _providerId == 'lmstudio' ||
        _providerId == 'vllm';
    // Use 8192 for local models so memory allocation is fast and doesn't take minutes
    final effectiveNumCtx = numCtx ?? (isOllama ? 8192 : null);

    final body = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
      if (!isOllama) 'max_tokens': maxTokens,
      'temperature': temperature,
      if (tools != null && tools.isNotEmpty)
        'tools': tools
            .map(
              (t) => {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.inputSchema,
                },
              },
            )
            .toList(),
      if (effectiveNumCtx != null) 'options': {'num_ctx': effectiveNumCtx},
    };

    _log.fine('Requesting $displayName ($baseUrl): $model');

    // --- STREAMING PATH (when onPartialResponse is provided) ---
    if (onPartialResponse != null) {
      final client = http.Client();
      final streamChunkBuffer = StringBuffer();
      Timer? flushTimer;

      void flushStreamChunk() {
        flushTimer?.cancel();
        flushTimer = null;
        if (streamChunkBuffer.isNotEmpty) {
          final textToEmit = streamChunkBuffer.toString();
          streamChunkBuffer.clear();
          onPartialResponse(textToEmit);
        }
      }

      try {
        final request = http.Request('POST', url)
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
            'Accept': 'text/event-stream',
            'User-Agent': 'Ghost/1.0',
          })
          ..body = jsonEncode({...body, 'stream': true});

        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 180),
          onTimeout: () => throw TimeoutException(
            'Request to $displayName ($baseUrl) timed out after 180s',
          ),
        );

        if (streamedResponse.statusCode != 200) {
          final errorBody = await streamedResponse.stream.bytesToString();
          _log.severe(
            '$displayName API error: ${streamedResponse.statusCode} - $errorBody',
          );
          throw ProviderError(
            'OpenAI API error (${streamedResponse.statusCode}): $errorBody',
            provider: 'openai',
          );
        }

        final contentBuffer = StringBuffer();
        final reasoningBuffer = StringBuffer();

        final Map<int, Map<String, dynamic>> accumulatedToolCalls = {};
        TokenUsage? tokenUsage;
        String? finishReason;

        await for (final line in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          final payload = trimmed.substring(5).trim();
          if (payload.isEmpty) continue;
          if (payload == '[DONE]') break;

          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            final choices = data['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final choice = (choices.first is Map)
                  ? (choices.first as Map)
                  : <dynamic, dynamic>{};
              if (choice['finish_reason'] != null) {
                finishReason = choice['finish_reason']?.toString();
              }
              final delta = (choice['delta'] is Map) ? (choice['delta'] as Map) : null;
              if (delta != null) {
                final chunk = delta['content'] as String?;
                if (chunk != null && chunk.isNotEmpty) {
                  contentBuffer.write(chunk);
                  streamChunkBuffer.write(chunk);
                  final bufStr = streamChunkBuffer.toString();
                  // Flush on natural word boundaries, line breaks, punctuation or when buffer reaches 25 chars
                  if (bufStr.length >= 25 ||
                      bufStr.endsWith('\n') ||
                      (bufStr.length >= 6 &&
                          (bufStr.endsWith(' ') ||
                              bufStr.endsWith('.') ||
                              bufStr.endsWith(',') ||
                              bufStr.endsWith('!') ||
                              bufStr.endsWith('?') ||
                              bufStr.endsWith(':')))) {
                    flushStreamChunk();
                  } else {
                    flushTimer ??= Timer(
                      const Duration(milliseconds: 25),
                      flushStreamChunk,
                    );
                  }
                }
                final reasoningChunk = (delta['reasoning_content'] as String?) ??
                    (delta['reasoning'] as String?);
                if (reasoningChunk != null && reasoningChunk.isNotEmpty) {
                  reasoningBuffer.write(reasoningChunk);
                }
                final toolCallDeltas = delta['tool_calls'] as List<dynamic>?;
                if (toolCallDeltas != null) {
                  for (final tc in toolCallDeltas) {
                    final map = (tc is Map) ? (tc as Map) : <dynamic, dynamic>{};
                    final idx = (map['index'] as num?)?.toInt() ?? 0;
                    final existing = accumulatedToolCalls.putIfAbsent(
                      idx,
                      () => {
                        'id': map['id'] ?? 'call_$idx',
                        'name': '',
                        'arguments': StringBuffer(),
                      },
                    );
                    if (map['id'] != null &&
                        (map['id'] as String).isNotEmpty) {
                      existing['id'] = map['id'];
                    }
                    final fn = (map['function'] is Map) ? (map['function'] as Map) : null;
                    if (fn != null) {
                      if (fn['name'] != null &&
                          (fn['name'] as String).isNotEmpty) {
                        existing['name'] = fn['name'];
                      }
                      if (fn['arguments'] != null) {
                        (existing['arguments'] as StringBuffer)
                            .write(fn['arguments']);
                      }
                    }
                  }
                }
              }
            }
            if (data.containsKey('usage') && data['usage'] is Map) {
              final u = data['usage'] as Map<String, dynamic>;
              tokenUsage = TokenUsage(
                inputTokens: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
                outputTokens: (u['completion_tokens'] as num?)?.toInt() ?? 0,
              );
            }
          } catch (_) {}
        }

        final toolCalls = <ToolCall>[];
        for (final entry in accumulatedToolCalls.entries) {
          final data = entry.value;
          final name = data['name'] as String? ?? '';
          final rawArgs = (data['arguments'] as StringBuffer).toString();
          Map<String, dynamic> parsedArgs = {};
          try {
            if (rawArgs.trim().isNotEmpty) {
              parsedArgs = jsonDecode(rawArgs) as Map<String, dynamic>;
            }
          } catch (e) {
            _log.warning('Failed to parse streaming tool args: $e');
          }
          if (name.isNotEmpty) {
            toolCalls.add(
              ToolCall(
                id: data['id'] as String? ?? 'call_${entry.key}',
                name: name,
                arguments: parsedArgs,
              ),
            );
          }
        }

        return AIResponse(
          content: contentBuffer.toString(),
          reasoningContent: reasoningBuffer.isNotEmpty
              ? reasoningBuffer.toString()
              : null,
          toolCalls: toolCalls,
          stopReason: finishReason,
          usage: tokenUsage,
        );
      } finally {
        flushTimer?.cancel();
        flushStreamChunk();
        client.close();
      }
    }

    // --- NON-STREAMING FALLBACK PATH ---
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'content-type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Ghost/1.0',
      },
      body: jsonEncode(body),
    ).timeout(
      const Duration(seconds: 180),
      onTimeout: () => throw TimeoutException(
        'Request to $displayName ($baseUrl) timed out after 180s',
      ),
    );

    if (response.statusCode != 200) {
      _log.severe(
        '$displayName API error: ${response.statusCode} - ${response.body}',
      );
      throw ProviderError(
        'OpenAI API error (${response.statusCode}): ${response.body}',
        provider: 'openai',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choice =
        (data['choices'] as List<dynamic>).first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;

    final textContent = message['content'] as String? ?? '';
    // Ollama returns thinking content as 'reasoning'; DeepSeek uses 'reasoning_content'
    final reasoningContent =
        (message['reasoning_content'] as String?) ??
        (message['reasoning'] as String?);
    final toolCalls = <ToolCall>[];

    if (message.containsKey('tool_calls') && message['tool_calls'] != null) {
      final calls = message['tool_calls'] as List<dynamic>;
      for (final call in calls) {
        final callMap = (call is Map) ? (call as Map) : <dynamic, dynamic>{};
        final fn = (callMap['function'] is Map) ? (callMap['function'] as Map) : null;
        if (fn == null) continue;

        final callId =
            callMap['id'] as String? ?? 'call_${calls.indexOf(call)}';
        final fnName = fn['name'] as String?;
        final fnArgs = fn['arguments'] as String? ?? '{}';

        if (fnName == null || fnName.isEmpty) continue;

        try {
          toolCalls.add(
            ToolCall(
              id: callId,
              name: fnName,
              arguments: jsonDecode(fnArgs) as Map<String, dynamic>,
            ),
          );
        } catch (e) {
          _log.warning(
            'Failed to parse tool arguments for $fnName: $e\nRaw args: $fnArgs',
          );
          toolCalls.add(
            ToolCall(
              id: callId,
              name: fnName,
              arguments: {'_error_': 'Invalid JSON in arguments: $fnArgs'},
            ),
          );
        }
      }
    }

    final usage = (data['usage'] is Map) ? (data['usage'] as Map) : null;

    return AIResponse(
      content: textContent,
      reasoningContent: reasoningContent,
      toolCalls: toolCalls,
      stopReason: choice['finish_reason'] as String?,
      usage: usage != null
          ? TokenUsage(
              inputTokens: usage['prompt_tokens'] as int? ?? 0,
              outputTokens: usage['completion_tokens'] as int? ?? 0,
            )
          : null,
    );
  }

  @override
  Future<List<double>> embed(String text, {String? model}) async {
    final embedModel = model ?? 'text-embedding-3-small';
    final url = Uri.parse('$baseUrl/embeddings');

    final body = {'model': embedModel, 'input': text};

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw ProviderError(
        'OpenAI Embeddings API error (${response.statusCode}): ${response.body}',
        provider: _providerId,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final dataList = data['data'] as List<dynamic>;
    if (dataList.isEmpty) return [];

    final embedding = dataList[0]['embedding'] as List<dynamic>;
    return embedding.map((e) => (e as num).toDouble()).toList();
  }

  @override
  Future<bool> isAvailable() async {
    return apiKey.isNotEmpty && !apiKey.startsWith('PLACEHOLDER');
  }

  @override
  Future<void> testConnection() async {
    final url = Uri.parse('$baseUrl/models');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $apiKey'},
    );

    if (response.statusCode != 200) {
      throw ProviderError(
        'OpenAI selection failed (${response.statusCode}): ${response.body}',
        provider: 'openai',
      );
    }
  }

  /// Lists available models for this provider.
  static Future<List<String>> listModels(
    String apiKey, {
    String? baseUrl,
  }) async {
    final url = Uri.parse('${baseUrl ?? 'https://api.openai.com/v1'}/models');
    _log.fine('Fetching models from $url...');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $apiKey'},
    );

    if (response.statusCode == 200) {
      _log.fine('Successfully fetched models from $url');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = data['data'] as List<dynamic>;
      return models.map((m) => m['id'] as String).toList();
    }

    _log.warning(
      'Failed to fetch models from $url: ${response.statusCode} ${response.body}',
    );

    // Fallback known models if list fails
    return [];
  }
}
