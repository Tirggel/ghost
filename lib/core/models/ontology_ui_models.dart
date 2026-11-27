/// Pure JSON-serializable DTOs for the Ontology & Knowledge Graph UI.
///
/// Kept independent of ObjectBox so Flutter UI widgets and tests can run
/// without loading native ObjectBox binaries.

class OntologyStatsDto {
  const OntologyStatsDto({
    this.relations = 0,
    this.nodes = 0,
    this.edges = 0,
    this.skills = 0,
    this.linkedSkills = 0,
    this.personalEdges = 0,
    this.governanceEdges = 0,
  });

  factory OntologyStatsDto.fromJson(Map<String, dynamic> json) {
    return OntologyStatsDto(
      relations: (json['relations'] as num?)?.toInt() ?? 0,
      nodes: (json['nodes'] as num?)?.toInt() ?? 0,
      edges: (json['edges'] as num?)?.toInt() ?? 0,
      skills: (json['skills'] as num?)?.toInt() ?? 0,
      linkedSkills: (json['linkedSkills'] as num?)?.toInt() ?? 0,
      personalEdges: (json['personalEdges'] as num?)?.toInt() ?? 0,
      governanceEdges: (json['governanceEdges'] as num?)?.toInt() ?? 0,
    );
  }

  final int relations;
  final int nodes;
  final int edges;
  final int skills;
  final int linkedSkills;
  final int personalEdges;
  final int governanceEdges;
}

class OntologyTripleDto {
  const OntologyTripleDto({
    this.edgeId,
    required this.subject,
    required this.subjectKey,
    required this.subjectType,
    required this.predicate,
    required this.object,
    required this.objectKey,
    required this.objectType,
    this.confidence = 1.0,
    this.createdAt,
    this.isInferred = false,
    this.hopDepth = 1,
    this.pathChain = const [],
    this.isGovernance = false,
  });

  factory OntologyTripleDto.fromJson(Map<String, dynamic> json) {
    return OntologyTripleDto(
      edgeId: (json['edgeId'] as num?)?.toInt(),
      subject: json['subject'] as String? ?? '',
      subjectKey: json['subjectKey'] as String? ?? '',
      subjectType: json['subjectType'] as String? ?? 'Entity',
      predicate: json['predicate'] as String? ?? '',
      object: json['object'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      objectType: json['objectType'] as String? ?? 'Entity',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isInferred: json['isInferred'] as bool? ?? false,
      hopDepth: (json['hopDepth'] as num?)?.toInt() ?? 1,
      pathChain: (json['pathChain'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isGovernance: json['isGovernance'] as bool? ?? false,
    );
  }

  final int? edgeId;
  final String subject;
  final String subjectKey;
  final String subjectType;
  final String predicate;
  final String object;
  final String objectKey;
  final String objectType;
  final double confidence;
  final DateTime? createdAt;
  final bool isInferred;
  final int hopDepth;
  final List<String> pathChain;
  final bool isGovernance;
}

class OntologyNodeDto {
  const OntologyNodeDto({
    this.nodeId,
    required this.canonicalKey,
    required this.label,
    this.entityType = 'Entity',
    this.edgeCount = 0,
    this.isGovernance = false,
    this.updatedAt,
  });

  factory OntologyNodeDto.fromJson(Map<String, dynamic> json) {
    return OntologyNodeDto(
      nodeId: (json['nodeId'] as num?)?.toInt(),
      canonicalKey: json['canonicalKey'] as String? ?? '',
      label: json['label'] as String? ?? '',
      entityType: json['entityType'] as String? ?? 'Entity',
      edgeCount: (json['edgeCount'] as num?)?.toInt() ?? 0,
      isGovernance: json['isGovernance'] as bool? ?? false,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  final int? nodeId;
  final String canonicalKey;
  final String label;
  final String entityType;
  final int edgeCount;
  final bool isGovernance;
  final DateTime? updatedAt;
}

class OntologyRelationDto {
  const OntologyRelationDto({
    required this.predicate,
    this.domainType = 'Entity',
    this.rangeType = 'Entity',
    this.isFunctional = false,
    this.isTransitive = false,
  });

  factory OntologyRelationDto.fromJson(Map<String, dynamic> json) {
    return OntologyRelationDto(
      predicate: json['predicate'] as String? ?? '',
      domainType: json['domainType'] as String? ?? 'Entity',
      rangeType: json['rangeType'] as String? ?? 'Entity',
      isFunctional: json['isFunctional'] as bool? ?? false,
      isTransitive: json['isTransitive'] as bool? ?? false,
    );
  }

  final String predicate;
  final String domainType;
  final String rangeType;
  final bool isFunctional;
  final bool isTransitive;
}

class OntologyListResponseDto {
  const OntologyListResponseDto({
    this.stats = const OntologyStatsDto(),
    this.facts = const [],
    this.nodes = const [],
    this.relations = const [],
    this.totalFacts = 0,
  });

  factory OntologyListResponseDto.fromJson(Map<String, dynamic> json) {
    return OntologyListResponseDto(
      stats: json['stats'] is Map<String, dynamic>
          ? OntologyStatsDto.fromJson(json['stats'] as Map<String, dynamic>)
          : json['stats'] is Map
              ? OntologyStatsDto.fromJson(
                  Map<String, dynamic>.from(json['stats'] as Map),
                )
              : const OntologyStatsDto(),
      facts: (json['facts'] as List<dynamic>? ?? const [])
          .map(
            (e) => OntologyTripleDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      nodes: (json['nodes'] as List<dynamic>? ?? const [])
          .map(
            (e) => OntologyNodeDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      relations: (json['relations'] as List<dynamic>? ?? const [])
          .map(
            (e) => OntologyRelationDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      totalFacts: (json['totalFacts'] as num?)?.toInt() ?? 0,
    );
  }

  final OntologyStatsDto stats;
  final List<OntologyTripleDto> facts;
  final List<OntologyNodeDto> nodes;
  final List<OntologyRelationDto> relations;
  final int totalFacts;
}

class OntologyQueryResponseDto {
  const OntologyQueryResponseDto({
    required this.query,
    this.rootNodes = const [],
    this.directFacts = const [],
    this.inferredFacts = const [],
    this.promptPreview = '',
  });

  factory OntologyQueryResponseDto.fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'] is Map
        ? Map<String, dynamic>.from(json['result'] as Map)
        : json;
    return OntologyQueryResponseDto(
      query: rawResult['query'] as String? ?? '',
      rootNodes: (rawResult['rootNodes'] as List<dynamic>? ?? const [])
          .map(
            (e) => OntologyNodeDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      directFacts: (rawResult['directFacts'] as List<dynamic>? ?? const [])
          .map(
            (e) => OntologyTripleDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      inferredFacts: (rawResult['inferredFacts'] as List<dynamic>? ?? const [])
          .map(
            (e) => OntologyTripleDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      promptPreview: json['promptPreview'] as String? ?? '',
    );
  }

  final String query;
  final List<OntologyNodeDto> rootNodes;
  final List<OntologyTripleDto> directFacts;
  final List<OntologyTripleDto> inferredFacts;
  final String promptPreview;

  bool get isEmpty => directFacts.isEmpty && inferredFacts.isEmpty;
}
