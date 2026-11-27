// Ghost — Native Ontology / Knowledge Graph Tools.

import '../agent/ontology/ontology_store_service.dart';
import 'registry.dart';

/// Registers all Knowledge Graph / Ontology tools into a [ToolRegistry].
class OntologyTools {
  static void registerAll(
    ToolRegistry registry,
    OntologyStoreService ontology,
  ) {
    registry.register(OntologyAssertTool(ontology));
    registry.register(OntologyQueryTool(ontology));
  }
}

/// Tool allowing the agent to store or update structured Knowledge Graph triples.
class OntologyAssertTool extends Tool {
  OntologyAssertTool(this.ontology);
  final OntologyStoreService ontology;

  @override
  String get name => 'ghost_ontology_assert';

  @override
  String get label => 'Knowledge Graph Assert';

  @override
  String get description =>
      'Store or update a structured factual triple (subject -> predicate -> object) '
      'in the Knowledge Graph. Functional predicates (e.g. WOHNT_IN, HEISST, '
      'ARBEITET_BEI, LIEGT_IN, HAT_BERUF) automatically overwrite prior values for the '
      'same subject, while non-functional predicates (e.g. MAG, ARBEITET_AN, BENUTZT) '
      'allow multiple values.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'subject': {
            'type': 'string',
            'description':
                'The subject entity label or canonical key (e.g. "Peter", "Zürich", "user:primary").',
          },
          'subject_type': {
            'type': 'string',
            'description':
                'Optional semantic type of the subject (e.g. "Person", "Place", "Project", "Organization", "Entity").',
          },
          'predicate': {
            'type': 'string',
            'description':
                'Relation predicate in UPPER_SNAKE_CASE (e.g. "WOHNT_IN", "LIEGT_IN", "ARBEITET_AN", "MAG").',
          },
          'object': {
            'type': 'string',
            'description':
                'The object entity label (e.g. "Zürich", "Schweiz", "Ghost").',
          },
          'object_type': {
            'type': 'string',
            'description':
                'Optional semantic type of the object (e.g. "Place", "Project", "Technology", "Text", "Entity").',
          },
          'confidence': {
            'type': 'number',
            'description': 'Optional confidence score between 0.0 and 1.0 (default 1.0).',
          },
        },
        'required': ['subject', 'predicate', 'object'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      '${input['subject']} --[${input['predicate']}]--> ${input['object']}';

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    if (!ontology.isInitialized) {
      return const ToolResult.error(
        'Ontology store is not initialized.',
      );
    }

    final subject = input['subject']?.toString().trim() ?? '';
    final predicate = input['predicate']?.toString().trim() ?? '';
    final object = input['object']?.toString().trim() ?? '';
    final subjectType = input['subject_type']?.toString().trim() ?? 'Entity';
    final objectType = input['object_type']?.toString().trim() ?? 'Entity';
    final confidence = (input['confidence'] as num?)?.toDouble() ?? 1.0;

    if (subject.isEmpty || predicate.isEmpty || object.isEmpty) {
      return const ToolResult.error(
        'Parameters "subject", "predicate", and "object" are required and must be non-empty.',
      );
    }

    final lowerSubj = subject.toLowerCase();
    final isPrimaryUser = lowerSubj == 'user:primary' ||
        lowerSubj == 'user' ||
        lowerSubj == 'ich' ||
        lowerSubj == 'me';

    try {
      final result = await ontology.assertFact(
        subjectLabel: isPrimaryUser && lowerSubj == 'user:primary' ? 'User' : subject,
        subjectType: isPrimaryUser ? 'Person' : subjectType,
        subjectKey: isPrimaryUser ? OntologyStoreService.primaryUserKey : null,
        predicate: predicate,
        objectLabel: object,
        objectType: objectType,
        confidence: confidence,
      );

      final actionNote = result.replacedCount > 0
          ? 'Updated functional relation (replaced ${result.replacedCount} previous edge(s)).'
          : (result.wasDuplicate
              ? 'Updated existing triple timestamp/confidence.'
              : 'Stored new Knowledge Graph triple.');

      return ToolResult(
        output:
            '$actionNote\n'
            'Triple: ${result.subject.label} (${result.subject.canonicalKey}) '
            '--[${result.predicate}]--> '
            '${result.object.label} (${result.object.canonicalKey})',
        metadata: result.toJson(),
      );
    } catch (e) {
      return ToolResult.error('Error asserting ontology fact: $e');
    }
  }
}

/// Tool allowing the agent to query direct and multi-hop inferred facts from the Knowledge Graph.
class OntologyQueryTool extends Tool {
  OntologyQueryTool(this.ontology);
  final OntologyStoreService ontology;

  @override
  String get name => 'ghost_ontology_query';

  @override
  String get label => 'Knowledge Graph Query';

  @override
  String get description =>
      'Query structured Knowledge Graph facts for an entity with recursive multi-hop '
      'traversal (e.g. resolving Peter -> Zürich -> Schweiz).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'entity': {
            'type': 'string',
            'description':
                'Entity label or canonical key to look up (e.g. "Peter", "Zürich", "user:primary").',
          },
          'max_depth': {
            'type': 'integer',
            'description': 'Multi-hop traversal depth from 1 to 4 (default 2).',
          },
          'include_incoming': {
            'type': 'boolean',
            'description': 'Include 1-hop incoming relations pointing to this entity (default true).',
          },
        },
        'required': ['entity'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Querying Knowledge Graph for "${input['entity']}"...';

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    if (!ontology.isInitialized) {
      return const ToolResult.error(
        'Ontology store is not initialized.',
      );
    }

    final entity = input['entity']?.toString().trim() ?? '';
    if (entity.isEmpty) {
      return const ToolResult.error('Parameter "entity" is required.');
    }

    final maxDepth = (input['max_depth'] as num?)?.toInt() ?? 2;
    final includeIncoming = input['include_incoming'] as bool? ?? true;

    try {
      final result = await ontology.queryFactsForEntity(
        entity,
        maxDepth: maxDepth,
        includeIncoming: includeIncoming,
      );

      if (result.isEmpty) {
        return ToolResult(
          output: 'No structured facts found for "$entity" in the Knowledge Graph.',
          metadata: result.toJson(),
        );
      }

      final buffer = StringBuffer();
      buffer.writeln(
        'Knowledge Graph results for "${result.rootNodes.map((n) => n.label).join(', ')}":',
      );
      if (result.directFacts.isNotEmpty) {
        buffer.writeln('\nDirect facts:');
        for (final fact in result.directFacts) {
          buffer.writeln(
            '- ${fact.subject.label} --[${fact.predicate}]--> ${fact.object.label} '
            '(confidence: ${fact.confidence.toStringAsFixed(2)})',
          );
        }
      }
      if (result.inferredFacts.isNotEmpty) {
        buffer.writeln('\nMulti-hop / inferred facts:');
        for (final fact in result.inferredFacts) {
          final via = fact.pathChain.isNotEmpty
              ? ' [via: ${fact.pathChain.join(' -> ')}]'
              : '';
          buffer.writeln(
            '- ${fact.subject.label} --[${fact.predicate}]--> ${fact.object.label}$via',
          );
        }
      }

      return ToolResult(
        output: buffer.toString().trim(),
        metadata: result.toJson(),
      );
    } catch (e) {
      return ToolResult.error('Error querying ontology: $e');
    }
  }
}
