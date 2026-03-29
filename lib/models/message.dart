// Ghost — Message data model.

/// A message in a conversation.
class Message {
  const Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.metadata = const {},
    this.attachments = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((a) => MessageAttachment.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// The role of the message sender: "user", "assistant", "system", "tool".
  final String role;

  /// The message content.
  final String content;

  /// When the message was created.
  final DateTime timestamp;

  /// Additional metadata (channel info, tool results, etc.).
  final Map<String, dynamic> metadata;

  /// Attachments associated with this message (images, files, etc.).
  final List<MessageAttachment> attachments;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  @override
  String toString() =>
      'Message{role: $role, content: "${content.length > 50 ? '${content.substring(0, 50)}...' : content}", attachments: ${attachments.length}}';
}

/// An attachment to a message.
class MessageAttachment {
  const MessageAttachment({
    required this.name,
    required this.mimeType,
    required this.data,
  });

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    return MessageAttachment(
      name: json['name'] as String,
      mimeType: json['mimeType'] as String,
      data: json['data'] as String,
    );
  }

  final String name;
  final String mimeType;

  /// Base64 encoded or raw bytes (internally stored as Base64 in JSON).
  final String data;

  Map<String, dynamic> toJson() => {
        'name': name,
        'mimeType': mimeType,
        'data': data,
      };
}
