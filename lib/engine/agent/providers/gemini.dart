// Ghost — Google Gemini AI Model Provider.

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
    
    // Gemini 1.5 and 2.0 are fully multimodal
    if (lower.contains('gemini-1.5') || lower.contains('gemini-2.0')) {
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
  }) async {
    final normalizedModel =
        model.startsWith('models/') ? model : 'models/$model';
    final generativeModel = GenerativeModel(
      model: normalizedModel,
      apiKey: apiKey,
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
    );

    final text = response.text ?? '';
    final toolCalls = <ToolCall>[];

    // Handle function calls
    final functionCalls = response.functionCalls.toList();
    for (final call in functionCalls) {
      toolCalls.add(ToolCall(
        id: 'gemini-${DateTime.now().microsecondsSinceEpoch}',
        name: call.name,
        arguments: call.args,
      ));
    }

    return AIResponse(
      content: text,
      toolCalls: toolCalls,
      usage: TokenUsage(
        inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
        outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
      ),
    );
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
    return messages.map((m) {
      if (m.role == 'user') {
        if (m.attachments.isEmpty) {
          return Content.text(m.content);
        }
        final parts = <Part>[];
        if (m.content.isNotEmpty) {
          parts.add(TextPart(m.content));
        }
        for (final a in m.attachments) {
          parts.add(DataPart(a.mimeType, base64Decode(a.data)));
        }
        return Content('user', parts);
      } else if (m.role == 'assistant') {
        final parts = <Part>[];
        if (m.content.isNotEmpty) {
          parts.add(TextPart(m.content));
        }

        final toolCalls = m.metadata['tool_calls'] as List<dynamic>?;
        if (toolCalls != null) {
          for (final call in toolCalls) {
            final map = call as Map<String, dynamic>;
            parts.add(FunctionCall(
              map['name'] as String,
              map['arguments'] as Map<String, dynamic>,
            ));
          }
        }

        // Gemini requires at least one part. If both are empty, add empty text.
        if (parts.isEmpty) parts.add(TextPart(''));

        return Content.model(parts);
      } else if (m.role == 'tool') {
        return Content.functionResponse(
          m.metadata['tool_name'] as String? ?? 'unknown',
          {'result': m.content},
        );
      }
      return Content.text(m.content);
    }).toList();
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

  Schema _convertToGeminiSchema(Map<String, dynamic> schema) {
    final type = schema['type'] as String?;
    final description = schema['description'] as String?;
    final properties = schema['properties'] as Map<String, dynamic>?;
    final required = schema['required'] as List<dynamic>?;

    if (type == 'object') {
      final geminiProps = <String, Schema>{};
      if (properties != null) {
        properties.forEach((key, value) {
          geminiProps[key] =
              _convertToGeminiSchema(value as Map<String, dynamic>);
        });
      }
      return Schema.object(
        properties: geminiProps,
        requiredProperties: required?.cast<String>(),
        description: description,
      );
    } else if (type == 'string') {
      return Schema.string(description: description);
    } else if (type == 'number' || type == 'integer') {
      return Schema.number(description: description);
    } else if (type == 'boolean') {
      return Schema.boolean(description: description);
    } else if (type == 'array') {
      return Schema.array(
        items: _convertToGeminiSchema(schema['items'] as Map<String, dynamic>),
        description: description,
      );
    }

    return Schema.string(description: description);
  }
}
