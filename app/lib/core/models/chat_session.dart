class ChatSession {
  final String id;
  final String? title;
  final String? model;
  final String? provider;
  final int messageCount;
  final String? agentName;
  final String? agentId;
  final DateTime? createdAt;

  ChatSession({
    required this.id,
    this.title,
    this.model,
    this.provider,
    required this.messageCount,
    this.agentName,
    this.agentId,
    this.createdAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String?,
      model: json['model'] as String?,
      provider: json['provider'] as String?,
      messageCount: json['messageCount'] as int? ?? 0,
      agentName: json['agentName'] as String?,
      agentId: json['agentId'] as String?,
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'] as String) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'model': model,
      'provider': provider,
      'messageCount': messageCount,
      'agentName': agentName,
      'agentId': agentId,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  dynamic operator [](String key) {
    switch (key) {
      case 'id': return id;
      case 'title': return title;
      case 'model': return model;
      case 'provider': return provider;
      case 'messageCount': return messageCount;
      case 'agentName': return agentName;
      case 'agentId': return agentId;
      case 'createdAt': return createdAt;
      default: return null;
    }
  }
}
