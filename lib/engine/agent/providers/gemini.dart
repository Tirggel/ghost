// Ghost — Google Gemini AI Model Provider.

import 'dart:async';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../models/message.dart';
import '../../models/provider.dart';

final _log = Logger('Ghost.GeminiProvider');

/// Provider for Google Gemini models via google_generative_ai.
class GeminiProvider extends AIModelProvider {
  GeminiProvider({
    required this.apiKey,
    required this.model,
  });

  final String apiKey;
  final String model;

  @override
  String get providerId => 'google';

  @override
  bool get supportsChat => true;

  @override
  String get modelId => model;

  @override
  String get displayName => 'Google $model';

  @override
  ModelCapabilities get capabilities {
    final lower = model.toLowerCase();
    
    // Gemini 1.5, 2.0, 2.5, 3 are fully multimodal
    if (lower.contains('gemini-1.5') ||
        lower.contains('gemini-2.0') ||
        lower.contains('gemini-2.5') ||
        lower.contains('gemini-3')) {
      return const ModelCapabilities(
        supportsText: true,
        supportsImage: true,
        supportsVideo: true,
        supportsAudio: true,
        supportsPdf: true,
      );
    }
    
    // Default or older models
    return ModelCapabilities.textOnly();
  }

  @override
  Future<AIResponse> chat({
    required List<Message> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    double temperature = 0.7,
    List<ToolDefinition>? tools,
    void Function(String chunk)? onPartialResponse,
  }) async {
    final normalizedModel =
        model.startsWith('models/') ? model : 'models/$model';
    final interceptingClient = _InterceptingHttpClient(http.Client());

    try {
      final generativeModel = GenerativeModel(
        model: normalizedModel,
        apiKey: apiKey,
        httpClient: interceptingClient,
        systemInstruction:
            systemPrompt != null ? Content.system(systemPrompt) : null,
        tools: tools != null ? [_buildTools(tools)] : null,
      );

      final history = _convertToGeminiHistory(messages);

      final response = await generativeModel.generateContent(
        history,
        generationConfig: GenerationConfig(
          maxOutputTokens: maxTokens,
          temperature: temperature,
        ),
      ).timeout(
        const Duration(seconds: 180),
        onTimeout: () => throw TimeoutException('Request to Google Gemini ($model) timed out after 180s'),
      );

      // Extract raw thought signature and separate reasoning content from raw JSON response
      String? extractedThoughtSignature;
      String? extractedReasoningContent;
      String? extractedVisibleText;

      if (interceptingClient.lastResponseBody != null) {
        try {
          final decoded = jsonDecode(interceptingClient.lastResponseBody!)
              as Map<String, dynamic>;
          final candidates = decoded['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final firstCandidate = candidates.first as Map<String, dynamic>;
            final content = firstCandidate['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null) {
              final visibleBuffer = StringBuffer();
              final reasoningBuffer = StringBuffer();

              for (final part in parts) {
                if (part is Map<String, dynamic>) {
                  final isThought = part['thought'] == true;
                  final text = part['text'] as String?;
                  if (text != null && text.isNotEmpty) {
                    if (isThought) {
                      reasoningBuffer.write(text);
                    } else {
                      visibleBuffer.write(text);
                    }
                  }

                  if (extractedThoughtSignature == null) {
                    final sig = part['thoughtSignature'] ??
                        part['thought_signature'] ??
                        (part['functionCall'] is Map
                            ? (part['functionCall'] as Map)['thoughtSignature'] ??
                                (part['functionCall'] as Map)['thought_signature']
                            : null);
                    if (sig != null && sig is String && sig.isNotEmpty) {
                      extractedThoughtSignature = sig;
                    }
                  }
                }
              }

              if (visibleBuffer.isNotEmpty) {
                extractedVisibleText = visibleBuffer.toString();
              }
              if (reasoningBuffer.isNotEmpty) {
                extractedReasoningContent = reasoningBuffer.toString();
              }
            }
          }
        } catch (e) {
          _log.fine('Could not inspect raw response body: $e');
        }
      }

      final text = extractedVisibleText ?? response.text ?? '';
      final toolCalls = <ToolCall>[];

      // Handle function calls
      final functionCalls = response.functionCalls.toList();
      for (int idx = 0; idx < functionCalls.length; idx++) {
        final call = functionCalls[idx];
        // Per Gemini multi-turn spec: only the first functionCall receives the thought signature
        final sig = idx == 0 ? extractedThoughtSignature : null;
        toolCalls.add(ToolCall(
          id: 'gemini-${DateTime.now().microsecondsSinceEpoch}-$idx',
          name: call.name,
          arguments: call.args,
          thoughtSignature: sig,
        ));
      }

      if (onPartialResponse != null && text.isNotEmpty) {
        onPartialResponse(text);
      }

      return AIResponse(
        content: text,
        reasoningContent: extractedReasoningContent,
        toolCalls: toolCalls,
        usage: TokenUsage(
          inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
          outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
        ),
      );
    } finally {
      interceptingClient.close();
    }
  }

  @override
  Future<List<double>> embed(String text, {String? model}) async {
    final embedModel = model ?? 'text-embedding-004';
    final cleanModel = embedModel.replaceFirst('models/', '');
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$cleanModel:embedContent?key=$apiKey');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': 'models/$cleanModel',
        'content': {
          'parts': [
            {'text': text}
          ]
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini Embeddings API error (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final values = data['embedding']['values'] as List<dynamic>;
    return values.map((e) => (e as num).toDouble()).toList();
  }

  @override
  Future<bool> isAvailable() async {
    return apiKey.isNotEmpty;
  }

  @override
  Future<void> testConnection() async {
    // Simple verification call that is more reliable than generateContent
    // because it doesn't depend on a specific model permission.
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
    final response = await http.get(url);

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      final message = error['error']?['message'] ?? response.body;
      throw Exception('Gemini verification failed: $message');
    }
  }

  /// Lists available models for this provider.
  static Future<List<String>> listModels(String apiKey) async {
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final models = data['models'] as List<dynamic>;
        return models
            .map((m) => m['name'] as String)
            .where((name) => name.contains('gemini'))
            .map((name) => name.replaceFirst('models/', ''))
            .toList();
      }
    } catch (e) {
      _log.warning('Failed to fetch Gemini models: $e');
    }

    // Fallback known models if list fails
    return [];
  }

  List<Content> _convertToGeminiHistory(List<Message> messages) {
    final history = <Content>[];

    int i = 0;
    while (i < messages.length) {
      final m = messages[i];

      if (m.role == 'user') {
        if (m.attachments.isEmpty) {
          history.add(Content.text(m.content));
        } else {
          final parts = <Part>[];
          if (m.content.isNotEmpty) {
            parts.add(TextPart(m.content));
          }
          for (final a in m.attachments) {
            parts.add(DataPart(a.mimeType, base64Decode(a.data)));
          }
          if (parts.isEmpty) parts.add(TextPart(''));
          history.add(Content('user', parts));
        }
        i++;
      } else if (m.role == 'assistant') {
        final parts = <Part>[];
        if (m.content.isNotEmpty) {
          parts.add(TextPart(m.content));
        }

        final toolCalls = m.metadata['tool_calls'] as List<dynamic>?;
        if (toolCalls != null) {
          for (int callIdx = 0; callIdx < toolCalls.length; callIdx++) {
            final call = toolCalls[callIdx];
            final map = call is Map<String, dynamic>
                ? call
                : (call as Map).cast<String, dynamic>();

            final rawSig = map['thought_signature'] as String? ??
                map['thoughtSignature'] as String?;
            final sig = callIdx == 0
                ? (rawSig != null && rawSig.isNotEmpty
                    ? rawSig
                    : 'skip_thought_signature_validator')
                : null;

            final argsRaw = map['arguments'];
            final args = argsRaw is Map
                ? Map<String, dynamic>.from(argsRaw)
                : <String, dynamic>{};

            parts.add(_GeminiFunctionCallPart(
              name: map['name'] as String,
              args: args,
              thoughtSignature: sig,
            ));
          }
        }

        // Gemini requires at least one part. If both are empty, add empty text.
        if (parts.isEmpty) parts.add(TextPart(''));

        history.add(Content.model(parts));
        i++;
      } else if (m.role == 'tool') {
        // Collect ALL consecutive tool messages into a single user turn with FunctionResponses.
        // Google Gemini does not support role: 'function', tool results must be provided
        // as FunctionResponse parts under role: 'user'.
        final responses = <FunctionResponse>[];
        while (i < messages.length && messages[i].role == 'tool') {
          final toolMsg = messages[i];
          final toolName =
              toolMsg.metadata['tool_name'] as String? ?? 'unknown';

          Map<String, Object?> responseMap;
          try {
            final decoded = jsonDecode(toolMsg.content);
            if (decoded is Map<String, dynamic>) {
              responseMap = decoded;
            } else {
              responseMap = {'result': decoded};
            }
          } catch (_) {
            responseMap = {'result': toolMsg.content};
          }

          responses.add(FunctionResponse(toolName, responseMap));
          i++;
        }

        history.add(Content('user', responses));
      } else {
        if (m.content.isNotEmpty) {
          history.add(Content.text(m.content));
        }
        i++;
      }
    }

    return history;
  }

  Tool _buildTools(List<ToolDefinition> toolDefinitions) {
    final functionDeclarations = toolDefinitions.map((d) {
      return FunctionDeclaration(
        d.name,
        d.description,
        _convertToGeminiSchema(d.inputSchema),
      );
    }).toList();

    return Tool(functionDeclarations: functionDeclarations);
  }

  Schema _convertToGeminiSchema(Map<dynamic, dynamic> schema) {
    final type = schema['type']?.toString();
    final description = schema['description']?.toString();
    final rawProperties = schema['properties'];
    final properties = rawProperties is Map ? rawProperties : null;
    final rawRequired = schema['required'];
    final required = rawRequired is List
        ? rawRequired.map((e) => e.toString()).toList()
        : null;

    if (type == 'object') {
      final geminiProps = <String, Schema>{};
      if (properties != null) {
        properties.forEach((key, value) {
          if (value is Map) {
            geminiProps[key.toString()] = _convertToGeminiSchema(value);
          } else {
            geminiProps[key.toString()] = Schema.string();
          }
        });
      }
      return Schema.object(
        properties: geminiProps,
        requiredProperties: required,
        description: description,
      );
    } else if (type == 'string') {
      return Schema.string(description: description);
    } else if (type == 'number' || type == 'integer') {
      return Schema.number(description: description);
    } else if (type == 'boolean') {
      return Schema.boolean(description: description);
    } else if (type == 'array') {
      final rawItems = schema['items'];
      final itemsSchema = rawItems is Map
          ? _convertToGeminiSchema(rawItems)
          : Schema.string();
      return Schema.array(
        items: itemsSchema,
        description: description,
      );
    }

    return Schema.string(description: description);
  }
}

/// Custom implementation of [Part] for Gemini function calls.
/// 
/// The `google_generative_ai` package's built-in `FunctionCall` only serializes
/// `name` and `args`, dropping `thought_signature`. Gemini 2.5 / 3 models strictly
/// validate that multi-turn function calls include `thought_signature` (or the official
/// fallback `skip_thought_signature_validator`), otherwise rejecting the turn with HTTP 400.
class _GeminiFunctionCallPart implements Part {
  final String name;
  final Map<String, dynamic> args;
  final String? thoughtSignature;

  _GeminiFunctionCallPart({
    required this.name,
    required this.args,
    this.thoughtSignature,
  });

  @override
  Object toJson() {
    final json = <String, Object?>{
      'functionCall': {
        'name': name,
        'args': args,
      },
    };
    if (thoughtSignature != null && thoughtSignature!.isNotEmpty) {
      json['thoughtSignature'] = thoughtSignature;
      json['thought_signature'] = thoughtSignature;
    }
    return json;
  }
}

/// Custom HTTP client that taps the raw response stream so we can extract
/// model-internal metadata (thought_signature, separate reasoning parts)
/// that `google_generative_ai: 0.4.7` discards during its internal parsing.
class _InterceptingHttpClient extends http.BaseClient {
  _InterceptingHttpClient(this._inner);

  final http.Client _inner;
  String? lastResponseBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final streamedResponse = await _inner.send(request);
    final bytes = await streamedResponse.stream.toBytes();
    try {
      lastResponseBody = utf8.decode(bytes);
    } catch (_) {
      lastResponseBody = null;
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      streamedResponse.statusCode,
      contentLength: bytes.length,
      request: streamedResponse.request,
      headers: streamedResponse.headers,
      isRedirect: streamedResponse.isRedirect,
      persistentConnection: streamedResponse.persistentConnection,
      reasonPhrase: streamedResponse.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
