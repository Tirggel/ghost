// Ghost — Session data model.

import '../models/message.dart';

/// Session type.
enum SessionType { main, group, channel }

/// A conversation session between a user and the agent.
class Session {
  Session({
    required this.id,
    required this.agentId,
    this.agentName,
    required this.channelType,
    required this.peerId,
    this.groupId,
    this.type = SessionType.main,
    this.model,
    this.provider,
    this.title,
    List<Message>? history,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  })  : history = history ?? [],
        createdAt = createdAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      agentId: json['agentId'] as String,
      agentName: json['agentName'] as String?,
      channelType: json['channelType'] as String,
      peerId: json['peerId'] as String,
      groupId: json['groupId'] as String?,
      model: json['model'] as String?,
      provider: json['provider'] as String?,
      title: json['title'] as String?,
      type: SessionType.values.firstWhere(
        (t) => t.name == (json['type'] as String?),
        orElse: () => SessionType.main,
      ),
      history: (json['history'] as List<dynamic>?)
              ?.map((m) => Message.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.parse(json['lastActiveAt'] as String)
          : null,
    );
  }

  final String id;
  final String agentId;
  String? agentName;
  final String channelType;
  final String peerId;
  final String? groupId;
  String? model;
  String? provider;
  String? title;
  final SessionType type;
  final List<Message> history;
  final DateTime createdAt;
  DateTime lastActiveAt;

  /// Unique key for identifying this session.
  String get sessionKey =>
      groupId != null ? '$channelType:$groupId' : '$channelType:$peerId';

  /// Add a message to the history.
  void addMessage(Message message) {
    history.add(message);
    lastActiveAt = DateTime.now();
  }

  /// Get the last N messages.
  List<Message> lastMessages(int count) {
    if (count >= history.length) return List.unmodifiable(history);
    return List.unmodifiable(history.sublist(history.length - count));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'agentId': agentId,
        if (agentName != null) 'agentName': agentName,
        'channelType': channelType,
        'peerId': peerId,
        if (groupId != null) 'groupId': groupId,
        if (model != null) 'model': model,
        if (provider != null) 'provider': provider,
        if (title != null) 'title': title,
        'type': type.name,
        'history': history.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
      };

  /// Convert to summary (without full history) for listing.
  Map<String, dynamic> toSummary() => {
        'id': id,
        'agentId': agentId,
        if (agentName != null) 'agentName': agentName,
        'channelType': channelType,
        'peerId': peerId,
        if (model != null) 'model': model,
        if (provider != null) 'provider': provider,
        if (title != null) 'title': title,
        'type': type.name,
        'messageCount': history.length,
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
      };

  int get inputTokens {
    int total = 0;
    for (final m in history) {
      if (m.metadata.containsKey('usage')) {
        final usage = m.metadata['usage'];
        if (usage is Map) {
          total += (usage['input'] as num?)?.toInt() ?? 0;
        }
      }
    }
    return total;
  }

  int get outputTokens {
    int total = 0;
    for (final m in history) {
      if (m.metadata.containsKey('usage')) {
        final usage = m.metadata['usage'];
        if (usage is Map) {
          total += (usage['output'] as num?)?.toInt() ?? 0;
        }
      }
    }
    return total;
  }
}
