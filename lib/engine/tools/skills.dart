import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import '../agent/skills.dart';
import 'registry.dart';
import 'package:path/path.dart' as p;

final _log = Logger('Ghost.Tools.Skills');

/// Tools for managing Ghost skills.
class SkillsTools {
  static void registerAll(ToolRegistry registry, SkillManager skillManager) {
    registry.register(ImportSkillTool(skillManager));
    registry.register(ListSkillsTool(skillManager));
    registry.register(SetSkillGlobalTool(skillManager));
    registry.register(CreateSkillTemplateTool(skillManager));
    registry.register(DebugSkillTool(skillManager));
    registry.register(DownloadGithubSkillTool(skillManager));
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

/// A tool that creates a new skill template.
class CreateSkillTemplateTool extends Tool {
  CreateSkillTemplateTool(this.skillManager);

  final SkillManager skillManager;

  @override
  String get name => 'create_skill_template';

  @override
  String get description =>
      'Creates a new skill folder with a basic template (Python or Node.js). '
      'This is the best way to start building a new skill or MCP server.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'The human-readable name of the skill (e.g. "Spotify Control").',
          },
          'description': {
            'type': 'string',
            'description': 'A short description of what the skill does.',
          },
          'type': {
            'type': 'string',
            'enum': ['python', 'node'],
            'description': 'The runtime to use for the MCP server.',
          },
          'emoji': {
            'type': 'string',
            'description': 'An emoji to represent the skill (optional).',
          },
        },
        'required': ['name', 'description', 'type'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final name = input['name'] as String;
    final description = input['description'] as String;
    final type = input['type'] as String;
    final emoji = input['emoji'] as String?;

    try {
      final skill = await skillManager.createSkillTemplate(
        name: name,
        description: description,
        type: type,
        emoji: emoji,
      );
      
      // Auto-initialize runtimes for the new template
      final skillPath = p.join(skillManager.skillsDir, skill.slug);
      unawaited(skillManager.initializeRuntimes(skill.slug, skillPath));

      return ToolResult(
        output: 'Successfully created skill template "${skill.name}" in .ghost/skills/${skill.slug}. '
            'Files created: SKILL.md, _meta.json, server.${type == 'python' ? 'py' : 'js'}. '
            'The environment is being initialized in the background. '
            'You can now edit these files to implement your tools.',
        metadata: {'slug': skill.slug},
      );
    } catch (e) {
      return ToolResult.error('Failed to create skill template: $e');
    }
  }
}

/// A tool that debugs a skill by running its MCP command.
class DebugSkillTool extends Tool {
  DebugSkillTool(this.skillManager);

  final SkillManager skillManager;

  @override
  String get name => 'debug_skill';

  @override
  String get description =>
      'Runs a skill\'s MCP command and captures its output (stdout/stderr) for a few seconds. '
      'Use this to troubleshoot failing skills or to verify that an MCP server starts correctly.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'slug': {
            'type': 'string',
            'description': 'The slug of the skill to debug.',
          },
        },
        'required': ['slug'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final slug = input['slug'] as String;

    try {
      final log = await skillManager.debugSkill(slug);
      return ToolResult(output: log);
    } catch (e) {
      return ToolResult.error('Failed to debug skill: $e');
    }
  }
}

/// A tool that downloads a skill from GitHub.
class DownloadGithubSkillTool extends Tool {
  DownloadGithubSkillTool(this.skillManager);

  final SkillManager skillManager;

  @override
  String get name => 'download_github_skill';

  @override
  String get description =>
      'Downloads and installs a Ghost skill from a GitHub repository folder. '
      'Example URL: https://github.com/owner/repo/tree/main/skills/my-skill';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The GitHub URL pointing to the skill folder or SKILL.md.',
          },
        },
        'required': ['url'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final url = input['url'] as String;

    try {
      final skill = await skillManager.downloadGithubSkill(url);
      return ToolResult(
        output: 'Successfully downloaded and installed skill "${skill.name}" (${skill.slug}). '
            'You can now activate it globally or for specific agents.',
        metadata: {'slug': skill.slug},
      );
    } catch (e) {
      return ToolResult.error('Failed to download skill from GitHub: $e');
    }
  }
}
