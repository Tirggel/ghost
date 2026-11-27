// Ghost — Canonical Domain Taxonomy & Signal Extraction for Multi-Agent Routing.

/// Definition of a canonical competency domain used across Ontology, Skills, and Routing.
class DomainDefinition {
  const DomainDefinition({
    required this.key,
    required this.labelDe,
    required this.labelEn,
    required this.aliases,
    required this.skillCategories,
    required this.keywords,
  });

  final String key;
  final String labelDe;
  final String labelEn;
  final List<String> aliases;
  final List<String> skillCategories;
  final List<String> keywords;

  String labelForLocale(String languageCode) {
    return languageCode.toLowerCase().startsWith('de') ? labelDe : labelEn;
  }
}

/// Extracted domain & token signals from a Kanban task or user prompt.
class TaskRoutingSignals {
  const TaskRoutingSignals({
    required this.domainWeights,
    required this.tokens,
    required this.normalizedLabels,
    required this.combinedTextLower,
  });

  final Map<String, double> domainWeights;
  final Set<String> tokens;
  final Set<String> normalizedLabels;
  final String combinedTextLower;
}

/// Shared domain taxonomy for mapping between user/agent competency tags,
/// skill categories (`GEHOERT_ZU_DOMAIN`), system prompts, and task descriptions.
class AgentDomainTaxonomy {
  AgentDomainTaxonomy._();

  static const List<DomainDefinition> standardDomains = [
    DomainDefinition(
      key: 'coding',
      labelDe: 'Coding',
      labelEn: 'Coding',
      aliases: [
        'coding',
        'code',
        'development',
        'dev',
        'programming',
        'programmierung',
        'software',
        'engineering',
      ],
      skillCategories: ['development', 'coding'],
      keywords: [
        'code',
        'coding',
        'dart',
        'flutter',
        'python',
        'typescript',
        'javascript',
        'rust',
        'java',
        'sql',
        'api',
        'backend',
        'frontend',
        'refactor',
        'refactoring',
        'bug',
        'bugfix',
        'debug',
        'debugging',
        'unit test',
        'test',
        'tests',
        'implement',
        'implementiere',
        'entwickeln',
        'entwicklung',
        'programmier',
        'klasse',
        'funktion',
        'widget',
        'database',
        'datenbank',
        'algorithm',
      ],
    ),
    DomainDefinition(
      key: 'research',
      labelDe: 'Recherche',
      labelEn: 'Research',
      aliases: [
        'research',
        'recherche',
        'web',
        'search',
        'suche',
        'analysis',
        'analyse',
      ],
      skillCategories: ['web', 'research'],
      keywords: [
        'recherche',
        'recherchiere',
        'research',
        'suche',
        'web',
        'browser',
        'scrape',
        'news',
        'nachrichten',
        'wetter',
        'weather',
        'studie',
        'quellen',
        'sources',
        'vergleich',
        'compare',
        'benchmark',
        'markt',
        'market',
        'dokumentation',
        'documentation',
        'papers',
        'artikel',
        'zusammenfassung',
        'investigate',
      ],
    ),
    DomainDefinition(
      key: 'finance',
      labelDe: 'Finanzen',
      labelEn: 'Finance',
      aliases: [
        'finance',
        'finanzen',
        'accounting',
        'buchhaltung',
        'trading',
        'crypto',
      ],
      skillCategories: ['finance'],
      keywords: [
        'finanz',
        'finanzen',
        'finance',
        'budget',
        'rechnung',
        'rechnungen',
        'invoice',
        'steuer',
        'steuern',
        'tax',
        'crypto',
        'krypto',
        'binance',
        'wallet',
        'token',
        'swap',
        'trading',
        'aktien',
        'stocks',
        'portfolio',
        'zahlung',
        'payment',
        'kosten',
        'cost',
        'bilanz',
        'umsatz',
        'preis',
      ],
    ),
    DomainDefinition(
      key: 'communication',
      labelDe: 'Kommunikation',
      labelEn: 'Communication',
      aliases: [
        'communication',
        'kommunikation',
        'messaging',
        'email',
        'outreach',
      ],
      skillCategories: ['communication'],
      keywords: [
        'email',
        'mail',
        'gmail',
        'outlook',
        'kalender',
        'calendar',
        'termin',
        'meeting',
        'nachricht',
        'message',
        'slack',
        'telegram',
        'discord',
        'whatsapp',
        'brief',
        'antwort',
        'reply',
        'kommunikation',
        'communication',
        'einladung',
        'newsletter',
        'protokoll',
      ],
    ),
    DomainDefinition(
      key: 'system',
      labelDe: 'System',
      labelEn: 'System',
      aliases: [
        'system',
        'devops',
        'ops',
        'infra',
        'infrastructure',
        'sysadmin',
      ],
      skillCategories: ['system'],
      keywords: [
        'system',
        'devops',
        'docker',
        'kubernetes',
        'k8s',
        'git',
        'github',
        'bash',
        'shell',
        'terminal',
        'deploy',
        'deployment',
        'server',
        'linux',
        'ci/cd',
        'pipeline',
        'cron',
        'backup',
        'monitoring',
        'prozess',
        'netzwerk',
        'sysadmin',
        'config',
      ],
    ),
    DomainDefinition(
      key: 'security',
      labelDe: 'Sicherheit',
      labelEn: 'Security',
      aliases: [
        'security',
        'sicherheit',
        'secops',
        'compliance',
        'privacy',
        'datenschutz',
      ],
      skillCategories: ['security'],
      keywords: [
        'security',
        'sicherheit',
        'audit',
        'hitl',
        'vault',
        'berechtigung',
        'permission',
        'auth',
        'oauth',
        'token',
        'encrypt',
        'verschlüssel',
        'schwachstelle',
        'vulnerability',
        'cve',
        'compliance',
        'datenschutz',
        'gdpr',
        'dsgvo',
        'firewall',
      ],
    ),
    DomainDefinition(
      key: 'design',
      labelDe: 'Design',
      labelEn: 'Design',
      aliases: [
        'design',
        'ui',
        'ux',
        'ui/ux',
        'styling',
        'branding',
      ],
      skillCategories: ['design'],
      keywords: [
        'design',
        'ui',
        'ux',
        'layout',
        'css',
        'theme',
        'styling',
        'monolith',
        'mockup',
        'wireframe',
        'prototype',
        'farbe',
        'color',
        'typography',
        'typografie',
        'komponente',
        'figma',
        'responsive',
        'animation',
      ],
    ),
  ];

  static final Map<String, DomainDefinition> _byAlias = _buildAliasLookup();

  static Map<String, DomainDefinition> _buildAliasLookup() {
    final map = <String, DomainDefinition>{};
    for (final def in standardDomains) {
      map[def.key] = def;
      for (final alias in def.aliases) {
        map[normalizeRawKey(alias)] = def;
      }
      for (final cat in def.skillCategories) {
        map[normalizeRawKey(cat)] = def;
      }
      map[normalizeRawKey(def.labelDe)] = def;
      map[normalizeRawKey(def.labelEn)] = def;
    }
    return map;
  }

  /// Normalizes a raw competency/category/label into a stable snake_case slug.
  static String normalizeRawKey(String raw) {
    var s = raw.trim().toLowerCase();
    s = s
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  /// Resolves aliases and skill categories (e.g. `development` -> `coding`,
  /// `web` -> `research`, `Recherche` -> `research`) to a canonical domain key,
  /// or returns the normalized custom slug if it is a user-defined domain.
  static String canonicalDomainKey(String raw) {
    final norm = normalizeRawKey(raw);
    if (norm.isEmpty) return 'general';
    final def = _byAlias[norm];
    return def != null ? def.key : norm;
  }

  /// Returns a human-readable display label for a domain key or custom competency.
  static String displayLabel(String rawOrKey, {String languageCode = 'de'}) {
    final norm = normalizeRawKey(rawOrKey);
    final def = _byAlias[norm];
    if (def != null) {
      return def.labelForLocale(languageCode);
    }
    final trimmed = rawOrKey.trim();
    if (trimmed.isEmpty) return 'General';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  /// Checks whether two domain labels/keys refer to the same canonical domain.
  static bool areEquivalent(String a, String b) {
    return canonicalDomainKey(a) == canonicalDomainKey(b);
  }

  /// Returns preset display tags for UI editors.
  static List<String> presetLabels({String languageCode = 'de'}) {
    return standardDomains
        .map((d) => d.labelForLocale(languageCode))
        .toList();
  }

  /// Infers implicit competencies from an agent's name, system prompt, and notes.
  /// Returns canonical domain keys with confidence scores in `0.65..0.80`.
  static List<({String domainKey, String label, double confidence})>
      inferCompetenciesFromProfile({
    required String name,
    String systemPrompt = '',
    String cronMessage = '',
    String notes = '',
    String languageCode = 'de',
  }) {
    final text = '$name\n$systemPrompt\n$cronMessage\n$notes'.trim();
    if (text.isEmpty) return const [];

    final hitsByDomain = <String, int>{};
    for (final def in standardDomains) {
      var hits = 0;
      for (final kw in def.keywords) {
        if (_matchesKeyword(text, kw)) {
          hits++;
        }
      }
      // Also match domain labels/aliases directly
      for (final alias in def.aliases) {
        if (_matchesKeyword(text, alias)) {
          hits++;
        }
      }
      if (hits > 0) {
        hitsByDomain[def.key] = hits;
      }
    }

    final results = <({String domainKey, String label, double confidence})>[];
    for (final entry in hitsByDomain.entries) {
      final hits = entry.value;
      // 1 hit -> 0.65, 2 hits -> 0.72, 3+ hits -> 0.78
      final confidence = hits >= 3 ? 0.78 : (hits == 2 ? 0.72 : 0.65);
      results.add((
        domainKey: entry.key,
        label: displayLabel(entry.key, languageCode: languageCode),
        confidence: confidence,
      ));
    }
    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results;
  }

  /// Extracts weighted domain signals and tokens from a Kanban task.
  static TaskRoutingSignals extractTaskSignals({
    required String title,
    String description = '',
    List<String> labels = const [],
    Set<String> knownDomainKeys = const {},
  }) {
    final cleanTitle = title.trim();
    final cleanDesc = description.trim();
    final normalizedLabels = labels
        .map(canonicalDomainKey)
        .where((k) => k.isNotEmpty && k != 'general')
        .toSet();

    final rawWeights = <String, double>{};

    void scoreText(String text, double fieldWeight) {
      if (text.isEmpty) return;
      for (final def in standardDomains) {
        var matchedCount = 0;
        for (final kw in def.keywords) {
          if (_matchesKeyword(text, kw)) {
            matchedCount++;
          }
        }
        for (final alias in def.aliases) {
          if (_matchesKeyword(text, alias)) {
            matchedCount++;
          }
        }
        if (matchedCount > 0) {
          // Diminishing returns for multiple keywords in the same field
          final gain = fieldWeight * (1.0 + (matchedCount - 1).clamp(0, 3) * 0.25);
          rawWeights[def.key] = (rawWeights[def.key] ?? 0.0) + gain;
        }
      }

      // Also check arbitrary custom domain keys present in the ontology graph
      for (final domainKey in knownDomainKeys) {
        final canonical = canonicalDomainKey(domainKey);
        if (_byAlias.containsKey(canonical)) continue;
        final searchTerm = canonical.replaceAll('_', ' ');
        if (searchTerm.length >= 3 && _matchesKeyword(text, searchTerm)) {
          rawWeights[canonical] = (rawWeights[canonical] ?? 0.0) + fieldWeight;
        }
      }
    }

    // Labels carry highest explicit intent
    for (final label in labels) {
      final canonical = canonicalDomainKey(label);
      if (canonical.isNotEmpty && canonical != 'general') {
        rawWeights[canonical] = (rawWeights[canonical] ?? 0.0) + 2.5;
      }
      scoreText(label, 1.5);
    }

    scoreText(cleanTitle, 2.0);
    scoreText(cleanDesc, 1.0);

    // Normalize weights to (0, 1] relative to max domain weight
    final normalizedWeights = <String, double>{};
    if (rawWeights.isNotEmpty) {
      final maxWeight = rawWeights.values.reduce((a, b) => a > b ? a : b);
      for (final entry in rawWeights.entries) {
        normalizedWeights[entry.key] =
            maxWeight > 0 ? (entry.value / maxWeight).clamp(0.0, 1.0) : 0.0;
      }
    }

    final combined = '$cleanTitle $cleanDesc ${labels.join(' ')}'.toLowerCase();
    final tokens = RegExp(r'[\p{L}\p{N}_-]{3,}', unicode: true)
        .allMatches(combined)
        .map((m) => m.group(0)!)
        .toSet();

    return TaskRoutingSignals(
      domainWeights: normalizedWeights,
      tokens: tokens,
      normalizedLabels: normalizedLabels,
      combinedTextLower: combined,
    );
  }

  static bool _matchesKeyword(String text, String keyword) {
    final cleanKw = keyword.trim().toLowerCase();
    if (cleanKw.isEmpty) return false;
    final escaped = RegExp.escape(cleanKw);
    // Allow prefix match on German/English stems for longer keywords (>= 6 chars)
    final suffix = cleanKw.length >= 6 ? r'[\p{L}]*' : '';
    final pattern = RegExp(
      '(^|[^\\p{L}\\p{N}_])$escaped$suffix(\$|[^\\p{L}\\p{N}_])',
      caseSensitive: false,
      unicode: true,
    );
    return pattern.hasMatch(text);
  }
}
