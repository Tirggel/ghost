import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../agent/manager.dart';
import '../config/config.dart';
import 'registry.dart';

/// Tools for managing custom agents and their schedules.
class AgentsTools {
  static void registerAll(ToolRegistry registry, AgentManager agentManager) {
    registry.register(ManageAgentsTool(agentManager));
  }
}

/// A tool that allows managing custom agents (list, create, delete).
/// This is particularly useful for scheduling periodic tasks.
class ManageAgentsTool extends Tool {
  ManageAgentsTool(this.agentManager);

  final AgentManager agentManager;

  @override
  String get name => 'manage_agents';

  @override
  String get description =>
      'Manage custom agents. You can list existing agents, create new ones with specific system prompts, skills, and cron schedules, or delete them. '
      'Cron schedules use standard unix format (e.g. "*/5 * * * *" for every 5 minutes).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['list', 'create', 'delete'],
            'description': 'The action to perform.',
          },
          'id': {
            'type': 'string',
            'description': 'The ID of the agent (required for delete).',
          },
          'name': {
            'type': 'string',
            'description': 'Human-readable name for the agent (required for create).',
          },
          'systemPrompt': {
            'type': 'string',
            'description': 'The system prompt defining the agent\'s behavior and goal.',
          },
          'cronSchedule': {
            'type': 'string',
            'description': 'Optional cron schedule (e.g. "0 9 * * *" for daily at 9am).',
          },
          'cronMessage': {
            'type': 'string',
            'description': 'The message sent to the agent when the cron triggers.',
          },
          'skills': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List of skill slugs the agent should have access to.',
          },
          'enabled': {
            'type': 'boolean',
            'description': 'Whether the agent (and its schedule) is enabled.',
            'default': true,
          },
        },
        'required': ['action'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final action = input['action'] as String;

    switch (action) {
      case 'list':
        return _listAgents();
      case 'create':
        return _createAgent(input);
      case 'delete':
        return _deleteAgent(input);
      default:
        return ToolResult.error('Unknown action: $action');
    }
  }

  Future<ToolResult> _listAgents() async {
    final agents = agentManager.config.customAgents;
    final List<Map<String, dynamic>> result =
        agents.map((a) => a.toJson()).toList();
    return ToolResult(output: jsonEncode(result));
  }

  Future<ToolResult> _createAgent(Map<String, dynamic> input) async {
    final name = input['name'] as String?;
    if (name == null || name.isEmpty) {
      return const ToolResult.error('Field "name" is required for create.');
    }

    final id = input['id'] as String? ?? const Uuid().v4();
    final systemPrompt = input['systemPrompt'] as String? ?? '';
    final cronSchedule = input['cronSchedule'] as String?;
    final cronMessage = input['cronMessage'] as String? ?? 'Run your scheduled task.';
    final skills = (input['skills'] as List<dynamic>?)?.cast<String>() ?? [];
    final enabled = input['enabled'] as bool? ?? true;

    final newAgent = CustomAgentConfig(
      id: id,
      name: name,
      systemPrompt: systemPrompt,
      cronSchedule: cronSchedule,
      cronMessage: cronMessage,
      skills: skills,
      enabled: enabled,
      model: agentManager.config.agent.model,
      provider: agentManager.config.agent.provider,
    );

    final currentAgents = List<CustomAgentConfig>.from(agentManager.config.customAgents);
    currentAgents.add(newAgent);

    try {
      await agentManager.saveCustomAgents(currentAgents);
      return ToolResult(
        output: 'Successfully created custom agent "${newAgent.name}" (ID: ${newAgent.id}). '
            '${cronSchedule != null ? 'Scheduled with: $cronSchedule' : 'No schedule set.'}',
        metadata: {'id': newAgent.id},
      );
    } catch (e) {
      return ToolResult.error('Failed to save custom agent: $e');
    }
  }

  Future<ToolResult> _deleteAgent(Map<String, dynamic> input) async {
    final id = input['id'] as String?;
    if (id == null || id.isEmpty) {
      return const ToolResult.error('Field "id" is required for delete.');
    }

    final currentAgents = List<CustomAgentConfig>.from(agentManager.config.customAgents);
    final initialCount = currentAgents.length;
    currentAgents.removeWhere((a) => a.id == id);

    if (currentAgents.length == initialCount) {
      return ToolResult.error('Agent with ID "$id" not found.');
    }

    try {
      await agentManager.saveCustomAgents(currentAgents);
      return ToolResult(output: 'Successfully deleted custom agent with ID "$id".');
    } catch (e) {
      return ToolResult.error('Failed to delete custom agent: $e');
    }
  }
}
