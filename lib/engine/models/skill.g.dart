// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skill.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Skill _$SkillFromJson(Map<String, dynamic> json) => Skill(
  slug: json['slug'] as String,
  name: json['name'] as String,
  description: json['description'] as String? ?? '',
  emoji: json['emoji'] as String?,
  category: json['category'] as String? ?? 'general',
  requiresHitl: json['requiresHitl'] as bool? ?? false,
  securityLevel: json['securityLevel'] as String? ?? 'standard',
  requiredSkills:
      (json['requiredSkills'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  hasPython: json['hasPython'] as bool? ?? false,
  hasNode: json['hasNode'] as bool? ?? false,
  hasMcp: json['hasMcp'] as bool? ?? false,
  mcpCommand: json['mcpCommand'] as String?,
);

Map<String, dynamic> _$SkillToJson(Skill instance) => <String, dynamic>{
  'slug': instance.slug,
  'name': instance.name,
  'description': instance.description,
  'emoji': instance.emoji,
  'category': instance.category,
  'requiresHitl': instance.requiresHitl,
  'securityLevel': instance.securityLevel,
  'requiredSkills': instance.requiredSkills,
  'hasPython': instance.hasPython,
  'hasNode': instance.hasNode,
  'hasMcp': instance.hasMcp,
  'mcpCommand': instance.mcpCommand,
};
