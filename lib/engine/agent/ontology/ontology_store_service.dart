// Ghost — Ontology Store Service (Graph Storage, Functional Rules, Multi-Hop Inference).

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../../objectbox.g.dart';
import '../../config/config.dart';
import '../../models/skill.dart';
import 'ontology_models.dart';

final _log = Logger('Ghost.OntologyStore');

/// Default T-Box relation definitions seeded on first startup.
const List<Map<String, dynamic>> _defaultRelations = [
  {
    'predicate': 'WOHNT_IN',
    'domainType': 'Person',
    'rangeType': 'Place',
    'isFunctional': true,
    'isTransitive': false,
  },
  {
    'predicate': 'HEISST',
    'domainType': 'Entity',
    'rangeType': 'Text',
    'isFunctional': true,
    'isTransitive': false,
  },
  {
    'predicate': 'ARBEITET_AN',
    'domainType': 'Person',
    'rangeType': 'Project',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'ARBEITET_BEI',
    'domainType': 'Person',
    'rangeType': 'Organization',
    'isFunctional': true,
    'isTransitive': false,
  },
  {
    'predicate': 'LIEGT_IN',
    'domainType': 'Place',
    'rangeType': 'Place',
    'isFunctional': true,
    'isTransitive': true,
  },
  {
    'predicate': 'TEIL_VON',
    'domainType': 'Entity',
    'rangeType': 'Entity',
    'isFunctional': false,
    'isTransitive': true,
  },
  {
    'predicate': 'MAG',
    'domainType': 'Person',
    'rangeType': 'Entity',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'MAG_NICHT',
    'domainType': 'Person',
    'rangeType': 'Entity',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'HAT_BERUF',
    'domainType': 'Person',
    'rangeType': 'Role',
    'isFunctional': true,
    'isTransitive': false,
  },
  {
    'predicate': 'BENUTZT',
    'domainType': 'Person',
    'rangeType': 'Technology',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'SPRICHT',
    'domainType': 'Person',
    'rangeType': 'Language',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'KENNT',
    'domainType': 'Person',
    'rangeType': 'Person',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'DARF_NUTZEN',
    'domainType': 'Agent',
    'rangeType': 'Skill',
    'isFunctional': false,
    'isTransitive': false,
  },
  {
    'predicate': 'GEHOERT_ZU_DOMAIN',
    'domainType': 'Skill',
    'rangeType': 'Domain',
    'isFunctional': true,
    'isTransitive': false,
  },
  {
    'predicate': 'BENOETIGT_SKILL',
    'domainType': 'Skill',
    'rangeType': 'Skill',
    'isFunctional': false,
    'isTransitive': true,
  },
  {
    'predicate': 'ERFORDERT_HITL',
    'domainType': 'Skill',
    'rangeType': 'SecurityPolicy',
    'isFunctional': true,
    'isTransitive': false,
  },
];

/// Native ObjectBox-backed Knowledge Graph and T-Box/A-Box Ontology engine.
class OntologyStoreService {
  OntologyStoreService({
    required this.config,
    required this.stateDir,
  });

  MemoryConfig config;
  final String stateDir;

  Store? _store;
  bool _ownsStore = false;
  Box<OntologyRelationDef>? _relationBox;
  Box<OntologyNode>? _nodeBox;
  Box<OntologyEdge>? _edgeBox;
  bool _initialized = false;

  static const String primaryUserKey = 'user:primary';
  static const String hitlPolicyKey = 'policy:hitl_required';
  static const String backupFileName = 'ontology_backup.json';

  static const String predicateCanUseSkill = 'DARF_NUTZEN';
  static const String predicateSkillDomain = 'GEHOERT_ZU_DOMAIN';
  static const String predicateRequiresSkill = 'BENOETIGT_SKILL';
  static const String predicateRequiresHitl = 'ERFORDERT_HITL';

  static const Set<String> governancePredicates = {
    predicateCanUseSkill,
    predicateSkillDomain,
    predicateRequiresSkill,
    predicateRequiresHitl,
  };

  static const Set<String> governanceEntityTypes = {
    'Agent',
    'Skill',
    'Domain',
    'SecurityPolicy',
  };

  static String agentCanonicalKey(String agentId) => 'agent:${agentId.trim()}';
  static String skillCanonicalKey(String slug) =>
      'skill:${slug.trim().toLowerCase()}';
  static String domainCanonicalKey(String category) =>
      canonicalizeKey('Domain', category.trim().isEmpty ? 'general' : category);

  bool get isInitialized => _initialized;

  /// Update memory configuration dynamically.
  void updateConfig(MemoryConfig newConfig) {
    config = newConfig;
  }

  /// Initialize ObjectBox boxes using an optional [sharedStore] (from RAGMemoryEngine)
  /// or opening a dedicated store in `$stateDir/objectbox_ontology`.
  Future<void> initialize({Store? sharedStore}) async {
    if (_initialized) return;

    try {
      if (sharedStore != null) {
        _store = sharedStore;
        _ownsStore = false;
      } else {
        _store = await openStore(directory: p.join(stateDir, 'objectbox_ontology'));
        _ownsStore = true;
      }

      _relationBox = _store!.box<OntologyRelationDef>();
      _nodeBox = _store!.box<OntologyNode>();
      _edgeBox = _store!.box<OntologyEdge>();
      _initialized = true;

      // Apply pending portable JSON restore if present (created during config.restore)
      final pendingBackup = File(p.join(stateDir, backupFileName));
      if (await pendingBackup.exists()) {
        try {
          final raw = await pendingBackup.readAsString();
          await importJson(raw);
          await pendingBackup.delete();
          _log.info('Applied pending ontology restore from ${pendingBackup.path}');
        } catch (e) {
          _log.warning('Failed to apply pending ontology backup: $e');
        }
      }

      await _seedDefaultRelations();
      _log.info(
        'OntologyStoreService initialized (${_ownsStore ? "standalone" : "shared"} store at $stateDir)',
      );
    } catch (e) {
      _log.severe('Failed to initialize OntologyStoreService: $e');
    }
  }

  /// Close references and release the ObjectBox store if owned by this service.
  Future<void> close() async {
    if (_ownsStore) {
      _store?.close();
    }
    _store = null;
    _ownsStore = false;
    _relationBox = null;
    _nodeBox = null;
    _edgeBox = null;
    _initialized = false;
  }

  /// Idempotently seeds default T-Box relation rules on startup.
  Future<void> _seedDefaultRelations() async {
    if (_store == null || _relationBox == null) return;

    _store!.runInTransaction(TxMode.write, () {
      for (final item in _defaultRelations) {
        final pred = item['predicate'] as String;
        final existing = _findRelationDefSync(pred);
        if (existing == null) {
          _relationBox!.put(
            OntologyRelationDef(
              predicate: pred,
              domainType: item['domainType'] as String,
              rangeType: item['rangeType'] as String,
              isFunctional: item['isFunctional'] as bool,
              isTransitive: item['isTransitive'] as bool,
            ),
          );
        }
      }
    });
  }

  /// Defines or updates an explicit T-Box relation rule.
  Future<OntologyRelationDef> defineRelation({
    required String predicate,
    String domainType = 'Entity',
    String rangeType = 'Entity',
    bool isFunctional = false,
    bool isTransitive = false,
  }) async {
    _ensureReady();
    final normPred = normalizePredicate(predicate);
    if (normPred.isEmpty) {
      throw ArgumentError.value(predicate, 'predicate', 'Predicate must not be empty');
    }

    return _store!.runInTransaction(TxMode.write, () {
      final existing = _findRelationDefSync(normPred);
      final def = existing ??
          OntologyRelationDef(
            predicate: normPred,
            domainType: domainType,
            rangeType: rangeType,
            isFunctional: isFunctional,
            isTransitive: isTransitive,
          );
      if (existing != null) {
        def.domainType = domainType;
        def.rangeType = rangeType;
        def.isFunctional = isFunctional;
        def.isTransitive = isTransitive;
      }
      _relationBox!.put(def);
      return def;
    });
  }

  /// Synchronizes the configured primary user profile to the `user:primary` anchor node.
  Future<void> syncUserProfile(UserConfig user) async {
    if (!_initialized || _store == null) return;
    final cleanName = user.name.trim();
    final label = cleanName.isNotEmpty ? cleanName : 'User';

    _store!.runInTransaction(TxMode.write, () {
      _upsertNodeSync(
        canonicalKey: primaryUserKey,
        label: label,
        entityType: 'Person',
      );
    });

    if (cleanName.isNotEmpty) {
      await assertFact(
        subjectLabel: cleanName,
        subjectType: 'Person',
        subjectKey: primaryUserKey,
        predicate: 'HEISST',
        objectLabel: cleanName,
        objectType: 'Text',
        confidence: 1.0,
      );
    }
  }

  /// Asserts a structured triple `(subject, predicate, object)` with T-Box rule enforcement.
  ///
  /// - Functional predicates (e.g. `WOHNT_IN`) overwrite existing edges of the
  ///   same predicate for the subject.
  /// - Non-functional predicates (e.g. `MAG`) allow multiple distinct objects
  ///   while deduplicating exact `(subject, predicate, object)` triples.
  Future<OntologyAssertResult> assertFact({
    required String subjectLabel,
    String subjectType = 'Entity',
    String? subjectKey,
    required String predicate,
    required String objectLabel,
    String objectType = 'Entity',
    String? objectKey,
    double confidence = 1.0,
    bool autoDefineRelation = true,
  }) async {
    _ensureReady();

    final cleanSubject = subjectLabel.trim();
    final cleanObject = objectLabel.trim();
    final normPredicate = normalizePredicate(predicate);

    if (cleanSubject.isEmpty) {
      throw ArgumentError.value(subjectLabel, 'subjectLabel', 'Subject must not be empty');
    }
    if (cleanObject.isEmpty) {
      throw ArgumentError.value(objectLabel, 'objectLabel', 'Object must not be empty');
    }
    if (normPredicate.isEmpty) {
      throw ArgumentError.value(predicate, 'predicate', 'Predicate must not be empty');
    }

    final clampedConfidence = confidence.clamp(0.0, 1.0).toDouble();

    return _store!.runInTransaction(TxMode.write, () {
      var relDef = _findRelationDefSync(normPredicate);
      if (relDef == null) {
        if (!autoDefineRelation) {
          throw StateError('Unknown ontology predicate: $normPredicate');
        }
        relDef = OntologyRelationDef(
          predicate: normPredicate,
          domainType: subjectType.trim().isEmpty ? 'Entity' : subjectType.trim(),
          rangeType: objectType.trim().isEmpty ? 'Entity' : objectType.trim(),
          isFunctional: false,
          isTransitive: false,
        );
        _relationBox!.put(relDef);
      }

      final effectiveSubjType = _resolveNodeType(subjectType, relDef.domainType);
      final effectiveObjType = _resolveNodeType(objectType, relDef.rangeType);

      final resolvedSubjKey =
          (subjectKey != null && subjectKey.trim().isNotEmpty)
              ? subjectKey.trim()
              : _resolveOrCanonicalizeKeySync(effectiveSubjType, cleanSubject);
      final resolvedObjKey =
          (objectKey != null && objectKey.trim().isNotEmpty)
              ? objectKey.trim()
              : _resolveOrCanonicalizeKeySync(effectiveObjType, cleanObject);

      final subjectNode = _upsertNodeSync(
        canonicalKey: resolvedSubjKey,
        label: cleanSubject,
        entityType: effectiveSubjType,
      );
      final objectNode = _upsertNodeSync(
        canonicalKey: resolvedObjKey,
        label: cleanObject,
        entityType: effectiveObjType,
      );

      final q = _edgeBox!
          .query(
            OntologyEdge_.subjectId.equals(subjectNode.obxId) &
                OntologyEdge_.predicate.equals(normPredicate),
          )
          .build();
      final List<OntologyEdge> existingEdges;
      try {
        existingEdges = q.find();
      } finally {
        q.close();
      }

      final now = DateTime.now();
      OntologyEdge? exactMatch;
      final toRemoveIds = <int>[];

      for (final edge in existingEdges) {
        if (edge.objectId == objectNode.obxId) {
          exactMatch = edge;
        } else if (relDef.isFunctional) {
          toRemoveIds.add(edge.obxId);
        }
      }

      if (toRemoveIds.isNotEmpty) {
        _edgeBox!.removeMany(toRemoveIds);
      }

      if (exactMatch != null) {
        exactMatch.confidence = clampedConfidence;
        exactMatch.createdAt = now;
        _edgeBox!.put(exactMatch);
        return OntologyAssertResult(
          subject: subjectNode,
          predicate: normPredicate,
          object: objectNode,
          edge: exactMatch,
          replacedCount: toRemoveIds.length,
          wasDuplicate: true,
          isFunctional: relDef.isFunctional,
        );
      }

      final newEdge = OntologyEdge(
        subjectId: subjectNode.obxId,
        predicate: normPredicate,
        objectId: objectNode.obxId,
        confidence: clampedConfidence,
        createdAt: now,
      );
      _edgeBox!.put(newEdge);

      return OntologyAssertResult(
        subject: subjectNode,
        predicate: normPredicate,
        object: objectNode,
        edge: newEdge,
        replacedCount: toRemoveIds.length,
        wasDuplicate: false,
        isFunctional: relDef.isFunctional,
      );
    });
  }

  /// Queries facts for [entityQuery] with BFS multi-hop traversal and cycle detection.
  ///
  /// Resolves implicit multi-hop chains (e.g. `Peter -> Zürich -> Schweiz`) up to
  /// [maxDepth] hops (clamped to `1..4`).
  Future<OntologyQueryResult> queryFactsForEntity(
    String entityQuery, {
    int maxDepth = 2,
    int maxResults = 30,
    bool includeIncoming = true,
    double minConfidence = 0.0,
  }) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return OntologyQueryResult(
        query: entityQuery,
        rootNodes: const [],
        directFacts: const [],
        inferredFacts: const [],
      );
    }

    final cleanQuery = entityQuery.trim();
    if (cleanQuery.isEmpty) {
      return OntologyQueryResult(
        query: entityQuery,
        rootNodes: const [],
        directFacts: const [],
        inferredFacts: const [],
      );
    }

    final effectiveDepth = maxDepth.clamp(1, 4);
    final rootNodes = _resolveNodesSync(cleanQuery);
    if (rootNodes.isEmpty) {
      return OntologyQueryResult(
        query: entityQuery,
        rootNodes: const [],
        directFacts: const [],
        inferredFacts: const [],
      );
    }

    // Cache node & relation definitions for fast lookup during BFS
    final nodeCache = <int, OntologyNode>{
      for (final n in _nodeBox!.getAll()) n.obxId: n,
    };
    final relDefCache = <String, OntologyRelationDef>{
      for (final r in _relationBox!.getAll()) r.predicate: r,
    };

    final directFacts = <OntologyTriple>[];
    final inferredFacts = <OntologyTriple>[];
    final visitedNodeIds = <int>{};
    final visitedEdgeIds = <int>{};
    final seenInferredKeys = <String>{};

    final queue = Queue<_TraversalItem>();
    for (final root in rootNodes) {
      if (visitedNodeIds.add(root.obxId)) {
        queue.add(
          _TraversalItem(
            rootNode: root,
            currentNode: root,
            depth: 0,
            pathChain: const [],
            predicatesChain: const [],
            minConfidence: 1.0,
          ),
        );
      }
    }

    int totalCollected() => directFacts.length + inferredFacts.length;

    while (queue.isNotEmpty && totalCollected() < maxResults) {
      final current = queue.removeFirst();
      if (current.depth >= effectiveDepth) continue;

      final outgoing = _getOutgoingEdgesSync(
        current.currentNode.obxId,
        minConfidence: minConfidence,
      );

      for (final edge in outgoing) {
        if (totalCollected() >= maxResults) break;

        final targetNode = nodeCache[edge.objectId];
        if (targetNode == null) continue;

        final stepLabel =
            '${current.currentNode.label} --[${edge.predicate}]--> ${targetNode.label}';
        final nextPath = [...current.pathChain, stepLabel];
        final nextPreds = [...current.predicatesChain, edge.predicate];
        final pathConfidence =
            edge.confidence < current.minConfidence ? edge.confidence : current.minConfidence;
        final hopDepth = current.depth + 1;

        if (visitedEdgeIds.add(edge.obxId)) {
          final isGov = isGovernanceTriple(
            current.currentNode,
            edge.predicate,
            targetNode,
          );
          final triple = OntologyTriple(
            edgeId: hopDepth == 1 ? edge.obxId : null,
            subject: current.currentNode,
            predicate: edge.predicate,
            object: targetNode,
            confidence: edge.confidence,
            createdAt: edge.createdAt,
            isInferred: hopDepth > 1,
            hopDepth: hopDepth,
            pathChain: hopDepth > 1 ? nextPath : const [],
            isGovernance: isGov,
          );

          if (hopDepth == 1) {
            directFacts.add(triple);
          } else {
            inferredFacts.add(triple);
          }
        }

        // Emit homogeneous transitive shortcut if all predicates from root are the same transitive predicate
        if (hopDepth >= 2 && totalCollected() < maxResults) {
          final firstPred = nextPreds.first;
          final isHomogeneousTransitive =
              nextPreds.every((p) => p == firstPred) &&
              (relDefCache[firstPred]?.isTransitive ?? false);

          if (isHomogeneousTransitive && current.rootNode.obxId != targetNode.obxId) {
            final shortcutKey =
                '${current.rootNode.obxId}|$firstPred|${targetNode.obxId}';
            if (seenInferredKeys.add(shortcutKey)) {
              inferredFacts.add(
                OntologyTriple(
                  subject: current.rootNode,
                  predicate: firstPred,
                  object: targetNode,
                  confidence: pathConfidence,
                  createdAt: edge.createdAt,
                  isInferred: true,
                  hopDepth: hopDepth,
                  pathChain: nextPath,
                  isGovernance: isGovernanceTriple(
                    current.rootNode,
                    firstPred,
                    targetNode,
                  ),
                ),
              );
            }
          }
        }

        // Continue BFS only if target hasn't been expanded (cycle prevention)
        if (hopDepth < effectiveDepth && visitedNodeIds.add(targetNode.obxId)) {
          queue.add(
            _TraversalItem(
              rootNode: current.rootNode,
              currentNode: targetNode,
              depth: hopDepth,
              pathChain: nextPath,
              predicatesChain: nextPreds,
              minConfidence: pathConfidence,
            ),
          );
        }
      }

      // Include 1-hop incoming edges for root nodes for bidirectional context
      if (includeIncoming && current.depth == 0) {
        final incoming = _getIncomingEdgesSync(
          current.currentNode.obxId,
          minConfidence: minConfidence,
        );
        for (final edge in incoming) {
          if (totalCollected() >= maxResults) break;
          if (!visitedEdgeIds.add(edge.obxId)) continue;
          final sourceNode = nodeCache[edge.subjectId];
          if (sourceNode == null) continue;
          directFacts.add(
            OntologyTriple(
              edgeId: edge.obxId,
              subject: sourceNode,
              predicate: edge.predicate,
              object: current.currentNode,
              confidence: edge.confidence,
              createdAt: edge.createdAt,
              isInferred: false,
              hopDepth: 1,
              isGovernance: isGovernanceTriple(
                sourceNode,
                edge.predicate,
                current.currentNode,
              ),
            ),
          );
        }
      }
    }

    return OntologyQueryResult(
      query: entityQuery,
      rootNodes: rootNodes,
      directFacts: directFacts,
      inferredFacts: inferredFacts,
    );
  }

  /// Finds existing [OntologyNode]s whose labels appear in [text] without LLM calls.
  List<OntologyNode> findMatchingNodesInText(
    String text, {
    int limit = 5,
    Set<String> excludeEntityTypes = governanceEntityTypes,
  }) {
    if (!_initialized || _nodeBox == null) return const [];
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final textLower = trimmed.toLowerCase();
    final allNodes = _nodeBox!
        .getAll()
        .where((n) => !excludeEntityTypes.contains(n.entityType))
        .toList();
    final matches = <OntologyNode>[];

    // Sort longest labels first so specific entities match before shorter substrings
    allNodes.sort((a, b) => b.label.length.compareTo(a.label.length));

    for (final node in allNodes) {
      if (matches.length >= limit) break;
      final label = node.label.trim();
      if (label.length < 3) continue;

      final labelLower = label.toLowerCase();
      if (!textLower.contains(labelLower)) continue;

      final escaped = RegExp.escape(labelLower);
      final wordPattern = RegExp(
        '(^|[^\\p{L}\\p{N}_])$escaped(\$|[^\\p{L}\\p{N}_])',
        caseSensitive: false,
        unicode: true,
      );
      if (wordPattern.hasMatch(text)) {
        matches.add(node);
      }
    }
    return matches;
  }

  /// Returns whether a triple belongs to the Skill / Agent governance layer.
  static bool isGovernanceTriple(
    OntologyNode subject,
    String predicate,
    OntologyNode object,
  ) {
    return governancePredicates.contains(predicate) ||
        governanceEntityTypes.contains(subject.entityType) ||
        governanceEntityTypes.contains(object.entityType);
  }

  /// Returns all T-Box relation definitions.
  List<OntologyRelationDef> getAllRelationDefs() {
    if (!_initialized || _relationBox == null) return const [];
    return _relationBox!.getAll();
  }

  /// Returns summary statistics for the ontology store.
  OntologyStats getStats() {
    if (!_initialized || _relationBox == null || _nodeBox == null || _edgeBox == null) {
      return const OntologyStats(relationCount: 0, nodeCount: 0, edgeCount: 0);
    }

    final nodes = _nodeBox!.getAll();
    final edges = _edgeBox!.getAll();
    final nodeCache = <int, OntologyNode>{
      for (final n in nodes) n.obxId: n,
    };

    var skillCount = 0;
    for (final node in nodes) {
      if (node.entityType == 'Skill') {
        skillCount++;
      }
    }

    final linkedSkillIds = <int>{};
    var personalEdgeCount = 0;
    var governanceEdgeCount = 0;

    for (final edge in edges) {
      final subj = nodeCache[edge.subjectId];
      final obj = nodeCache[edge.objectId];
      if (subj == null || obj == null) continue;

      if (edge.predicate == predicateCanUseSkill && obj.entityType == 'Skill') {
        linkedSkillIds.add(obj.obxId);
      }

      if (isGovernanceTriple(subj, edge.predicate, obj)) {
        governanceEdgeCount++;
      } else {
        personalEdgeCount++;
      }
    }

    return OntologyStats(
      relationCount: _relationBox!.count(),
      nodeCount: nodes.length,
      edgeCount: edges.length,
      skillCount: skillCount,
      linkedSkillCount: linkedSkillIds.length,
      personalEdgeCount: personalEdgeCount,
      governanceEdgeCount: governanceEdgeCount,
    );
  }

  /// Lists resolved triples filtered by [category] (`all`, `personal`, `governance`)
  /// and case-insensitive search [query], sorted newest-first.
  ({List<OntologyTriple> facts, int totalCount}) listFacts({
    String category = 'all',
    String query = '',
    int limit = 200,
    int offset = 0,
  }) {
    if (!_initialized || _nodeBox == null || _edgeBox == null) {
      return (facts: const <OntologyTriple>[], totalCount: 0);
    }

    final nodeCache = <int, OntologyNode>{
      for (final n in _nodeBox!.getAll()) n.obxId: n,
    };
    final edges = _edgeBox!.getAll();
    final normalizedCat = category.trim().toLowerCase();
    final normalizedQuery = query.trim().toLowerCase();

    final matched = <OntologyTriple>[];
    for (final edge in edges) {
      final subj = nodeCache[edge.subjectId];
      final obj = nodeCache[edge.objectId];
      if (subj == null || obj == null) continue;

      final isGov = isGovernanceTriple(subj, edge.predicate, obj);
      if (normalizedCat == 'personal' && isGov) continue;
      if (normalizedCat == 'governance' && !isGov) continue;

      if (normalizedQuery.isNotEmpty) {
        final haystacks = [
          subj.label,
          subj.canonicalKey,
          subj.entityType,
          edge.predicate,
          obj.label,
          obj.canonicalKey,
          obj.entityType,
        ];
        final hits = haystacks.any((h) => h.toLowerCase().contains(normalizedQuery));
        if (!hits) continue;
      }

      matched.add(
        OntologyTriple(
          edgeId: edge.obxId,
          subject: subj,
          predicate: edge.predicate,
          object: obj,
          confidence: edge.confidence,
          createdAt: edge.createdAt,
          isInferred: false,
          hopDepth: 1,
          isGovernance: isGov,
        ),
      );
    }

    matched.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final totalCount = matched.length;
    final safeOffset = offset.clamp(0, totalCount);
    final safeLimit = limit.clamp(1, 1000);
    final end = (safeOffset + safeLimit).clamp(0, totalCount);

    return (
      facts: matched.sublist(safeOffset, end),
      totalCount: totalCount,
    );
  }

  /// Lists entity nodes filtered by [category] (`all`, `personal`, `governance`)
  /// and case-insensitive [query], including each node's incident edge count.
  List<OntologyNodeSummary> listNodes({
    String category = 'all',
    String query = '',
  }) {
    if (!_initialized || _nodeBox == null || _edgeBox == null) {
      return const [];
    }

    final nodes = _nodeBox!.getAll();
    final edges = _edgeBox!.getAll();
    final edgeCounts = <int, int>{};
    for (final edge in edges) {
      edgeCounts[edge.subjectId] = (edgeCounts[edge.subjectId] ?? 0) + 1;
      if (edge.objectId != edge.subjectId) {
        edgeCounts[edge.objectId] = (edgeCounts[edge.objectId] ?? 0) + 1;
      }
    }

    final normalizedCat = category.trim().toLowerCase();
    final normalizedQuery = query.trim().toLowerCase();
    final summaries = <OntologyNodeSummary>[];

    for (final node in nodes) {
      final isGov = governanceEntityTypes.contains(node.entityType);
      if (normalizedCat == 'personal' && isGov) continue;
      if (normalizedCat == 'governance' && !isGov) continue;

      if (normalizedQuery.isNotEmpty) {
        final hits = node.label.toLowerCase().contains(normalizedQuery) ||
            node.canonicalKey.toLowerCase().contains(normalizedQuery) ||
            node.entityType.toLowerCase().contains(normalizedQuery);
        if (!hits) continue;
      }

      summaries.add(
        OntologyNodeSummary(
          nodeId: node.obxId,
          canonicalKey: node.canonicalKey,
          label: node.label,
          entityType: node.entityType,
          edgeCount: edgeCounts[node.obxId] ?? 0,
          isGovernance: isGov,
          updatedAt: node.updatedAt,
        ),
      );
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// Deletes a single fact edge by its ObjectBox [edgeId].
  Future<bool> deleteEdge(int edgeId) async {
    if (!_initialized || _store == null || _edgeBox == null) {
      return false;
    }
    return _store!.runInTransaction(TxMode.write, () {
      return _edgeBox!.remove(edgeId);
    });
  }

  /// Deletes an entity node by [canonicalKey] along with all incident edges.
  Future<bool> deleteNode(String canonicalKey) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return false;
    }
    final cleanKey = canonicalKey.trim();
    if (cleanKey.isEmpty) return false;
    return _store!.runInTransaction(TxMode.write, () {
      final node = _findNodeByKeySync(cleanKey);
      if (node == null) return false;
      _deleteNodeAndEdgesSync(node.obxId);
      return true;
    });
  }

  /// Exports the full T-Box and A-Box as portable JSON using `canonicalKey` references.
  Future<String> exportJson() async {
    if (!_initialized || _relationBox == null || _nodeBox == null || _edgeBox == null) {
      return jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'relations': const <dynamic>[],
        'nodes': const <dynamic>[],
        'edges': const <dynamic>[],
      });
    }

    final relations = _relationBox!.getAll();
    final nodes = _nodeBox!.getAll();
    final edges = _edgeBox!.getAll();

    final idToKey = <int, String>{
      for (final node in nodes) node.obxId: node.canonicalKey,
    };

    final serializedEdges = <Map<String, dynamic>>[];
    for (final edge in edges) {
      final subjKey = idToKey[edge.subjectId];
      final objKey = idToKey[edge.objectId];
      if (subjKey == null || objKey == null) continue;
      serializedEdges.add({
        'subjectKey': subjKey,
        'predicate': edge.predicate,
        'objectKey': objKey,
        'confidence': edge.confidence,
        'createdAt': edge.createdAt.toIso8601String(),
      });
    }

    return jsonEncode({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'relations': relations.map((r) => r.toJson()).toList(),
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': serializedEdges,
    });
  }

  /// Restores T-Box and A-Box from a portable JSON export, remapping node IDs.
  Future<void> importJson(String jsonData) async {
    _ensureReady();
    final decoded = jsonDecode(jsonData);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid ontology backup format: root must be an object');
    }

    final rawRelations = decoded['relations'] as List<dynamic>? ?? const [];
    final rawNodes = decoded['nodes'] as List<dynamic>? ?? const [];
    final rawEdges = decoded['edges'] as List<dynamic>? ?? const [];

    _store!.runInTransaction(TxMode.write, () {
      _edgeBox!.removeAll();
      _nodeBox!.removeAll();
      _relationBox!.removeAll();

      for (final item in rawRelations) {
        if (item is Map<String, dynamic>) {
          _relationBox!.put(OntologyRelationDef.fromJson(item));
        } else if (item is Map) {
          _relationBox!.put(OntologyRelationDef.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      final keyToId = <String, int>{};
      for (final item in rawNodes) {
        final map = item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map);
        final node = OntologyNode.fromJson(map);
        final id = _nodeBox!.put(node);
        keyToId[node.canonicalKey] = id;
      }

      for (final item in rawEdges) {
        final map = item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map);
        final subjId = keyToId[map['subjectKey'] as String? ?? ''];
        final objId = keyToId[map['objectKey'] as String? ?? ''];
        final pred = map['predicate'] as String? ?? '';
        if (subjId == null || objId == null || pred.isEmpty) continue;

        _edgeBox!.put(
          OntologyEdge(
            subjectId: subjId,
            predicate: normalizePredicate(pred),
            objectId: objId,
            confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
            createdAt: map['createdAt'] != null
                ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
                : DateTime.now(),
          ),
        );
      }
    });

    await _seedDefaultRelations();
    _log.info(
      'Imported ontology backup: ${rawRelations.length} relations, ${rawNodes.length} nodes, ${rawEdges.length} edges',
    );
  }

  /// Clears all ontology edges, nodes, and relation definitions.
  /// Set [reseedDefaults] to `true` when clearing user knowledge while keeping T-Box rules.
  Future<void> clear({bool reseedDefaults = false}) async {
    if (!_initialized || _store == null || _edgeBox == null || _nodeBox == null || _relationBox == null) {
      return;
    }

    _store!.runInTransaction(TxMode.write, () {
      _edgeBox!.removeAll();
      _nodeBox!.removeAll();
      _relationBox!.removeAll();
    });

    if (reseedDefaults) {
      await _seedDefaultRelations();
    }
    _log.info('Cleared ontology store (reseedDefaults: $reseedDefaults)');
  }

  /// Normalizes a predicate string to `UPPER_SNAKE_CASE`.
  static String normalizePredicate(String raw) {
    var s = raw.trim().toUpperCase();
    s = s
        .replaceAll('Ä', 'AE')
        .replaceAll('Ö', 'OE')
        .replaceAll('Ü', 'UE')
        .replaceAll('ß', 'SS');
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  /// Produces a deterministic canonical key `<type>:<slug>` for an entity.
  static String canonicalizeKey(String entityType, String label) {
    final typeSlug = _slugify(entityType.isEmpty ? 'entity' : entityType);
    final labelSlug = _slugify(label);
    return '$typeSlug:$labelSlug';
  }

  static String _slugify(String raw) {
    var s = raw.trim().toLowerCase();
    s = s
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'unknown' : s;
  }

  // ---------------------------------------------------------------------------
  // Skill & Agent Permission Graph Synchronization
  // ---------------------------------------------------------------------------

  /// Synchronizes all installed [skills] into the Ontology Knowledge Graph:
  /// - Upserts `Skill` nodes with compact metadata (`shortDescription`, `category`,
  ///   `requiresHitl`, `securityLevel`, runtime flags, `dependencies`).
  /// - Maintains `GEHOERT_ZU_DOMAIN`, `BENOETIGT_SKILL`, and `ERFORDERT_HITL` edges.
  /// - Prunes uninstalled `Skill` nodes and their stale edges.
  Future<void> syncSkills(
    List<Skill> skills, {
    Map<String, String>? shortDescriptions,
  }) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return;
    }

    _store!.runInTransaction(TxMode.write, () {
      final hitlNode = _upsertNodeSync(
        canonicalKey: hitlPolicyKey,
        label: 'HITL Approval Required',
        entityType: 'SecurityPolicy',
      );

      final activeSkillKeys = <String>{};
      final skillNodeBySlug = <String, OntologyNode>{};

      for (final skill in skills) {
        final normSlug = skill.slug.trim().toLowerCase();
        if (normSlug.isEmpty) continue;

        final skillKey = skillCanonicalKey(normSlug);
        activeSkillKeys.add(skillKey);

        final shortDesc = (shortDescriptions?[skill.slug] ??
                shortDescriptions?[normSlug] ??
                skill.description)
            .trim();
        final category = skill.category.trim().isEmpty
            ? 'general'
            : skill.category.trim().toLowerCase();

        final metaJson = jsonEncode({
          'slug': skill.slug,
          'shortDescription': shortDesc,
          'category': category,
          'requiresHitl': skill.requiresHitl,
          'securityLevel': skill.securityLevel,
          'hasMcp': skill.hasMcp,
          'hasPython': skill.hasPython,
          'hasNode': skill.hasNode,
          'dependencies': skill.requiredSkills,
        });

        final skillNode = _upsertNodeSync(
          canonicalKey: skillKey,
          label: skill.name.trim().isNotEmpty ? skill.name.trim() : skill.slug,
          entityType: 'Skill',
          metadataJson: metaJson,
        );
        skillNodeBySlug[normSlug] = skillNode;

        // 1. GEHOERT_ZU_DOMAIN (functional)
        final domainNode = _upsertNodeSync(
          canonicalKey: domainCanonicalKey(category),
          label: category,
          entityType: 'Domain',
        );
        _setFunctionalEdgeSync(
          subjectId: skillNode.obxId,
          predicate: predicateSkillDomain,
          objectId: domainNode.obxId,
        );

        // 2. ERFORDERT_HITL (functional)
        if (skill.requiresHitl) {
          _setFunctionalEdgeSync(
            subjectId: skillNode.obxId,
            predicate: predicateRequiresHitl,
            objectId: hitlNode.obxId,
          );
        } else {
          _removeEdgesSync(
            subjectId: skillNode.obxId,
            predicate: predicateRequiresHitl,
          );
        }
      }

      // 3. BENOETIGT_SKILL edges (after all active Skill nodes exist)
      for (final skill in skills) {
        final normSlug = skill.slug.trim().toLowerCase();
        final skillNode = skillNodeBySlug[normSlug];
        if (skillNode == null) continue;

        final targetIds = <int>{};
        for (final dep in skill.requiredSkills) {
          final depSlug = dep.trim().toLowerCase();
          if (depSlug.isEmpty || depSlug == normSlug) continue;
          final depNode = skillNodeBySlug[depSlug];
          if (depNode != null) {
            targetIds.add(depNode.obxId);
          }
        }
        _syncEdgeTargetsSync(
          subjectId: skillNode.obxId,
          predicate: predicateRequiresSkill,
          targetObjectIds: targetIds,
        );
      }

      // 4. Prune uninstalled Skill nodes and all incident edges
      final allNodes = _nodeBox!.getAll();
      for (final node in allNodes) {
        if (node.entityType == 'Skill' &&
            !activeSkillKeys.contains(node.canonicalKey)) {
          _deleteNodeAndEdgesSync(node.obxId);
        }
      }
    });
  }

  /// Removes a deleted skill node and all its incident edges from the ontology.
  Future<void> removeSkillNode(String slug) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return;
    }
    final key = skillCanonicalKey(slug);
    _store!.runInTransaction(TxMode.write, () {
      final node = _findNodeByKeySync(key);
      if (node != null) {
        _deleteNodeAndEdgesSync(node.obxId);
      }
    });
  }

  /// Synchronizes `DARF_NUTZEN` permission edges for an agent.
  Future<void> syncAgentSkillPermissions({
    required String agentId,
    required String agentName,
    required List<String> allowedSkillSlugs,
  }) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return;
    }

    _store!.runInTransaction(TxMode.write, () {
      final agentNode = _upsertNodeSync(
        canonicalKey: agentCanonicalKey(agentId),
        label: agentName.trim().isNotEmpty ? agentName.trim() : agentId,
        entityType: 'Agent',
      );

      final targetIds = <int>{};
      for (final slug in allowedSkillSlugs) {
        final skillNode = _findNodeByKeySync(skillCanonicalKey(slug));
        if (skillNode != null) {
          targetIds.add(skillNode.obxId);
        }
      }

      _syncEdgeTargetsSync(
        subjectId: agentNode.obxId,
        predicate: predicateCanUseSkill,
        targetObjectIds: targetIds,
      );
    });
  }

  /// Removes a deleted custom agent node and its `DARF_NUTZEN` edges.
  Future<void> removeAgentNode(String agentId) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return;
    }
    final key = agentCanonicalKey(agentId);
    _store!.runInTransaction(TxMode.write, () {
      final node = _findNodeByKeySync(key);
      if (node != null) {
        _deleteNodeAndEdgesSync(node.obxId);
      }
    });
  }

  /// Removes any `Agent` nodes whose IDs are not in [activeAgentIds].
  Future<void> pruneOrphanAgentNodes(Set<String> activeAgentIds) async {
    if (!_initialized || _store == null || _nodeBox == null || _edgeBox == null) {
      return;
    }
    final validKeys = activeAgentIds.map(agentCanonicalKey).toSet();
    _store!.runInTransaction(TxMode.write, () {
      final allNodes = _nodeBox!.getAll();
      for (final node in allNodes) {
        if (node.entityType == 'Agent' &&
            !validKeys.contains(node.canonicalKey)) {
          _deleteNodeAndEdgesSync(node.obxId);
        }
      }
    });
  }

  /// Returns all skills that [agentId] is authorized to use via `DARF_NUTZEN`.
  List<SkillOntologySummary> getAllowedSkillsForAgent(String agentId) {
    if (!_initialized || _nodeBox == null || _edgeBox == null) {
      return const [];
    }

    final agentNode = _findNodeByKeySync(agentCanonicalKey(agentId));
    if (agentNode == null) return const [];

    final nodeCache = <int, OntologyNode>{
      for (final n in _nodeBox!.getAll()) n.obxId: n,
    };
    final outgoing = _getOutgoingEdgesSync(agentNode.obxId)
        .where((e) => e.predicate == predicateCanUseSkill);

    final summaries = <SkillOntologySummary>[];
    final seenSlugs = <String>{};

    for (final edge in outgoing) {
      final skillNode = nodeCache[edge.objectId];
      if (skillNode == null || skillNode.entityType != 'Skill') continue;

      final skillEdges = _getOutgoingEdgesSync(skillNode.obxId);
      final hasHitlEdge = skillEdges.any((e) => e.predicate == predicateRequiresHitl);
      final summary = SkillOntologySummary.fromNode(
        skillNode,
        requiresHitlOverride: hasHitlEdge ? true : null,
      );
      if (seenSlugs.add(summary.slug)) {
        summaries.add(summary);
      }
    }

    summaries.sort((a, b) {
      final catCmp = a.category.compareTo(b.category);
      if (catCmp != 0) return catCmp;
      return a.slug.compareTo(b.slug);
    });
    return summaries;
  }

  /// Resolves [skillQuery] (slug or display name) ONLY if [agentId] has a `DARF_NUTZEN` edge to it.
  SkillOntologySummary? resolveAuthorizedSkill(
    String agentId,
    String skillQuery,
  ) {
    final clean = skillQuery.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final normalizedKeySlug = clean.startsWith('skill:')
        ? clean.substring(6)
        : clean;

    final allowed = getAllowedSkillsForAgent(agentId);
    for (final s in allowed) {
      if (s.slug.toLowerCase() == normalizedKeySlug) return s;
    }
    for (final s in allowed) {
      if (s.name.toLowerCase() == normalizedKeySlug) return s;
    }
    return null;
  }

  /// Checks whether a skill node matching [skillQuery] exists in the ontology at all.
  bool isSkillInstalledInOntology(String skillQuery) {
    if (!_initialized || _nodeBox == null) return false;
    final clean = skillQuery.trim().toLowerCase();
    if (clean.isEmpty) return false;
    final slug = clean.startsWith('skill:') ? clean.substring(6) : clean;

    if (_findNodeByKeySync(skillCanonicalKey(slug)) != null) return true;
    return _nodeBox!.getAll().any(
          (n) => n.entityType == 'Skill' && n.label.trim().toLowerCase() == slug,
        );
  }

  /// Returns whether the skill [slug] requires HITL via `ERFORDERT_HITL` edge or metadata.
  bool skillRequiresHitl(String slug) {
    if (!_initialized || _nodeBox == null || _edgeBox == null) return false;
    final node = _findNodeByKeySync(skillCanonicalKey(slug));
    if (node == null) return false;
    final hasEdge = _getOutgoingEdgesSync(node.obxId)
        .any((e) => e.predicate == predicateRequiresHitl);
    if (hasEdge) return true;
    return node.metadata['requiresHitl'] as bool? ?? false;
  }

  /// Resolves transitive `BENOETIGT_SKILL` dependencies for [slug] with cycle protection.
  List<String> getRequiredSkillSlugs(String slug, {int maxDepth = 3}) {
    if (!_initialized || _nodeBox == null || _edgeBox == null) {
      return const [];
    }
    final rootNode = _findNodeByKeySync(skillCanonicalKey(slug));
    if (rootNode == null) return const [];

    final nodeCache = <int, OntologyNode>{
      for (final n in _nodeBox!.getAll()) n.obxId: n,
    };
    final visitedIds = <int>{rootNode.obxId};
    final result = <String>[];
    final queue = Queue<({int nodeId, int depth})>()
      ..add((nodeId: rootNode.obxId, depth: 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.depth >= maxDepth) continue;

      final outgoing = _getOutgoingEdgesSync(current.nodeId)
          .where((e) => e.predicate == predicateRequiresSkill);
      for (final edge in outgoing) {
        final target = nodeCache[edge.objectId];
        if (target == null || target.entityType != 'Skill') continue;
        if (!visitedIds.add(target.obxId)) continue;
        final depSummary = SkillOntologySummary.fromNode(target);
        result.add(depSummary.slug);
        queue.add((nodeId: target.obxId, depth: current.depth + 1));
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Internal Synchronous Helpers (safe inside ObjectBox transactions)
  // ---------------------------------------------------------------------------

  void _ensureReady() {
    if (!_initialized || _store == null || _relationBox == null || _nodeBox == null || _edgeBox == null) {
      throw StateError('OntologyStoreService is not initialized.');
    }
  }

  String _resolveNodeType(String requestedType, String fallbackType) {
    final clean = requestedType.trim();
    if (clean.isEmpty || clean == 'Entity') {
      return fallbackType.trim().isEmpty ? 'Entity' : fallbackType.trim();
    }
    return clean;
  }

  OntologyRelationDef? _findRelationDefSync(String normPredicate) {
    final q = _relationBox!
        .query(OntologyRelationDef_.predicate.equals(normPredicate))
        .build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  String _resolveOrCanonicalizeKeySync(String entityType, String label) {
    final candidateKey = canonicalizeKey(entityType, label);
    final exactKeyNode = _findNodeByKeySync(candidateKey);
    if (exactKeyNode != null) return exactKeyNode.canonicalKey;

    // Also reuse an existing node with identical case-insensitive label (e.g. primary user or generic Entity)
    final allNodes = _nodeBox!.getAll();
    final labelLower = label.trim().toLowerCase();
    for (final node in allNodes) {
      if (node.label.trim().toLowerCase() == labelLower) {
        if (node.entityType == entityType ||
            node.entityType == 'Entity' ||
            entityType == 'Entity' ||
            node.canonicalKey == primaryUserKey) {
          return node.canonicalKey;
        }
      }
    }
    return candidateKey;
  }

  OntologyNode? _findNodeByKeySync(String canonicalKey) {
    final q = _nodeBox!
        .query(OntologyNode_.canonicalKey.equals(canonicalKey))
        .build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  OntologyNode _upsertNodeSync({
    required String canonicalKey,
    required String label,
    required String entityType,
    String? metadataJson,
  }) {
    final existing = _findNodeByKeySync(canonicalKey);
    final now = DateTime.now();
    if (existing != null) {
      existing.label = label;
      if (existing.entityType == 'Entity' && entityType != 'Entity') {
        existing.entityType = entityType;
      }
      if (metadataJson != null) {
        existing.metadataJson = metadataJson;
      }
      existing.updatedAt = now;
      _nodeBox!.put(existing);
      return existing;
    }

    final created = OntologyNode(
      canonicalKey: canonicalKey,
      label: label,
      entityType: entityType,
      metadataJson: metadataJson ?? '{}',
      updatedAt: now,
    );
    _nodeBox!.put(created);
    return created;
  }

  void _setFunctionalEdgeSync({
    required int subjectId,
    required String predicate,
    required int objectId,
  }) {
    final q = _edgeBox!
        .query(
          OntologyEdge_.subjectId.equals(subjectId) &
              OntologyEdge_.predicate.equals(predicate),
        )
        .build();
    final List<OntologyEdge> existing;
    try {
      existing = q.find();
    } finally {
      q.close();
    }

    OntologyEdge? exact;
    final toRemove = <int>[];
    for (final edge in existing) {
      if (edge.objectId == objectId) {
        exact = edge;
      } else {
        toRemove.add(edge.obxId);
      }
    }
    if (toRemove.isNotEmpty) {
      _edgeBox!.removeMany(toRemove);
    }
    if (exact == null) {
      _edgeBox!.put(
        OntologyEdge(
          subjectId: subjectId,
          predicate: predicate,
          objectId: objectId,
          confidence: 1.0,
        ),
      );
    }
  }

  void _removeEdgesSync({
    required int subjectId,
    required String predicate,
  }) {
    final q = _edgeBox!
        .query(
          OntologyEdge_.subjectId.equals(subjectId) &
              OntologyEdge_.predicate.equals(predicate),
        )
        .build();
    try {
      final edges = q.find();
      if (edges.isNotEmpty) {
        _edgeBox!.removeMany(edges.map((e) => e.obxId).toList());
      }
    } finally {
      q.close();
    }
  }

  void _syncEdgeTargetsSync({
    required int subjectId,
    required String predicate,
    required Set<int> targetObjectIds,
  }) {
    final q = _edgeBox!
        .query(
          OntologyEdge_.subjectId.equals(subjectId) &
              OntologyEdge_.predicate.equals(predicate),
        )
        .build();
    final List<OntologyEdge> existing;
    try {
      existing = q.find();
    } finally {
      q.close();
    }

    final existingTargetIds = <int>{};
    final toRemove = <int>[];
    for (final edge in existing) {
      if (targetObjectIds.contains(edge.objectId) &&
          existingTargetIds.add(edge.objectId)) {
        continue;
      }
      toRemove.add(edge.obxId);
    }
    if (toRemove.isNotEmpty) {
      _edgeBox!.removeMany(toRemove);
    }

    final now = DateTime.now();
    for (final targetId in targetObjectIds) {
      if (!existingTargetIds.contains(targetId)) {
        _edgeBox!.put(
          OntologyEdge(
            subjectId: subjectId,
            predicate: predicate,
            objectId: targetId,
            confidence: 1.0,
            createdAt: now,
          ),
        );
      }
    }
  }

  void _deleteNodeAndEdgesSync(int nodeId) {
    final outQ = _edgeBox!.query(OntologyEdge_.subjectId.equals(nodeId)).build();
    final inQ = _edgeBox!.query(OntologyEdge_.objectId.equals(nodeId)).build();
    try {
      final edgeIds = <int>{
        ...outQ.find().map((e) => e.obxId),
        ...inQ.find().map((e) => e.obxId),
      };
      if (edgeIds.isNotEmpty) {
        _edgeBox!.removeMany(edgeIds.toList());
      }
    } finally {
      outQ.close();
      inQ.close();
    }
    _nodeBox!.remove(nodeId);
  }

  List<OntologyNode> _resolveNodesSync(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    // 1. Exact canonicalKey match
    final byKey = _findNodeByKeySync(clean);
    if (byKey != null) return [byKey];

    final allNodes = _nodeBox!.getAll();
    final lower = clean.toLowerCase();
    final slug = _slugify(clean);

    // 2. Exact case-insensitive label match
    final exactLabels = allNodes
        .where((n) => n.label.trim().toLowerCase() == lower)
        .toList();
    if (exactLabels.isNotEmpty) return exactLabels;

    // 3. Slug suffix match on canonicalKey (e.g. "zuerich" matches "place:zuerich")
    final slugMatches = allNodes.where((n) {
      final parts = n.canonicalKey.split(':');
      return parts.length == 2 && parts[1] == slug;
    }).toList();
    if (slugMatches.isNotEmpty) return slugMatches;

    // 4. Fallback substring match on label
    return allNodes
        .where((n) => n.label.toLowerCase().contains(lower))
        .take(3)
        .toList();
  }

  List<OntologyEdge> _getOutgoingEdgesSync(
    int subjectId, {
    double minConfidence = 0.0,
  }) {
    final q = _edgeBox!
        .query(OntologyEdge_.subjectId.equals(subjectId))
        .build();
    try {
      return q.find().where((e) => e.confidence >= minConfidence).toList();
    } finally {
      q.close();
    }
  }

  List<OntologyEdge> _getIncomingEdgesSync(
    int objectId, {
    double minConfidence = 0.0,
  }) {
    final q = _edgeBox!
        .query(OntologyEdge_.objectId.equals(objectId))
        .build();
    try {
      return q.find().where((e) => e.confidence >= minConfidence).toList();
    } finally {
      q.close();
    }
  }
}

class _TraversalItem {
  const _TraversalItem({
    required this.rootNode,
    required this.currentNode,
    required this.depth,
    required this.pathChain,
    required this.predicatesChain,
    required this.minConfidence,
  });

  final OntologyNode rootNode;
  final OntologyNode currentNode;
  final int depth;
  final List<String> pathChain;
  final List<String> predicatesChain;
  final double minConfidence;
}
