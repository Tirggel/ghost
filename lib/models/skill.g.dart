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
      isGlobal: json['isGlobal'] as bool? ?? false,
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
      'isGlobal': instance.isGlobal,
      'hasPython': instance.hasPython,
      'hasNode': instance.hasNode,
      'hasMcp': instance.hasMcp,
      'mcpCommand': instance.mcpCommand,
    };
