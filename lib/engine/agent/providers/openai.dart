// Ghost — OpenAI Provider implementation.

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
  })  : _displayName = displayName,
        _providerId = providerId ?? 'openai';

  final String apiKey;
  final String model;
  final String baseUrl;
  final String? _displayName;
  final String _providerId;

  /// If true, this is a reasoning model (e.g. deepseek-reasoner) that requires
  /// special message handling — tool call history must be sanitized.
  final bool isReasoningModel;

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
      return const ModelCapabilities(
        supportsText: true,
        supportsImage: true,
      );
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
              'image_url': {
                'url': 'data:${a.mimeType};base64,${a.data}',
              },
            });
          }
        }
        content = parts;
      } else {
        content = m.content;
      }

      final msg = <String, dynamic>{
        'role': m.role,
        'content': content,
      };

      if (m.metadata.containsKey('reasoning_content')) {
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
              }
            };
          }).toList();
        }
      }

      apiMessages.add(msg);
    }

    final body = {
      'model': model,
      'messages': apiMessages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      if (tools != null && tools.isNotEmpty)
        'tools': tools
            .map((t) => {
                  'type': 'function',
                  'function': {
                    'name': t.name,
                    'description': t.description,
                    'parameters': t.inputSchema,
                  }
                })
            .toList(),
    };

    _log.fine('Requesting $displayName ($baseUrl): $model');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      _log.severe(
          '$displayName API error: ${response.statusCode} - ${response.body}');
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
    final reasoningContent = message['reasoning_content'] as String?;
    final toolCalls = <ToolCall>[];

    if (message.containsKey('tool_calls') && message['tool_calls'] != null) {
      final calls = message['tool_calls'] as List<dynamic>;
      for (final call in calls) {
        final callMap = call as Map<String, dynamic>;
        final fn = callMap['function'] as Map<String, dynamic>?;
        if (fn == null) continue;

        final callId =
            callMap['id'] as String? ?? 'call_${calls.indexOf(call)}';
        final fnName = fn['name'] as String?;
        final fnArgs = fn['arguments'] as String? ?? '{}';

        if (fnName == null || fnName.isEmpty) continue;

        try {
          toolCalls.add(ToolCall(
            id: callId,
            name: fnName,
            arguments: jsonDecode(fnArgs) as Map<String, dynamic>,
          ));
        } catch (e) {
          _log.warning('Failed to parse tool arguments for $fnName: $e\nRaw args: $fnArgs');
          toolCalls.add(ToolCall(
            id: callId,
            name: fnName,
            arguments: {'_error_': 'Invalid JSON in arguments: $fnArgs'},
          ));
        }
      }
    }

    final usage = data['usage'] as Map<String, dynamic>?;

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

    final body = {
      'model': embedModel,
      'input': text,
    };

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
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
    );

    if (response.statusCode != 200) {
      throw ProviderError(
        'OpenAI selection failed (${response.statusCode}): ${response.body}',
        provider: 'openai',
      );
    }
  }

  /// Lists available models for this provider.
  static Future<List<String>> listModels(String apiKey,
      {String? baseUrl}) async {
    final url = Uri.parse('${baseUrl ?? 'https://api.openai.com/v1'}/models');
    _log.fine('Fetching models from $url...');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
    );

    if (response.statusCode == 200) {
      _log.fine('Successfully fetched models from $url');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = data['data'] as List<dynamic>;
      return models.map((m) => m['id'] as String).toList();
    }

    _log.warning('Failed to fetch models from $url: ${response.statusCode} ${response.body}');


    // Fallback known models if list fails
    return [];
  }
}
