// Ghost — Antigravity Tool Exposition Service.
// Exposes Ghost's unique tool ecosystem as registered Antigravity and ACP tools.

import 'dart:async';
import 'package:logging/logging.dart';
import '../../engine/tools/registry.dart';
import '../../engine/config/secure_storage.dart';
import '../../engine/agent/rag_memory.dart';
import '../../engine/tasks/task_manager.dart';
import '../../engine/tasks/task_orchestrator.dart';

final _log = Logger('Ghost.AntigravityTools');

/// Standard Antigravity tool schema representation.
class AntigravityToolDescriptor {
  const AntigravityToolDescriptor({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

/// Service exposing Ghost's specialized capabilities as Antigravity tools.
class AntigravityToolExpositionService {
  AntigravityToolExpositionService({
    required this.toolRegistry,
    this.storage,
    this.ragEngine,
    this.taskManager,
    this.orchestrator,
  });

  final ToolRegistry toolRegistry;
  final SecureStorage? storage;
  final RAGMemoryEngine? ragEngine;
  final TaskManager? taskManager;
  final TaskOrchestrator? orchestrator;

  /// Returns the complete list of Antigravity-exposed tool definitions.
  List<AntigravityToolDescriptor> getExposedTools() {
    final list = <AntigravityToolDescriptor>[
      const AntigravityToolDescriptor(
        name: 'ghost_web_search',
        description:
            'Perform real-time web searches using DuckDuckGo with deep summary analysis.',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query string.',
            },
          },
          'required': ['query'],
        },
      ),
      const AntigravityToolDescriptor(
        name: 'ghost_workspace_rag',
        description:
            'Perform semantic code search across indexed workspace project files using ObjectBox vector memory.',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search query or concept to find in the codebase.',
            },
          },
          'required': ['query'],
        },
      ),
      const AntigravityToolDescriptor(
        name: 'ghost_vault_keys',
        description:
            'Inspect available external API key names safely stored in Ghost secure vault without revealing secret values.',
        parameters: {
          'type': 'object',
          'properties': {},
        },
      ),
      const AntigravityToolDescriptor(
        name: 'ghost_kanban_pipeline',
        description:
            'Create or update sequential Kanban task pipelines with automated agent dependency progression.',
        parameters: {
          'type': 'object',
          'properties': {
            'titles': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Ordered list of task titles in the pipeline.',
            },
            'assignedAgentId': {
              'type': 'string',
              'description': 'Optional ID of the agent to assign tasks to.',
            },
          },
          'required': ['titles'],
        },
      ),
      const AntigravityToolDescriptor(
        name: 'ghost_apply_patch',
        description:
            'Apply structured SEARCH/REPLACE blocks or unified diff patches to workspace files with review gating.',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Relative path to the workspace file.',
            },
            'patch': {
              'type': 'string',
              'description':
                  'Patch content with <<<<<<< SEARCH ... ======= ... >>>>>>> REPLACE.',
            },
          },
          'required': ['path', 'patch'],
        },
      ),
      const AntigravityToolDescriptor(
        name: 'ghost_exec',
        description:
            'Execute shell commands with automatic Python venv and node_modules .bin environment injection.',
        parameters: {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description': 'The shell command to execute.',
            },
          },
          'required': ['command'],
        },
      ),
    ];

    return list;
  }

  /// Dispatches execution of an exposed Antigravity tool.
  Future<Map<String, dynamic>> executeAntigravityTool(
    String toolName,
    Map<String, dynamic> arguments, {
    required String sessionId,
    required String workspaceDir,
    String stateDir = '.ghost',
  }) async {
    _log.info('Executing Antigravity tool: $toolName');

    switch (toolName) {
      case 'ghost_web_search':
        final res = await toolRegistry.execute(
          'web_search',
          arguments,
          ToolContext(
            sessionId: sessionId,
            agentId: 'antigravity',
            workspaceDir: workspaceDir,
            stateDir: stateDir,
          ),
        );
        return {'output': res.output, 'isError': res.isError};

      case 'ghost_workspace_rag':
        if (ragEngine == null) {
          return {'output': 'RAG Engine not available', 'isError': true};
        }
        final query = arguments['query'] as String? ?? '';
        final results = await ragEngine!.query(query);
        return {
          'output': results.isEmpty
              ? 'No relevant workspace snippets found.'
              : results.join('\n---\n'),
          'isError': false,
        };

      case 'ghost_vault_keys':
        if (storage == null) {
          return {'output': 'Vault storage not available', 'isError': true};
        }
        final keys = await storage!.listKeys();
        final publicKeys = keys
            .where((k) =>
                !k.startsWith('_') &&
                !k.contains('auth_token') &&
                !k.contains('client_token'))
            .toList();
        return {
          'output': 'Available vault credentials:\n${publicKeys.join('\n')}',
          'isError': false,
        };

      case 'ghost_kanban_pipeline':
        if (orchestrator == null) {
          return {'output': 'Task orchestrator not available', 'isError': true};
        }
        final titles =
            (arguments['titles'] as List<dynamic>?)?.cast<String>() ?? [];
        final assignedAgentId = arguments['assignedAgentId'] as String?;
        final tasks = await orchestrator!.createPipeline(
          titles: titles,
          assignedAgentId: assignedAgentId,
        );
        return {
          'output':
              'Created pipeline with ${tasks.length} tasks: ${tasks.map((t) => t.id).join(", ")}',
          'isError': false,
          'taskIds': tasks.map((t) => t.id).toList(),
        };

      case 'ghost_apply_patch':
        final res = await toolRegistry.execute(
          'apply_patch',
          arguments,
          ToolContext(
            sessionId: sessionId,
            agentId: 'antigravity',
            workspaceDir: workspaceDir,
            stateDir: stateDir,
          ),
        );
        return {'output': res.output, 'isError': res.isError};

      case 'ghost_exec':
        final res = await toolRegistry.execute(
          'bash',
          arguments,
          ToolContext(
            sessionId: sessionId,
            agentId: 'antigravity',
            workspaceDir: workspaceDir,
            stateDir: stateDir,
          ),
        );
        return {'output': res.output, 'isError': res.isError};

      default:
        return {'output': 'Unknown tool: $toolName', 'isError': true};
    }
  }
}
