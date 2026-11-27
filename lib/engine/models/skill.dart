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
    this.category = 'general',
    this.requiresHitl = false,
    this.securityLevel = 'standard',
    this.requiredSkills = const [],
    this.hasPython = false,
    this.hasNode = false,
    this.hasMcp = false,
    this.mcpCommand,
  });

  factory Skill.fromJson(Map<String, dynamic> json) => _$SkillFromJson(json);

  final String slug;
  final String name;
  final String description;
  final String? emoji;
  final String category;
  final bool requiresHitl;
  final String securityLevel;
  final List<String> requiredSkills;

  final bool hasPython;
  final bool hasNode;
  final bool hasMcp;
  final String? mcpCommand;

  Map<String, dynamic> toJson() => _$SkillToJson(this);

  Skill copyWith({
    String? slug,
    String? name,
    String? description,
    String? emoji,
    String? category,
    bool? requiresHitl,
    String? securityLevel,
    List<String>? requiredSkills,
    bool? hasPython,
    bool? hasNode,
    bool? hasMcp,
    String? mcpCommand,
  }) {
    return Skill(
      slug: slug ?? this.slug,
      name: name ?? this.name,
      description: description ?? this.description,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      requiresHitl: requiresHitl ?? this.requiresHitl,
      securityLevel: securityLevel ?? this.securityLevel,
      requiredSkills: requiredSkills ?? this.requiredSkills,
      hasPython: hasPython ?? this.hasPython,
      hasNode: hasNode ?? this.hasNode,
      hasMcp: hasMcp ?? this.hasMcp,
      mcpCommand: mcpCommand ?? this.mcpCommand,
    );
  }
}
