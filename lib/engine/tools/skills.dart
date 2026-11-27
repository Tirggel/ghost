import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../agent/ontology/ontology_models.dart';
import '../agent/ontology/ontology_store_service.dart';
import '../agent/skills.dart';
import '../models/skill.dart';
import 'registry.dart';

final _log = Logger('Ghost.Tools.Skills');

/// Tools for managing and progressively loading Ghost skills.
class SkillsTools {
  static void registerAll(
    ToolRegistry registry,
    SkillManager skillManager, {
    OntologyStoreService? ontology,
  }) {
    registry.register(LoadSkillTool(skillManager, ontology: ontology));
    registry.register(ImportSkillTool(skillManager));
    registry.register(ListSkillsTool(skillManager));
    registry.register(CreateSkillTemplateTool(skillManager));
    registry.register(DebugSkillTool(skillManager));
    registry.register(DownloadGithubSkillTool(skillManager));
  }
}

/// Stage 2 Progressive Disclosure tool: loads full SKILL.md instructions and
/// runtime metadata for a specific skill after verifying `DARF_NUTZEN` permission
/// in the Ontology Knowledge Graph.
class LoadSkillTool extends Tool {
  LoadSkillTool(this.skillManager, {this.ontology});

  final SkillManager skillManager;
  final OntologyStoreService? ontology;

  @override
  String get name => 'ghost_load_skill';

  @override
  String get label => 'Load Skill';

  @override
  String get description =>
      'Loads the full SKILL.md instructions, tool specifications, directory path, '
      'dependencies, and security/HITL metadata for an authorized skill on demand. '
      'Always call this BEFORE using a skill listed in [AVAILABLE SKILLS].';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'skill_name': {
            'type': 'string',
            'description':
                'The slug or display name of the skill to load (e.g. "weather-pro").',
          },
        },
        'required': ['skill_name'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Loading skill "${input['skill_name'] ?? input['skillName'] ?? ''}"';

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final requested = (input['skill_name'] ??
            input['skillName'] ??
            input['slug'] ??
            '')
        .toString()
        .trim();

    if (requested.isEmpty) {
      return const ToolResult.error('Parameter "skill_name" is required.');
    }

    try {
      SkillOntologySummary? summary;
      List<String> transitiveDeps = const [];

      if (ontology != null && ontology!.isInitialized) {
        summary = ontology!.resolveAuthorizedSkill(context.agentId, requested);
        if (summary == null) {
          if (ontology!.isSkillInstalledInOntology(requested)) {
            return ToolResult.error(
              'PERMISSION DENIED: Agent "${context.agentId}" is not authorized '
              'to use skill "$requested" (missing DARF_NUTZEN permission in ontology).',
            );
          }
          return ToolResult.error(
            'Skill "$requested" was not found among installed skills.',
          );
        }
        transitiveDeps = ontology!.getRequiredSkillSlugs(summary.slug);
      }

      final installedSkills = await skillManager.loadSkills();
      Skill? diskSkill;
      for (final s in installedSkills) {
        if (summary != null) {
          if (s.slug.toLowerCase() == summary.slug.toLowerCase()) {
            diskSkill = s;
            break;
          }
        } else if (s.slug.toLowerCase() == requested.toLowerCase() ||
            s.name.toLowerCase() == requested.toLowerCase()) {
          diskSkill = s;
          break;
        }
      }

      if (diskSkill == null && summary == null) {
        return ToolResult.error(
          'Skill "$requested" was not found among installed skills.',
        );
      }

      final slug = summary?.slug ?? diskSkill!.slug;
      final displayName = summary?.name ?? diskSkill?.name ?? slug;
      final category = summary?.category ?? diskSkill?.category ?? 'general';
      final requiresHitl = (summary?.requiresHitl ?? false) ||
          (diskSkill?.requiresHitl ?? false) ||
          (ontology != null &&
              ontology!.isInitialized &&
              ontology!.skillRequiresHitl(slug));
      final securityLevel =
          summary?.securityLevel ?? diskSkill?.securityLevel ?? 'standard';
      final skillDirPath = p.join(skillManager.skillsDir, slug);
      final markdown = await skillManager.readSkillContent(slug);

      final allDeps = <String>{
        ...?(summary?.dependencies),
        ...?diskSkill?.requiredSkills,
        ...transitiveDeps,
      }.toList();

      final buffer = StringBuffer();
      buffer.writeln('=== SKILL LOADED: $displayName ($slug) ===');
      buffer.writeln('Skill directory: $skillDirPath');
      buffer.writeln('Category/Domain: $category');
      buffer.writeln('Security level: $securityLevel');
      buffer.writeln('Requires HITL approval: ${requiresHitl ? "YES (ERFORDERT_HITL)" : "no"}');
      if (diskSkill?.hasPython == true) {
        buffer.writeln('Python runtime: .venv/bin/python (inside $skillDirPath)');
      }
      if (diskSkill?.hasNode == true) {
        buffer.writeln('Node.js runtime: node (inside $skillDirPath)');
      }
      if (diskSkill?.hasMcp == true && diskSkill?.mcpCommand != null) {
        buffer.writeln('MCP command: ${diskSkill!.mcpCommand}');
      }
      if (allDeps.isNotEmpty) {
        buffer.writeln(
          'Required skills (BENOETIGT_SKILL): ${allDeps.join(', ')}',
        );
      }
      if (requiresHitl) {
        buffer.writeln(
          'SECURITY NOTICE: This skill is marked ERFORDERT_HITL. '
          'Any mutating/executing actions triggered for this skill are subject to '
          'System-1 risk scoring and Human-In-The-Loop confirmation.',
        );
      }
      buffer.writeln();
      buffer.writeln('--- SKILL.md ---');
      buffer.writeln(
        markdown.isNotEmpty
            ? markdown
            : '(No SKILL.md content found for "$slug".)',
      );

      return ToolResult(
        output: buffer.toString().trim(),
        metadata: {
          'skill_slug': slug,
          'skill_name': displayName,
          'skill_dir': skillDirPath,
          'category': category,
          'requires_hitl': requiresHitl,
          'security_level': securityLevel,
          'dependencies': allDeps,
          'has_mcp': diskSkill?.hasMcp ?? summary?.hasMcp ?? false,
          if (diskSkill?.mcpCommand != null)
            'mcp_command': diskSkill!.mcpCommand,
        },
      );
    } catch (e) {
      return ToolResult.error('Failed to load skill "$requested": $e');
    }
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
