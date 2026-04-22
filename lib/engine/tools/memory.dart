// Ghost — Memory Tools (RAG)

import '../agent/memory_system.dart';
import 'registry.dart';

class MemoryTools {
  static void registerAll(ToolRegistry registry, MemorySystem engine) {
    registry.register(MemoryAddTool(engine));
    registry.register(MemoryQueryTool(engine));
  }
}

class MemoryAddTool extends Tool {
  MemoryAddTool(this.engine);
  final MemorySystem engine;

  @override
  String get name => 'memory_add';

  @override
  String get description =>
      'Add a fact, context, or information to your long-term memory for future retrieval.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'The text or information to remember.'
          },
          'category': {
            'type': 'string',
            'description':
                'Optional category for this memory (e.g. "user_preference", "project_info").'
          }
        },
        'required': ['text'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Adding fact to "${input['category'] ?? 'general'}"...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final text = input['text']?.toString();
    final category = input['category']?.toString();

    if (text == null || text.isEmpty) {
      return const ToolResult(
          output: 'Error: No text provided to remember.', isError: true);
    }

    try {
      // 1. Check for similar existing memories first
      final existing = await engine.query(text, limit: 3, category: category);

      // 2. Add the new memory
      await engine.add(text,
          metadata: {
            'source': 'tool_call',
            'category': ?category,
            'agentId': context.agentId,
          },
          activeProvider: context.activeProvider);

      if (existing.isEmpty) {
        return const ToolResult(output: 'Successfully added to memory.');
      } else {
        final buffer = StringBuffer();
        buffer.writeln('Successfully added to memory.');
        buffer.writeln(
            '\nNote: I found these similar/related memories already exist:');
        for (var i = 0; i < existing.length; i++) {
          buffer.writeln('- ${existing[i]}');
        }
        buffer.writeln(
            '\nYou can use this to say something like "I\'ve noted that" if it is relevant to the current conversation.');
        return ToolResult(output: buffer.toString());
      }
    } catch (e) {
      return ToolResult(output: 'Error adding to memory: $e', isError: true);
    }
  }
}

class MemoryQueryTool extends Tool {
  MemoryQueryTool(this.engine);
  final MemorySystem engine;

  @override
  String get name => 'memory_query';

  @override
  String get description =>
      'Search your long-term memory for relevant information or past context.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query to find relevant memories.'
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of results to return (default 5).'
          }
        },
        'required': ['query'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Searching for "${input['query']}"...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final query = input['query']?.toString();
    final limit = (input['limit'] as num?)?.toInt() ?? 5;

    if (query == null || query.isEmpty) {
      return const ToolResult(
          output: 'Error: No query provided.', isError: true);
    }

    try {
      final results = await engine.query(query,
          limit: limit, activeProvider: context.activeProvider);

      if (results.isEmpty) {
        return const ToolResult(output: 'No relevant memories found.');
      }

      final buffer = StringBuffer();
      buffer.writeln('Historical Context (from memory):');
      for (var i = 0; i < results.length; i++) {
        buffer.writeln('${i + 1}. ${results[i]}');
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult(output: 'Error querying memory: $e', isError: true);
    }
  }
}
