// Ghost — ACP Workspace-RAG Context Provider.
// Exposes Ghost's semantic memory and workspace indexing to Antigravity and ACP clients.

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../agent/rag_memory.dart';
import 'protocol.dart';

final _log = Logger('Ghost.AcpContextProvider');

/// Context Provider integrating Ghost's Workspace RAG.
class AcpContextProvider {
  AcpContextProvider({
    required this.ragEngine,
    this.providerId = 'ghost.workspace_rag',
    this.name = 'Ghost Workspace RAG Context Provider',
  });

  final RAGMemoryEngine ragEngine;
  final String providerId;
  final String name;

  /// Index/sync the workspace directory into RAG.
  Future<void> syncWorkspace(String workspacePath) async {
    try {
      final dir = Directory(workspacePath);
      if (!await dir.exists()) {
        _log.warning('Workspace directory does not exist: $workspacePath');
        return;
      }
      _log.info('Syncing workspace for ACP context: $workspacePath');
      await ragEngine.syncWorkspaceRag(workspacePath);
    } catch (e) {
      _log.warning('Failed to sync workspace for ACP context: $e');
    }
  }

  /// Query the context provider for relevant snippets and files.
  Future<List<AcpContextItem>> query(
    String queryText, {
    String? workspacePath,
    int maxResults = 5,
  }) async {
    try {
      final results = await ragEngine.query(queryText);
      final items = <AcpContextItem>[];

      for (int i = 0; i < results.length && i < maxResults; i++) {
        final chunk = results[i];
        items.add(
          AcpContextItem(
            title: 'Workspace Snippet ${i + 1}',
            content: chunk,
            source: 'workspace_rag',
          ),
        );
      }

      // If RAG produced no results but a workspace is given, fallback to file structure overview
      if (items.isEmpty && workspacePath != null) {
        final fallbackOverview = await _getWorkspaceOverview(workspacePath);
        if (fallbackOverview != null && fallbackOverview.isNotEmpty) {
          items.add(
            AcpContextItem(
              title: 'Workspace Project Overview',
              content: fallbackOverview,
              source: 'workspace_fs',
            ),
          );
        }
      }

      return items;
    } catch (e) {
      _log.warning('Error querying ACP context provider: $e');
      return [];
    }
  }

  /// Builds a formatted context string for direct prompt enrichment.
  Future<String> buildEnrichedPromptContext(
    String queryText, {
    String? workspacePath,
  }) async {
    final items = await query(queryText, workspacePath: workspacePath);
    if (items.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('\n[ANTIGRAVITY CONTEXT PROVIDER: $name]');
    buffer.writeln('The following verified workspace context is available for this prompt:');
    for (final item in items) {
      buffer.writeln('\n--- Context Item: ${item.title} (${item.source}) ---');
      buffer.writeln(item.content);
    }
    buffer.writeln('--- End of Workspace Context ---\n');
    return buffer.toString();
  }

  /// Fallback summary of top-level workspace files and directories.
  Future<String?> _getWorkspaceOverview(String workspacePath) async {
    try {
      final dir = Directory(workspacePath);
      if (!await dir.exists()) return null;

      final entries = await dir.list().toList();
      final summary = entries.map((e) {
        final type = e is Directory ? '[DIR]' : '[FILE]';
        return '$type ${p.basename(e.path)}';
      }).join('\n');

      return 'Top-level workspace directory structure:\n$summary';
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> getProviderMetadata() => {
        'id': providerId,
        'name': name,
        'description':
            'Semantic RAG memory and indexed workspace documents for Antigravity & Ghost.',
      };
}
