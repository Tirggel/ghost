// Ghost — Tool base class and registry.

import 'package:logging/logging.dart';

import '../infra/errors.dart';
import '../models/provider.dart';

final _log = Logger('Ghost.Tools');

/// Result of a tool execution.
class ToolResult {
  const ToolResult({
    required this.output,
    this.isError = false,
    this.metadata = const {},
  });

  /// Create an error result.
  const ToolResult.error(String message)
      : output = message,
        isError = true,
        metadata = const {};

  final String output;
  final bool isError;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'output': output,
        'isError': isError,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}

/// Context passed to tools during execution.
class ToolContext {
  const ToolContext({
    required this.sessionId,
    required this.agentId,
    required this.workspaceDir,
    required this.stateDir,
    this.activeProvider,
    this.browserHeadless = true,
    this.restrictNetwork = false,
  });

  final String sessionId;
  final String agentId;
  final String workspaceDir;
  final String stateDir;
  final AIModelProvider? activeProvider;
  final bool browserHeadless;
  final bool restrictNetwork;
}

/// Abstract base class for tools.
abstract class Tool {
  /// Tool name (used for invocation).
  String get name;

  /// Human-readable description.
  String get description;

  /// JSON Schema for the tool's input parameters.
  Map<String, dynamic> get inputSchema;

  /// User-friendly label for activity display (defaults to name).
  String get label => name;

  /// Execute the tool with the given input.
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context);

  /// Optional summary for logging.
  String getLogSummary(Map<String, dynamic> input) => '';
}

/// Tool groups — shorthand names for sets of tools.
class ToolGroups {
  ToolGroups._();

  static const Map<String, List<String>> groups = {
    'group:runtime': ['exec', 'bash', 'process'],
    'group:fs': ['read', 'write', 'edit', 'apply_patch'],
    'group:sessions': [
      'sessions_list',
      'sessions_history',
      'sessions_send',
      'sessions_spawn',
      'session_status',
    ],
    'group:memory': [
      'memory_search',
      'memory_get',
      'memory_add',
      'memory_query'
    ],
    'group:web': ['web_search', 'web_fetch'],
    'group:ui': ['browser', 'canvas'],
    'group:github': ['github'],
  };

  /// Expand group references in a tool list.
  static List<String> expand(List<String> toolNames) {
    final expanded = <String>[];
    for (final name in toolNames) {
      if (groups.containsKey(name)) {
        expanded.addAll(groups[name]!);
      } else {
        expanded.add(name);
      }
    }
    return expanded;
  }
}

/// Tool profiles — predefined allowlists.
class ToolProfiles {
  ToolProfiles._();

  static const Map<String, List<String>> profiles = {
    'minimal': ['session_status'],
    'coding': [
      'group:fs',
      'group:runtime',
      'group:sessions',
      'group:memory',
      'group:github',
      'group:web',
      'group:ui',
    ],
    'messaging': ['message', 'group:sessions'],
    'full': [], // Empty = no restrictions
  };

  /// Get the expanded allowlist for a profile.
  static List<String> getAllowList(String profile) {
    final tools = profiles[profile];
    if (tools == null) return [];
    if (tools.isEmpty) return []; // 'full' = no restrictions
    return ToolGroups.expand(tools);
  }

  /// Check if a profile allows all tools.
  static bool isUnrestricted(String profile) {
    return profile == 'full';
  }
}

/// Registry of available tools with policy enforcement.
class ToolRegistry {
  ToolRegistry({
    this.profile = 'full',
    this.allow = const [],
    this.deny = const [],
  });

  final String profile;
  final List<String> allow;
  final List<String> deny;

  final Map<String, Tool> _tools = {};

  /// Register a tool.
  void register(Tool tool) {
    _tools[tool.name] = tool;
    _log.fine('Registered tool: ${tool.name}');
  }

  /// Unregister a tool.
  void unregister(String name) {
    _tools.remove(name);
  }

  /// Get a tool by name.
  Tool? getTool(String name) => _tools[name];

  /// Check if a tool is allowed by the current policy.
  bool isAllowed(String toolName) {
    // Deny always wins
    final expandedDeny = ToolGroups.expand(deny);
    if (expandedDeny.contains(toolName)) return false;

    // If profile is unrestricted and no explicit deny, allow
    if (ToolProfiles.isUnrestricted(profile)) return true;

    // Check explicit allow list
    final expandedAllow = ToolGroups.expand(allow);
    if (expandedAllow.contains(toolName)) return true;

    // Check profile allowlist
    final profileAllow = ToolProfiles.getAllowList(profile);
    return profileAllow.contains(toolName);
  }

  /// Execute a tool by name with policy enforcement.
  Future<ToolResult> execute(
    String toolName,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    if (!isAllowed(toolName)) {
      throw ToolError(
        'Tool "$toolName" is not allowed by current policy',
        toolName: toolName,
        code: 'TOOL_DENIED',
      );
    }

    // Check Network Isolation
    if (context.restrictNetwork) {
      final webTools = ToolGroups.groups['group:web'] ?? [];
      if (webTools.contains(toolName)) {
        throw ToolError(
          'Tool "$toolName" is blocked by Network Isolation policy',
          toolName: toolName,
          code: 'NETWORK_RESTRICTED',
        );
      }
    }

    final tool = _tools[toolName];
    if (tool == null) {
      throw ToolError(
        'Tool "$toolName" not found',
        toolName: toolName,
        code: 'TOOL_NOT_FOUND',
      );
    }

    final summary = tool.getLogSummary(input);
    final logSuffix = summary.isNotEmpty ? ': $summary' : '';
    _log.info('Executing tool: $toolName$logSuffix');
    try {
      return await tool.execute(input, context);
    } catch (e) {
      if (e is ToolError) rethrow;
      throw ToolError(
        'Tool execution failed: $e',
        toolName: toolName,
        code: 'TOOL_EXECUTION_FAILED',
        cause: e,
      );
    }
  }

  /// Get all registered tool names.
  Set<String> get toolNames => _tools.keys.toSet();

  /// Get definitions for all allowed tools (for model context).
  List<Map<String, dynamic>> getToolDefinitions() {
    return _tools.entries
        .where((e) => isAllowed(e.key))
        .map(
          (e) => {
            'name': e.value.name,
            'description': e.value.description,
            'input_schema': e.value.inputSchema,
          },
        )
        .toList();
  }
}
