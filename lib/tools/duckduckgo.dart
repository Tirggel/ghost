// Ghost — DuckDuckGo Search Tool

import 'package:ddgs/ddgs.dart';
import '../tools/registry.dart';
import '../infra/logger.dart';

/// Tool to perform a web search using DuckDuckGo.
class DuckDuckGoSearchTool extends Tool {
  DuckDuckGoSearchTool();

  @override
  String get name => 'web_search';

  @override
  String get label => 'WEB';

  @override
  String get description =>
      'Search the web for real-time information and news using DuckDuckGo.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query.',
          },
        },
        'required': ['query'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Searching for "${input['query']}"...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final query = input['query'] as String;

    final ddgs = DDGS();
    try {
      final results = await ddgs.textTyped(
        query,
        options: const SearchOptions(maxResults: 5),
      );

      if (results.isEmpty) {
        return ToolResult(output: 'No results found for query "$query".');
      }

      final buffer = StringBuffer();

      for (final res in results) {
        buffer.writeln('### ${res.title}');
        buffer.writeln('Source: ${res.href}');
        buffer.writeln('${res.body}\n');
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      final logger = createLogger('DuckDuckGo');
      logger.severe('DuckDuckGo Search Error: $e');
      return ToolResult.error('Search failed: $e');
    } finally {
      ddgs.close();
    }
  }
}
