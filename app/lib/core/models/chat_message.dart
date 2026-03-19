class ChatMessage {
  final String role;
  final String content;
  final String? timestamp;
  final Map<String, dynamic>? metadata;
  final List<ChatAttachment>? attachments;

  ChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
    this.metadata,
    this.attachments,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: json['timestamp'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      attachments: (json['attachments'] as List<dynamic>?)
          ?.map((a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp,
      'metadata': metadata,
      'attachments': attachments?.map((a) => a.toJson()).toList(),
    };
  }

  bool get isAssistant => role == 'assistant';
  bool get isUser => role == 'user';
  bool get isSystem => role == 'system';
}

class ChatAttachment {
  final String name;
  final String mimeType;
  final String data;

  ChatAttachment({
    required this.name,
    required this.mimeType,
    required this.data,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      name: json['name'] as String,
      mimeType: json['mimeType'] as String,
      data: json['data'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'mimeType': mimeType,
      'data': data,
    };
  }
}
