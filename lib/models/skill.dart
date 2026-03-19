// Ghost — Skill Data Model

import 'package:json_annotation/json_annotation.dart';

part 'skill.g.dart';

@JsonSerializable()
class Skill {
  Skill({
    required this.slug,
    required this.name,
    this.description = '',
    this.emoji,
    this.isGlobal = false,
  });

  factory Skill.fromJson(Map<String, dynamic> json) => _$SkillFromJson(json);

  final String slug;
  final String name;
  final String description;
  final String? emoji;
  final bool isGlobal;

  Map<String, dynamic> toJson() => _$SkillToJson(this);

  Skill copyWith({
    String? slug,
    String? name,
    String? description,
    String? emoji,
    bool? isGlobal,
  }) {
    return Skill(
      slug: slug ?? this.slug,
      name: name ?? this.name,
      description: description ?? this.description,
      emoji: emoji ?? this.emoji,
      isGlobal: isGlobal ?? this.isGlobal,
    );
  }
}
