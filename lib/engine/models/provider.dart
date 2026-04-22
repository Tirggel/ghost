// Ghost — AI Model Provider interface.

import 'message.dart';

/// Abstract interface for AI model providers (Anthropic, OpenAI, etc.).
abstract class AIModelProvider {
  /// Provider identifier (e.g., "anthropic", "openai").
  String get providerId;

  /// Model identifier (e.g., "claude-sonnet-4-20250514", "gpt-4o").
  String get modelId;

  /// Display name.
  String get displayName;

  /// Whether the provider supports chat completions.
  bool get supportsChat;

  /// Send a conversation and get a response.
  Future<AIResponse> chat({
    required List<Message> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    double temperature = 0.7,
    List<ToolDefinition>? tools,
  });

  /// Generate embeddings for the given text.
  Future<List<double>> embed(String text, {String? model});

  /// Get the capabilities of the current model.
  ModelCapabilities get capabilities;

  /// Check if the provider is configured and ready.
  Future<bool> isAvailable();

  /// Actually test the connection to the provider.
  Future<void> testConnection();
}

/// Defines the modalities supported by a model.
class ModelCapabilities {
  const ModelCapabilities({
    this.supportsText = true,
    this.supportsImage = false,
    this.supportsVideo = false,
    this.supportsAudio = false,
    this.supportsPdf = false,
  });

  factory ModelCapabilities.textOnly() => const ModelCapabilities();

  factory ModelCapabilities.all() => const ModelCapabilities(
        supportsImage: true,
        supportsVideo: true,
        supportsAudio: true,
        supportsPdf: true,
      );

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) {
    return ModelCapabilities(
      supportsText: json['text'] as bool? ?? true,
      supportsImage: json['image'] as bool? ?? false,
      supportsVideo: json['video'] as bool? ?? false,
      supportsAudio: json['audio'] as bool? ?? false,
      supportsPdf: json['pdf'] as bool? ?? false,
    );
  }

  final bool supportsText;
  final bool supportsImage;
  final bool supportsVideo;
  final bool supportsAudio;
  final bool supportsPdf;

  Map<String, bool> toJson() => {
        'text': supportsText,
        'image': supportsImage,
        'video': supportsVideo,
        'audio': supportsAudio,
        'pdf': supportsPdf,
      };
}

/// Response from an AI model.
class AIResponse {
  const AIResponse({
    required this.content,
    this.toolCalls = const [],
    this.usage,
    this.stopReason,
  });

  /// The text response content.
  final String content;

  /// Tool calls requested by the model.
  final List<ToolCall> toolCalls;

  /// Token usage information.
  final TokenUsage? usage;

  /// Why the model stopped generating.
  final String? stopReason;

  /// Whether the model requested tool calls.
  bool get hasToolCalls => toolCalls.isNotEmpty;

  AIResponse copyWith({
    String? content,
    List<ToolCall>? toolCalls,
    TokenUsage? usage,
    String? stopReason,
  }) {
    return AIResponse(
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      usage: usage ?? this.usage,
      stopReason: stopReason ?? this.stopReason,
    );
  }
}

/// A tool call requested by the model.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: json['arguments'] as Map<String, dynamic>,
    );
  }

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
      };
}

/// Token usage information for a model response.
class TokenUsage {
  const TokenUsage({this.inputTokens = 0, this.outputTokens = 0});

  final int inputTokens;
  final int outputTokens;
  int get totalTokens => inputTokens + outputTokens;
}

/// Definition of a tool the model can call.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };
}
