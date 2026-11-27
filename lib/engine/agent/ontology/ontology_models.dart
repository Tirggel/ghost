// Ghost — Ontology & Knowledge Graph Data Models (T-Box & A-Box).

import 'dart:convert';
import 'package:objectbox/objectbox.dart';

/// T-Box: Schema and semantic rules for an ontology relation/predicate.
@Entity()
class OntologyRelationDef {
  OntologyRelationDef({
    this.obxId = 0,
    required this.predicate,
    this.domainType = 'Entity',
    this.rangeType = 'Entity',
    this.isFunctional = false,
    this.isTransitive = false,
  });

  @Id()
  int obxId = 0;

  /// Normalized predicate name in UPPER_SNAKE_CASE (e.g. WOHNT_IN, HEISST).
  @Unique()
  String predicate;

  /// Expected entity type of the subject (e.g. Person, Place, Entity).
  String domainType;

  /// Expected entity type of the object (e.g. Place, Project, Text, Entity).
  String rangeType;

  /// Functional relation (at most one active object per subject for this predicate).
  /// Asserting a new object replaces existing edges for the same (subject, predicate).
  bool isFunctional;

  /// Transitive relation (supports multi-hop transitive inference, e.g. LIEGT_IN).
  bool isTransitive;

  Map<String, dynamic> toJson() => {
        'predicate': predicate,
        'domainType': domainType,
        'rangeType': rangeType,
        'isFunctional': isFunctional,
        'isTransitive': isTransitive,
      };

  factory OntologyRelationDef.fromJson(Map<String, dynamic> json) {
    return OntologyRelationDef(
      predicate: json['predicate'] as String,
      domainType: json['domainType'] as String? ?? 'Entity',
      rangeType: json['rangeType'] as String? ?? 'Entity',
      isFunctional: json['isFunctional'] as bool? ?? false,
      isTransitive: json['isTransitive'] as bool? ?? false,
    );
  }
}

/// A-Box: Entity node in the Knowledge Graph.
@Entity()
class OntologyNode {
  OntologyNode({
    this.obxId = 0,
    required this.canonicalKey,
    required this.label,
    this.entityType = 'Entity',
    this.metadataJson = '{}',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  @Id()
  int obxId = 0;

  /// Stable canonical identifier (e.g. "user:primary", "place:zuerich").
  @Unique()
  String canonicalKey;

  /// Human-readable display label (e.g. "Peter", "Zürich").
  @Index()
  String label;

  /// Semantic entity type (e.g. Person, Place, Project, Organization, Entity).
  @Index()
  String entityType;

  /// JSON-encoded metadata payload (e.g. skill description, category, HITL policy).
  String metadataJson;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  @Transient()
  Map<String, dynamic> get metadata {
    if (metadataJson.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(metadataJson);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return const {};
  }

  Map<String, dynamic> toJson() => {
        'canonicalKey': canonicalKey,
        'label': label,
        'entityType': entityType,
        if (metadataJson.isNotEmpty && metadataJson != '{}')
          'metadataJson': metadataJson,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory OntologyNode.fromJson(Map<String, dynamic> json) {
    return OntologyNode(
      canonicalKey: json['canonicalKey'] as String,
      label: json['label'] as String,
      entityType: json['entityType'] as String? ?? 'Entity',
      metadataJson: json['metadataJson'] as String? ?? '{}',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// A-Box: Directed edge (fact triple) connecting two [OntologyNode]s.
@Entity()
class OntologyEdge {
  OntologyEdge({
    this.obxId = 0,
    required this.subjectId,
    required this.predicate,
    required this.objectId,
    this.confidence = 1.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  @Id()
  int obxId = 0;

  @Index()
  int subjectId;

  @Index()
  String predicate;

  @Index()
  int objectId;

  double confidence;

  @Property(type: PropertyType.date)
  DateTime createdAt;
}

/// Resolved triple returned by queries and multi-hop graph traversal.
class OntologyTriple {
  const OntologyTriple({
    required this.subject,
    required this.predicate,
    required this.object,
    required this.confidence,
    required this.createdAt,
    this.isInferred = false,
    this.hopDepth = 1,
    this.pathChain = const [],
  });

  final OntologyNode subject;
  final String predicate;
  final OntologyNode object;
  final double confidence;
  final DateTime createdAt;
  final bool isInferred;
  final int hopDepth;

  /// Sequence of steps for multi-hop/inferred triples (e.g. ["Peter --[WOHNT_IN]--> Zürich", "Zürich --[LIEGT_IN]--> Schweiz"]).
  final List<String> pathChain;

  String toReadableString() {
    final suffix = isInferred ? ' [inferred]' : '';
    return '${subject.label} --[$predicate]--> ${object.label}$suffix';
  }

  Map<String, dynamic> toJson() => {
        'subject': subject.label,
        'subjectKey': subject.canonicalKey,
        'subjectType': subject.entityType,
        'predicate': predicate,
        'object': object.label,
        'objectKey': object.canonicalKey,
        'objectType': object.entityType,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
        'isInferred': isInferred,
        'hopDepth': hopDepth,
        if (pathChain.isNotEmpty) 'pathChain': pathChain,
      };
}

/// Result of asserting a fact into the ontology store.
class OntologyAssertResult {
  const OntologyAssertResult({
    required this.subject,
    required this.predicate,
    required this.object,
    required this.edge,
    required this.replacedCount,
    required this.wasDuplicate,
    required this.isFunctional,
  });

  final OntologyNode subject;
  final String predicate;
  final OntologyNode object;
  final OntologyEdge edge;
  final int replacedCount;
  final bool wasDuplicate;
  final bool isFunctional;

  Map<String, dynamic> toJson() => {
        'subject': subject.toJson(),
        'predicate': predicate,
        'object': object.toJson(),
        'confidence': edge.confidence,
        'isFunctional': isFunctional,
        'replacedCount': replacedCount,
        'wasDuplicate': wasDuplicate,
      };
}

/// Result of a multi-hop entity query.
class OntologyQueryResult {
  const OntologyQueryResult({
    required this.query,
    required this.rootNodes,
    required this.directFacts,
    required this.inferredFacts,
  });

  final String query;
  final List<OntologyNode> rootNodes;
  final List<OntologyTriple> directFacts;
  final List<OntologyTriple> inferredFacts;

  bool get isEmpty => directFacts.isEmpty && inferredFacts.isEmpty;

  List<OntologyTriple> get allFacts => [...directFacts, ...inferredFacts];

  /// Formats a compact, token-efficient summary for system prompt injection.
  String toCompactPromptString({int maxLines = 15}) {
    if (isEmpty) return '';
    final lines = <String>[];
    final seen = <String>{};

    for (final fact in directFacts) {
      if (lines.length >= maxLines) break;
      final line = '${fact.subject.label} --[${fact.predicate}]--> ${fact.object.label}';
      if (seen.add(line)) {
        lines.add('- $line');
      }
    }

    for (final fact in inferredFacts) {
      if (lines.length >= maxLines) break;
      final via = fact.pathChain.isNotEmpty
          ? ' (via ${fact.pathChain.join(' -> ')})'
          : '';
      final line =
          '${fact.subject.label} --[${fact.predicate}]--> ${fact.object.label}$via';
      if (seen.add(line)) {
        lines.add('- $line');
      }
    }

    return lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'rootNodes': rootNodes.map((n) => n.toJson()).toList(),
        'directFacts': directFacts.map((f) => f.toJson()).toList(),
        'inferredFacts': inferredFacts.map((f) => f.toJson()).toList(),
      };
}

/// Summary counts of the ontology store.
class OntologyStats {
  const OntologyStats({
    required this.relationCount,
    required this.nodeCount,
    required this.edgeCount,
  });

  final int relationCount;
  final int nodeCount;
  final int edgeCount;

  Map<String, dynamic> toJson() => {
        'relations': relationCount,
        'nodes': nodeCount,
        'edges': edgeCount,
      };
}

/// Compact representation of an authorized Skill stored in the Ontology Graph
/// for Progressive Disclosure (Stage 1 index & Stage 2 validation/HITL).
class SkillOntologySummary {
  const SkillOntologySummary({
    required this.slug,
    required this.name,
    required this.shortDescription,
    this.category = 'general',
    this.requiresHitl = false,
    this.securityLevel = 'standard',
    this.dependencies = const [],
    this.hasMcp = false,
    this.hasPython = false,
    this.hasNode = false,
  });

  final String slug;
  final String name;
  final String shortDescription;
  final String category;
  final bool requiresHitl;
  final String securityLevel;
  final List<String> dependencies;
  final bool hasMcp;
  final bool hasPython;
  final bool hasNode;

  /// Formats a single token-efficient index line for Stage 1 system prompt injection.
  String toCompactIndexLine() {
    final hitlTag = requiresHitl ? ' [HITL]' : '';
    final desc = shortDescription.trim().isNotEmpty
        ? shortDescription.trim()
        : name;
    return '- `$slug` [$category]$hitlTag: $desc';
  }

  factory SkillOntologySummary.fromNode(
    OntologyNode node, {
    bool? requiresHitlOverride,
    List<String>? dependenciesOverride,
  }) {
    final meta = node.metadata;
    final rawSlug = (meta['slug'] as String?)?.trim();
    final slug = (rawSlug != null && rawSlug.isNotEmpty)
        ? rawSlug
        : node.canonicalKey.replaceFirst('skill:', '');
    final rawDeps = (meta['dependencies'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    return SkillOntologySummary(
      slug: slug,
      name: node.label,
      shortDescription: (meta['shortDescription'] as String?) ?? '',
      category: (meta['category'] as String?) ?? 'general',
      requiresHitl:
          requiresHitlOverride ?? (meta['requiresHitl'] as bool? ?? false),
      securityLevel: (meta['securityLevel'] as String?) ?? 'standard',
      dependencies: dependenciesOverride ?? rawDeps,
      hasMcp: meta['hasMcp'] as bool? ?? false,
      hasPython: meta['hasPython'] as bool? ?? false,
      hasNode: meta['hasNode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'shortDescription': shortDescription,
        'category': category,
        'requiresHitl': requiresHitl,
        'securityLevel': securityLevel,
        'dependencies': dependencies,
        'hasMcp': hasMcp,
        'hasPython': hasPython,
        'hasNode': hasNode,
      };
}
