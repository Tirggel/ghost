import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import '../agent/skills.dart';
import 'registry.dart';

final _log = Logger('Ghost.Tools.Skills');

/// Tools for managing Ghost skills.
class SkillsTools {
  static void registerAll(ToolRegistry registry, SkillManager skillManager) {
    registry.register(ImportSkillTool(skillManager));
    registry.register(ListSkillsTool(skillManager));
    registry.register(SetSkillGlobalTool(skillManager));
  }
}

/// A tool that imports a local directory as a permanent Ghost skill.
class ImportSkillTool extends Tool {
  ImportSkillTool(this.skillManager);

  final SkillManager skillManager;

  @override
  String get name => 'import_skill';

  @override
  String get description =>
      'Imports a local directory as a permanent Ghost skill. '
      'The folder will be moved to the managed .ghost/skills/ directory '
      'and its runtime environment (Python venv or Node modules) will be initialized. '
      'Use this after you have created a new skill or MCP server in a temporary folder.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or relative path to the skill directory to import.',
          },
        },
        'required': ['path'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final path = input['path'] as String;
    
    _log.info('Importing skill from $path');

    try {
      final skill = await skillManager.installSkillFromDirectory(path, moveSource: true);
      return ToolResult(
        output: 'Successfully imported skill "${skill.name}" (slug: ${skill.slug}) to .ghost/skills/. '
            'The environment has been initialized. The skill is now permanent and manageable. '
            'To activate it for all agents, use "set_skill_global".',
        metadata: {'slug': skill.slug},
      );
    } catch (e) {
      return ToolResult.error('Failed to import skill: $e');
    }
  }
}

/// A tool that lists all installed Ghost skills.
class ListSkillsTool extends Tool {
  ListSkillsTool(this.skillManager);

  final SkillManager skillManager;

  @override
  String get name => 'list_skills';

  @override
  String get description => 'List all installed Ghost skills.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    try {
      final skills = await skillManager.loadSkills();
      final result = skills.map((s) => s.toJson()).toList();
      return ToolResult(output: jsonEncode(result));
    } catch (e) {
      return ToolResult.error('Failed to list skills: $e');
    }
  }
}

/// A tool that activates or deactivates a skill globally for all agents.
class SetSkillGlobalTool extends Tool {
  SetSkillGlobalTool(this.skillManager);

  final SkillManager skillManager;

  @override
  String get name => 'set_skill_global';

  @override
  String get description => 'Activate or deactivate a skill globally for all agents.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'slug': {
            'type': 'string',
            'description': 'The slug of the skill (e.g. "context7-skill").',
          },
          'isGlobal': {
            'type': 'boolean',
            'description': 'Whether the skill should be active for all agents.',
          },
        },
        'required': ['slug', 'isGlobal'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final slug = input['slug'] as String;
    final isGlobal = input['isGlobal'] as bool;

    try {
      await skillManager.setGlobal(slug, isGlobal);
      return ToolResult(
        output: 'Successfully set skill "$slug" global status to $isGlobal. '
            'The skill context is now being rebuilt for all agents.',
      );
    } catch (e) {
      return ToolResult.error('Failed to set skill global status: $e');
    }
  }
}
