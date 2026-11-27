// Ghost — Ontology Pre-Turn Context Builder & Async Post-Turn Fact Extractor.

import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';

import '../../config/config.dart';
import '../../models/message.dart';
import '../../models/provider.dart';
import 'ontology_store_service.dart';

final _log = Logger('Ghost.OntologyExtractor');

/// Bridges [OntologyStoreService] with Ghost's chat pipeline:
/// 1. Pre-Turn Context Injection (compact graph triples for system prompt)
/// 2. Async Post-Turn Fact Extraction (JSON triples extracted via LLM)
class OntologyExtractor {
  OntologyExtractor._();

  static final RegExp _personalPronounsRegex = RegExp(
    r'\b(ich|mich|mir|mein|meine|meinem|meinen|meiner|i|me|my|mine)\b',
    caseSensitive: false,
  );

  /// Extracts relevant entity context from [ontology] for [userMessage]
  /// (including the primary user profile) and formats it compactly for the system prompt.
  static Future<String> buildPreTurnContext({
    required String userMessage,
    required OntologyStoreService ontology,
    UserConfig? userConfig,
    int maxDepth = 2,
    int maxFacts = 15,
  }) async {
    if (!ontology.isInitialized || !ontology.config.ontologyEnabled) {
      return '';
    }

    final queryTargets = <String>[];
    final isPersonal = _personalPronounsRegex.hasMatch(userMessage);

    // Always include primary user anchor when personal pronouns appear,
    // or as baseline context if the graph has user facts.
    if (isPersonal || ontology.getStats().edgeCount > 0) {
      queryTargets.add(OntologyStoreService.primaryUserKey);
      final userName = userConfig?.name.trim() ?? '';
      if (userName.isNotEmpty) {
        queryTargets.add(userName);
      }
    }

    // Match existing Knowledge Graph node labels present in the user prompt
    final matchedNodes = ontology.findMatchingNodesInText(userMessage, limit: 5);
    for (final node in matchedNodes) {
      if (!queryTargets.contains(node.canonicalKey)) {
        queryTargets.add(node.canonicalKey);
      }
    }

    if (queryTargets.isEmpty) return '';

    final seenLines = <String>{};
    final formattedLines = <String>[];

    for (final target in queryTargets) {
      if (formattedLines.length >= maxFacts) break;

      final result = await ontology.queryFactsForEntity(
        target,
        maxDepth: maxDepth,
        maxResults: maxFacts,
        includeIncoming: target != OntologyStoreService.primaryUserKey,
      );

      if (result.isEmpty) continue;

      final compact = result.toCompactPromptString(
        maxLines: maxFacts - formattedLines.length,
      );
      for (final line in compact.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final isGovernanceFact = OntologyStoreService.governancePredicates.any(
          (pred) => trimmed.contains('--[$pred]-->'),
        );
        if (isGovernanceFact) continue;
        if (seenLines.add(trimmed)) {
          formattedLines.add(trimmed);
          if (formattedLines.length >= maxFacts) break;
        }
      }
    }

    if (formattedLines.isEmpty) return '';

    return '[KNOWLEDGE GRAPH (VERIFIED STRUCTURED FACTS)]:\n${formattedLines.join('\n')}';
  }

  /// Asynchronously extracts structured JSON triples from [userMessage] using
  /// [provider] and persists them in [ontology].
  ///
  /// Callers MUST gate this behind System-1 security checks so untrusted or
  /// prompt-injection-flagged messages never poison long-term memory.
  static Future<int> extractAndAssertFacts({
    required String userMessage,
    required AIModelProvider provider,
    required OntologyStoreService ontology,
    UserConfig? userConfig,
  }) async {
    if (!ontology.isInitialized ||
        !ontology.config.ontologyEnabled ||
        !ontology.config.ontologyAutoExtract) {
      return 0;
    }
    if (!provider.supportsChat) return 0;

    final trimmed = userMessage.trim();
    if (trimmed.length < 12) return 0;

    try {
      final relations = ontology.getAllRelationDefs();
      final relationHints = relations
          .map(
            (r) =>
                '- ${r.predicate} (${r.domainType} -> ${r.rangeType}, '
                '${r.isFunctional ? "functional/single-value" : "multi-value"})',
          )
          .join('\n');

      final primaryName = userConfig?.name.trim() ?? '';
      final userIdentityHint = primaryName.isNotEmpty
          ? 'The primary user is "$primaryName" (if the user writes "ich"/"I"/"my", use subject "$primaryName" with subjectType "Person").'
          : 'If the user writes "ich"/"I"/"my", use subject "User" with subjectType "Person".';

      final extractionSystemPrompt = '''
You are a strict Knowledge Graph triple extractor.
Extract ONLY explicit, durable, factual statements from the user's message into a JSON array.
$userIdentityHint

Preferred predicates (you may create a concise UPPER_SNAKE_CASE predicate only if none fits):
$relationHints

Rules:
1. Extract ONLY facts explicitly stated by the user (e.g. residence, name, job, projects, locations, preferences).
2. Do NOT extract temporary questions, commands, greetings, hypotheses, or speculative statements.
3. Output ONLY a valid JSON array. If no durable facts are present, output [].
4. Each element must have:
   {"subject": "...", "subjectType": "Person|Place|Project|Organization|Technology|Entity", "predicate": "UPPER_SNAKE_CASE", "object": "...", "objectType": "Person|Place|Project|Organization|Technology|Text|Entity", "confidence": 0.0-1.0}
''';

      final response = await provider
          .chat(
            messages: [
              Message(
                role: 'user',
                content: trimmed,
                timestamp: DateTime.now(),
              ),
            ],
            systemPrompt: extractionSystemPrompt,
            maxTokens: 350,
            temperature: 0.0,
          )
          .timeout(const Duration(seconds: 10));

      final triples = _parseTriplesJson(response.content);
      if (triples.isEmpty) return 0;

      int savedCount = 0;
      for (final item in triples) {
        final subject = (item['subject'] as String? ?? '').trim();
        final predicate = (item['predicate'] as String? ?? '').trim();
        final object = (item['object'] as String? ?? '').trim();
        final subjectType = (item['subjectType'] as String? ?? 'Entity').trim();
        final objectType = (item['objectType'] as String? ?? 'Entity').trim();
        final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.85;

        if (subject.isEmpty || predicate.isEmpty || object.isEmpty) continue;
        if (confidence < 0.7) continue;

        final isPrimaryUser = _isPrimaryUserReference(subject, primaryName);
        await ontology.assertFact(
          subjectLabel: isPrimaryUser && primaryName.isNotEmpty
              ? primaryName
              : subject,
          subjectType: isPrimaryUser ? 'Person' : subjectType,
          subjectKey: isPrimaryUser ? OntologyStoreService.primaryUserKey : null,
          predicate: predicate,
          objectLabel: object,
          objectType: objectType,
          confidence: confidence,
        );
        savedCount++;
      }

      if (savedCount > 0) {
        _log.info('Post-turn ontology extraction stored $savedCount fact(s).');
      }
      return savedCount;
    } catch (e) {
      _log.warning('Async ontology fact extraction skipped/failed: $e');
      return 0;
    }
  }

  static bool _isPrimaryUserReference(String subject, String primaryName) {
    final lower = subject.trim().toLowerCase();
    if (lower == 'user' ||
        lower == 'ich' ||
        lower == 'i' ||
        lower == 'me' ||
        lower == 'user:primary') {
      return true;
    }
    if (primaryName.isNotEmpty && lower == primaryName.toLowerCase()) {
      return true;
    }
    return false;
  }

  static List<Map<String, dynamic>> _parseTriplesJson(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return const [];

    // Strip markdown code fences if present
    cleaned = cleaned
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
        .trim();

    final startIdx = cleaned.indexOf('[');
    final endIdx = cleaned.lastIndexOf(']');
    if (startIdx == -1 || endIdx == -1 || endIdx < startIdx) {
      return const [];
    }

    final jsonSlice = cleaned.substring(startIdx, endIdx + 1);
    try {
      final decoded = jsonDecode(jsonSlice);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
