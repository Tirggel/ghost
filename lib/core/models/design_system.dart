class DesignSystem {
  const DesignSystem({
    required this.id,
    required this.name,
    this.content = '',
  });

  factory DesignSystem.fromJson(Map<String, dynamic> json) {
    return DesignSystem(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String content;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
      };
}
