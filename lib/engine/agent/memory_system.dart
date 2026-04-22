import 'memory.dart';
import 'rag_memory.dart';
import '../infra/errors.dart';
import '../models/provider.dart';

class MemorySystem {
  MemorySystem({required this.standard, required this.rag});
  final MemoryEngine standard;
  final RAGMemoryEngine rag;

  Future<List<String>> query(String text, {int limit = 5, String? category, AIModelProvider? activeProvider}) async {
    final results = <String>[];
    if (standard.config.enabled) {
      results.addAll(await standard.query(text, limit: limit, category: category, activeProvider: activeProvider));
    }
    if (rag.config.ragEnabled) {
      // RAG must always use its own configured embedding provider, not the chat provider.
      results.addAll(await rag.query(text, category: category));
    }
    return results;
  }

  Future<void> add(String text, {Map<String, dynamic> metadata = const {}, AIModelProvider? activeProvider}) async {
    bool savedToAny = false;
    if (rag.config.ragEnabled) {
      // RAG must always use its own configured embedding provider, not the chat provider.
      await rag.add(text, metadata: metadata);
      savedToAny = true;
    } 
    if (standard.config.enabled) {
      await standard.add(text, metadata: metadata, activeProvider: activeProvider);
      savedToAny = true;
    }
    if (!savedToAny) {
      throw ToolError('Memory is disabled. Please tell the user to enable Standard or RAG Memory in the settings.');
    }
  }
}
