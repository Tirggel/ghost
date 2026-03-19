// Ghost — Anthropic AI Provider implementation.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../models/message.dart';
import '../../models/provider.dart';
import '../../infra/errors.dart';

final _log = Logger('Ghost.AnthropicProvider');

/// Implementation of Anthropic's Claude models.
class AnthropicProvider implements AIModelProvider {
  AnthropicProvider({
    required this.apiKey,
    this.model = 'claude-3-7-sonnet-20250219',
    this.apiVersion = '2023-06-01',
    this.baseUrl = 'https://api.anthropic.com/v1/messages',
    String? providerId,
    String? displayName,
  })  : _providerId = providerId ?? 'anthropic',
        _displayName = displayName ?? 'Anthropic Claude';

  final String apiKey;
  final String model;
  final String apiVersion;
  final String baseUrl;
  final String _providerId;
  final String _displayName;

  @override
  String get providerId => _providerId;

  @override
  bool get supportsChat => true;

  @override
  String get modelId => model;

  @override
  String get displayName => _displayName;

  @override
  ModelCapabilities get capabilities {
    final lower = model.toLowerCase();
    
    // Claude 3 models support vision
    if (lower.contains('claude-3')) {
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
    final url = Uri.parse(baseUrl);

    final body = {
      'model': model,
      'messages': messages
          .map((m) {
            final role = m.role == 'assistant' ? 'assistant' : 'user';
            
            if (role == 'user' && m.attachments.isNotEmpty) {
              final parts = <Map<String, dynamic>>[];
              for (final a in m.attachments) {
                if (a.mimeType.startsWith('image/')) {
                  parts.add({
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': a.mimeType,
                      'data': a.data,
                    },
                  });
                }
              }
              if (m.content.isNotEmpty) {
                parts.add({'type': 'text', 'text': m.content});
              }
              return {'role': role, 'content': parts};
            }
            
            return {
              'role': role,
              'content': m.content,
            };
          })
          .toList(),
      'max_tokens': maxTokens,
      'temperature': temperature,
      if (systemPrompt != null) 'system': systemPrompt,
      if (tools != null && tools.isNotEmpty)
        'tools': tools.map((t) => t.toJson()).toList(),
    };

    _log.fine('Requesting Anthropic API: $model');

    final response = await http.post(
      url,
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': apiVersion,
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      _log.severe(
          'Anthropic API error: ${response.statusCode} - ${response.body}');
      throw ProviderError(
        'Anthropic API error (${response.statusCode}): ${response.body}',
        provider: 'anthropic',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final contentList = data['content'] as List<dynamic>;

    String textContent = '';
    final toolCalls = <ToolCall>[];

    for (final item in contentList) {
      if (item['type'] == 'text') {
        textContent += (item['text'] as String);
      } else if (item['type'] == 'tool_use') {
        toolCalls.add(ToolCall(
          id: item['id'] as String,
          name: item['name'] as String,
          arguments: item['input'] as Map<String, dynamic>,
        ));
      }
    }

    final usage = data['usage'] as Map<String, dynamic>?;

    return AIResponse(
      content: textContent,
      toolCalls: toolCalls,
      stopReason: data['stop_reason'] as String?,
      usage: usage != null
          ? TokenUsage(
              inputTokens: usage['input_tokens'] as int? ?? 0,
              outputTokens: usage['output_tokens'] as int? ?? 0,
            )
          : null,
    );
  }

  @override
  Future<List<double>> embed(String text, {String? model}) async {
    throw ProviderError(
      'Anthropic does not currently support text embeddings via their standard API.',
      provider: _providerId,
    );
  }

  @override
  Future<bool> isAvailable() async {
    return apiKey.isNotEmpty && !apiKey.startsWith('PLACEHOLDER');
  }

  @override
  Future<void> testConnection() async {
    // Use a models listing endpoint derived from baseUrl to check auth.
    final listUrl =
        baseUrl.replaceAll('/messages', '').replaceAll('/v1', '/v1/models');
    final response = await http.get(
      Uri.parse(listUrl),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': apiVersion,
      },
    );

    if (response.statusCode != 200) {
      throw ProviderError(
        'Anthropic connection failed (${response.statusCode}): ${response.body}',
        provider: _providerId,
      );
    }
  }

  /// Lists available models for this provider.
  static Future<List<String>> listModels(String apiKey) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/models');
      final response = await http.get(
        url,
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final models = data['data'] as List<dynamic>;
        return models.map((m) => m['id'] as String).toList();
      }
    } catch (e) {
      _log.warning('Failed to fetch Anthropic models: $e');
    }

    return [
      'claude-3-7-sonnet-20250219',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
    ];
  }
}
