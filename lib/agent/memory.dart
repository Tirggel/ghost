import 'dart:convert';
import 'package:hive_ce/hive.dart';
import 'package:logging/logging.dart';
import '../config/config.dart';
import '../config/secure_storage.dart';
import '../models/provider.dart';

final _log = Logger('Ghost.MemoryEngine');

/// A single chunk of text with its metadata.
class MemoryChunk {

  factory MemoryChunk.fromJson(Map<String, dynamic> json) {
    return MemoryChunk(
      text: json['text'] as String,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map),
    );
  }
  MemoryChunk({
    required this.text,
    this.metadata = const {},
  });

  final String text;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'text': text,
        'metadata': metadata,
      };
}

/// Handles long-term memory via simple keyword matching.
class MemoryEngine {
  MemoryEngine({
    required this.config,
    required this.storage,
    required this.stateDir,
  });

  MemoryConfig config;
  final SecureStorage storage;
  final String stateDir;

  Box<Map<dynamic, dynamic>>? _hiveBox;

  /// Initialize the memory engine and its backend.
  Future<void> initialize({
    String? agentModel,
    String? agentProvider,
    AIModelProvider? testProvider,
  }) async {
    if (!config.enabled) {
      _log.info('Memory engine is disabled');
      return;
    }

    _log.info('Initializing memory engine (backend: ${config.backend})');

    if (config.backend == 'sqlite') {
      await _initSqlite();
    } else {
      await _initHive();
    }
  }

  Future<void> _initSqlite() async {
    _log.info('Initializing SQLite vector store in $stateDir/memory.db (Stub)');
    // Future implementation: Initialize sqflite or similar
    // Fallback to Hive for now if SQLite is not available
    await _initHive();
  }

  Future<void> _initHive() async {
    _log.info('Initializing Hive memory store');
    _hiveBox = await Hive.openBox<Map<dynamic, dynamic>>('memory_chunks');
  }

  /// Retrieve relevant context for a query using basic keyword matching.
  Future<List<String>> query(String text,
      {int limit = 5,
      String? category,
      AIModelProvider? activeProvider}) async {
    if (!config.enabled) return [];

    if (_hiveBox == null) {
      _log.warning('Cannot query memory: Hive box is not initialized.');
      return [];
    }

    _log.info(
        'Querying memory using keyword matching: "$text" (category: $category)');

    try {
      final chunks = _hiveBox!.values
          .map((m) => MemoryChunk.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      if (chunks.isEmpty) return [];

      // Check if this is a personal query (I, me, my, ich, mich, mein)
      final personalPronouns = RegExp(
          r'\b(ich|mich|mir|mein|meine|meinem|meinen|i|me|my|mine)\b',
          caseSensitive: false);
      final isPersonalQuery =
          personalPronouns.hasMatch(text) || category == 'user_profile';

      // Normalize query: lowercase, remove punctuation, split into words
      final queryWords = text
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), ' ') // Replace punctuation with space
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 2) // Keep words with at least 2 chars
          .toSet();

      _log.fine('Sanitized query words: $queryWords');

      if (queryWords.isEmpty && !isPersonalQuery) {
        // Return most recent if query is too short or has no meaningful words
        return chunks.reversed.take(limit).map((c) => c.text).toList();
      }

      // Calculate match score
      final scored = chunks.map((chunk) {
        final chunkTextLower = chunk.text.toLowerCase();
        final chunkCategory = chunk.metadata['category'] as String?;

        // Filter by category if requested
        if (category != null && chunkCategory != category) {
          return _ScoredChunk(chunk, 0.0);
        }

        // Boost personal info for personal queries
        double profileBoost = 0.0;
        if (isPersonalQuery && chunkCategory == 'user_profile') {
          profileBoost = 0.5; // Base boost for relevant category
        }

        // Also sanitize chunk text for better matching
        final sanitizedChunk =
            chunkTextLower.replaceAll(RegExp(r'[^\w\s]'), ' ');

        double score = profileBoost;

        if (queryWords.isEmpty &&
            isPersonalQuery &&
            chunkCategory == 'user_profile') {
          // If query is "Who am I?" (empty queryWords after filtering)
          score += 1.0;
        }

        for (final word in queryWords) {
          // Exact word match in sanitized text gets higher score
          if (sanitizedChunk.contains(' $word ') ||
              sanitizedChunk.startsWith('$word ') ||
              sanitizedChunk.endsWith(' $word') ||
              sanitizedChunk == word) {
            score += 1.0;
          } else if (chunkTextLower.contains(word)) {
            // Substring match gets lower score
            score += 0.3;
          }
        }
        return _ScoredChunk(chunk, score);
      }).toList();

      // Sort by score descending
      scored.sort((a, b) => b.score.compareTo(a.score));

      // Filter to items with at least some match
      final results = scored
          .where((s) => s.score > 0)
          .take(limit)
          .map((s) => s.chunk.text)
          .toList();

      _log.info('Found ${results.length} relevant chunks in memory');
      return results;
    } catch (e) {
      _log.severe('Memory query failed: $e');
      return [];
    }
  }

  /// Add a document or text chunk to memory.
  Future<void> add(String text,
      {Map<String, dynamic> metadata = const {},
      AIModelProvider? activeProvider}) async {
    if (!config.enabled) return;

    if (_hiveBox == null) {
      _log.warning('Cannot add to memory: Hive box is not initialized.');
      throw StateError('Memory storage not initialized');
    }

    if (text.trim().isEmpty) return;

    _log.info('Adding text to memory: ${text.length} chars');

    final chunks = _chunkText(text, 1000, 200);

    for (final chunkText in chunks) {
      try {
        final chunk = MemoryChunk(
          text: chunkText,
          metadata: {
            ...metadata,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        await _hiveBox!.add(chunk.toJson());
      } catch (e) {
        _log.severe('Failed to add chunk to memory: $e');
      }
    }
  }

  List<String> _chunkText(String text, int size, int overlap) {
    if (text.length <= size) return [text];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = start + size;
      if (end > text.length) end = text.length;

      chunks.add(text.substring(start, end));
      start += (size - overlap);

      if (start >= text.length) break;
    }

    return chunks;
  }

  Future<String> backup() async {
    if (_hiveBox == null) return '[]';
    final chunks = _hiveBox!.values.toList();
    return jsonEncode(chunks);
  }

  Future<void> restore(String jsonData) async {
    if (_hiveBox == null) return;
    try {
      final jsonList = jsonDecode(jsonData) as List<dynamic>;
      await _hiveBox!.clear();
      for (final item in jsonList) {
        await _hiveBox!.add(Map<dynamic, dynamic>.from(item as Map));
      }
      _log.info('Restored ${jsonList.length} chunks to memory');
    } catch (e) {
      _log.severe('Restore failed: $e');
      throw Exception('Failed to restore memory backup: $e');
    }
  }

  /// Delete all stored memory chunks.
  Future<void> clear() async {
    if (_hiveBox == null) return;
    await _hiveBox!.clear();
    _log.info('Cleared all chunks from standard memory');
  }
}

class _ScoredChunk {
  _ScoredChunk(this.chunk, this.score);
  final MemoryChunk chunk;
  final double score;
}
