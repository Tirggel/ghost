import 'dart:async';
import 'package:logging/logging.dart';
import '../agent/skills.dart';
import 'registry.dart';

final _log = Logger('Ghost.Tools.Skills');

/// Tools for managing Ghost skills.
class SkillsTools {
  static void registerAll(ToolRegistry registry, SkillManager skillManager) {
    registry.register(ImportSkillTool(skillManager));
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
            'The environment has been initialized. The skill is now permanent and manageable.',
        metadata: {'slug': skill.slug},
      );
    } catch (e) {
      return ToolResult.error('Failed to import skill: $e');
    }
  }
}
