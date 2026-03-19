// Ghost — Search Tools.

import '../tools/registry.dart';
import '../tools/duckduckgo.dart';

/// Tools for web search.
class SearchTools {
  SearchTools._();

  /// Register search tools.
  static void registerAll(ToolRegistry registry) {
    registry.register(DuckDuckGoSearchTool());
  }
}
