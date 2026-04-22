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
  final bool isGlobal;
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
    bool? isGlobal,
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
      isGlobal: isGlobal ?? this.isGlobal,
      hasPython: hasPython ?? this.hasPython,
      hasNode: hasNode ?? this.hasNode,
      hasMcp: hasMcp ?? this.hasMcp,
      mcpCommand: mcpCommand ?? this.mcpCommand,
    );
  }
}
