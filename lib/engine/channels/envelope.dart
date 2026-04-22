// Ghost — Message envelope (normalized message format).

/// A normalized message envelope.
///
/// All channel-specific message formats are converted to this
/// unified representation for processing by the router and agent.
class Envelope {
  const Envelope({
    required this.id,
    required this.channelType,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.groupId,
    this.media = const [],
    this.metadata = const {},
  });

  factory Envelope.fromJson(Map<String, dynamic> json) {
    return Envelope(
      id: json['id'] as String,
      channelType: json['channelType'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      groupId: json['groupId'] as String?,
      media: (json['media'] as List<dynamic>?)
              ?.map((m) => MediaAttachment.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Unique message identifier.
  final String id;

  /// Channel type (e.g., "telegram", "discord", "webchat").
  final String channelType;

  /// Sender identifier (channel-specific).
  final String senderId;

  /// Group/channel ID (null for DMs).
  final String? groupId;

  /// Message text content.
  final String content;

  /// Media attachments.
  final List<MediaAttachment> media;

  /// Message timestamp.
  final DateTime timestamp;

  /// Channel-specific metadata.
  final Map<String, dynamic> metadata;

  /// True if this is a group message.
  bool get isGroup => groupId != null;

  /// True if message has media attachments.
  bool get hasMedia => media.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'channelType': channelType,
        'senderId': senderId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (groupId != null) 'groupId': groupId,
        'media': media.map((m) => m.toJson()).toList(),
        'metadata': metadata,
      };

  @override
  String toString() =>
      'Envelope{$channelType:$senderId, content: "${content.length > 50 ? '${content.substring(0, 50)}...' : content}"}';
}

/// A media attachment on a message.
class MediaAttachment {
  const MediaAttachment({
    required this.type,
    required this.url,
    this.mimeType,
    this.sizeBytes,
    this.filename,
    this.caption,
  });

  factory MediaAttachment.fromJson(Map<String, dynamic> json) {
    return MediaAttachment(
      type: MediaType.values.firstWhere(
        (t) => t.name == (json['type'] as String),
        orElse: () => MediaType.file,
      ),
      url: json['url'] as String,
      mimeType: json['mimeType'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      filename: json['filename'] as String?,
      caption: json['caption'] as String?,
    );
  }

  final MediaType type;
  final String url;
  final String? mimeType;
  final int? sizeBytes;
  final String? filename;
  final String? caption;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'url': url,
        if (mimeType != null) 'mimeType': mimeType,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (filename != null) 'filename': filename,
        if (caption != null) 'caption': caption,
      };
}

/// Types of media attachments.
enum MediaType { image, audio, video, document, sticker, file }
