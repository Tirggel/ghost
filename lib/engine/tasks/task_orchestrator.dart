// Ghost — Task Orchestrator (Phase 3 + Ontology Multi-Agent Routing).
// Handles dependencies, pipelines, ontology-driven agent routing, and task transitions.

import 'dart:async';
import 'dart:math' as math;
import 'package:logging/logging.dart';

import '../agent/manager.dart';
import '../agent/ontology/agent_domain_taxonomy.dart';
import '../agent/ontology/ontology_models.dart';
import 'task.dart';
import 'task_manager.dart';

final _log = Logger('Ghost.TaskOrchestrator');

/// Score breakdown for a single candidate agent evaluated during ontology routing.
class AgentRoutingCandidate {
  const AgentRoutingCandidate({
    required this.agentId,
    required this.agentName,
    required this.totalScore,
    required this.competencyScore,
    required this.skillScore,
    required this.nameScore,
    required this.loadPenalty,
    required this.activeTasks,
    required this.matchedCompetencies,
    required this.matchedSkills,
  });

  final String agentId;
  final String agentName;
  final double totalScore;
  final double competencyScore;
  final double skillScore;
  final double nameScore;
  final double loadPenalty;
  final int activeTasks;
  final List<String> matchedCompetencies;
  final List<String> matchedSkills;

  bool get isDefaultAgent => agentId == 'default-agent';

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'agentName': agentName,
        'totalScore': double.parse(totalScore.toStringAsFixed(2)),
        'competencyScore': double.parse(competencyScore.toStringAsFixed(2)),
        'skillScore': double.parse(skillScore.toStringAsFixed(2)),
        'nameScore': double.parse(nameScore.toStringAsFixed(2)),
        'loadPenalty': double.parse(loadPenalty.toStringAsFixed(2)),
        'activeTasks': activeTasks,
        'matchedCompetencies': matchedCompetencies,
        'matchedSkills': matchedSkills,
      };
}

/// Transparent decision produced by ontology-based multi-agent routing.
class AgentRoutingDecision {
  const AgentRoutingDecision({
    required this.selectedAgentId,
    required this.selectedAgentName,
    required this.fallbackUsed,
    required this.score,
    required this.reason,
    required this.matchedCompetencies,
    required this.matchedSkills,
    required this.candidates,
    required this.decidedAt,
  });

  final String selectedAgentId;
  final String selectedAgentName;
  final bool fallbackUsed;
  final double score;
  final String reason;
  final List<String> matchedCompetencies;
  final List<String> matchedSkills;
  final List<AgentRoutingCandidate> candidates;
  final DateTime decidedAt;

  Map<String, dynamic> toMetadataJson() => {
        'selectedAgentId': selectedAgentId,
        'selectedAgentName': selectedAgentName,
        'fallbackUsed': fallbackUsed,
        'score': double.parse(score.toStringAsFixed(2)),
        'reason': reason,
        'matchedCompetencies': matchedCompetencies,
        'matchedSkills': matchedSkills,
        'decidedAt': decidedAt.toIso8601String(),
        'candidates': candidates.take(5).map((c) => c.toJson()).toList(),
      };
}

class TaskOrchestrator {
  TaskOrchestrator({
    required this.taskManager,
    required this.agentManager,
  });

  final TaskManager taskManager;
  final AgentManager agentManager;
  StreamSubscription<TaskEvent>? _subscription;
  final Map<String, Future<AgentRoutingDecision?>> _routingInFlight = {};
  bool _disposed = false;

  static const double minSpecialistScore = 15.0;
  static const double minMarginOverDefault = 8.0;

  /// Initialize the orchestrator by listening to task events.
  void initialize() {
    _disposed = false;
    _subscription = taskManager.onTaskChanged.listen(_handleTaskEvent);
    _log.info('TaskOrchestrator initialized');
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
  }

  /// Evaluates ontology-driven routing for an ad-hoc request (e.g. an Automation).
  Future<AgentRoutingDecision> evaluateRoutingForRequest({
    required String title,
    required String description,
    List<String> labels = const [],
    List<String> excludeAgentIds = const [],
  }) {
    final syntheticTask = KanbanTask(
      id: '__routing_eval__',
      title: title,
      description: description,
      labels: labels,
    );
    return evaluateAgentRouting(
      syntheticTask,
      excludeAgentIds: excludeAgentIds,
    );
  }

  /// Evaluates all enabled agents via the Ontology Knowledge Graph
  /// (`HAT_KOMPETENZ`, `DARF_NUTZEN`, `GEHOERT_ZU_DOMAIN`) and current workload.
  Future<AgentRoutingDecision> evaluateAgentRouting(
    KanbanTask task, {
    List<String> excludeAgentIds = const [],
  }) async {
    final excluded = excludeAgentIds.toSet();
    final config = agentManager.config;
    final ontology = agentManager.ontologyStoreService;
    final lang = config.user.language;

    // 1. Collect candidate agent definitions from live config
    final candidatesDef = <({
      String id,
      String name,
      List<String> explicitCompetencies,
      String prompt,
      String cronMessage,
      String notes,
      List<String> disabledSkills,
    })>[
      if (!excluded.contains('default-agent'))
        (
          id: 'default-agent',
          name: config.identity.name.trim().isNotEmpty
              ? config.identity.name.trim()
              : 'Ghost',
          explicitCompetencies: config.agent.competencies,
          prompt: '',
          cronMessage: '',
          notes: '${config.identity.vibe} ${config.identity.notes}'.trim(),
          disabledSkills: config.agent.disabledSkills,
        ),
      for (final ca in config.customAgents)
        if (ca.enabled && !excluded.contains(ca.id))
          (
            id: ca.id,
            name: ca.name.trim().isNotEmpty ? ca.name.trim() : ca.id,
            explicitCompetencies: ca.competencies,
            prompt: ca.systemPrompt,
            cronMessage: ca.cronMessage,
            notes: '',
            disabledSkills: ca.disabledSkills,
          ),
    ];

    if (candidatesDef.isEmpty) {
      final fallbackName = config.identity.name.trim().isNotEmpty
          ? config.identity.name.trim()
          : 'Ghost';
      return AgentRoutingDecision(
        selectedAgentId: 'default-agent',
        selectedAgentName: fallbackName,
        fallbackUsed: true,
        score: 0.0,
        reason: 'Standard-Fallback – kein aktiver Kandidat verfügbar',
        matchedCompetencies: const [],
        matchedSkills: const [],
        candidates: const [],
        decidedAt: DateTime.now(),
      );
    }

    // 2. Load ontology capability profiles (or synthesize from config if not initialized)
    final profilesById = <String, AgentCapabilityProfile>{};
    final knownDomains = <String>{};
    final allSkillsBySlug = <String, SkillOntologySummary>{};

    if (ontology.isInitialized) {
      for (final profile in ontology.getAllAgentCapabilityProfiles()) {
        profilesById[profile.agentId] = profile;
        for (final s in profile.allowedSkills) {
          allSkillsBySlug[s.slug] = s;
        }
      }
      knownDomains.addAll(ontology.getKnownDomainKeys());
    }

    for (final def in candidatesDef) {
      if (!profilesById.containsKey(def.id)) {
        final synthesized = <AgentCompetency>[];
        final seenDomains = <String>{};
        for (final raw in def.explicitCompetencies) {
          final key = AgentDomainTaxonomy.canonicalDomainKey(raw);
          if (key == 'general' || !seenDomains.add(key)) continue;
          synthesized.add(
            AgentCompetency(
              domainKey: key,
              label: AgentDomainTaxonomy.displayLabel(raw, languageCode: lang),
              confidence: 1.0,
              source: 'explicit',
              isExplicit: true,
            ),
          );
        }
        for (final inf in AgentDomainTaxonomy.inferCompetenciesFromProfile(
          name: def.name,
          systemPrompt: def.prompt,
          cronMessage: def.cronMessage,
          notes: def.notes,
          languageCode: lang,
        )) {
          if (!seenDomains.add(inf.domainKey)) continue;
          synthesized.add(
            AgentCompetency(
              domainKey: inf.domainKey,
              label: inf.label,
              confidence: inf.confidence,
              source: 'prompt',
              isExplicit: false,
            ),
          );
        }
        profilesById[def.id] = AgentCapabilityProfile(
          agentId: def.id,
          agentName: def.name,
          competencies: synthesized,
          allowedSkills: const [],
          skillDomainsBySlug: const {},
        );
      }
      for (final comp in profilesById[def.id]!.competencies) {
        knownDomains.add(comp.domainKey);
      }
    }

    // 3. Extract signals from the Kanban task
    final signals = AgentDomainTaxonomy.extractTaskSignals(
      title: task.title,
      description: task.description,
      labels: task.labels,
      knownDomainKeys: knownDomains,
    );

    // Identify skills directly referenced by the task
    final taskMatchedSkillSlugs = <String>{};
    for (final skill in allSkillsBySlug.values) {
      if (_taskMatchesSkill(signals, skill)) {
        taskMatchedSkillSlugs.add(skill.slug);
      }
    }

    // Compute active in-progress task counts per agent
    final activeCounts = <String, int>{};
    for (final t in taskManager.tasks) {
      if (t.id == task.id) continue;
      if (t.status == TaskStatus.inProgress && t.assignedAgentId != null) {
        activeCounts[t.assignedAgentId!] =
            (activeCounts[t.assignedAgentId!] ?? 0) + 1;
      }
    }

    final maxAllowedAcrossAgents = profilesById.values
        .map((p) => p.allowedSkills.length)
        .fold<int>(0, (prev, len) => len > prev ? len : prev);
    final totalSkillDenominator =
        math.max(allSkillsBySlug.length, math.max(maxAllowedAcrossAgents, 1));

    // 4. Score every candidate
    final scored = <AgentRoutingCandidate>[];
    for (final def in candidatesDef) {
      final profile = profilesById[def.id]!;
      final compByDomain = <String, AgentCompetency>{
        for (final c in profile.competencies) c.domainKey: c,
      };

      // A) Competency match (0..55)
      double compScore = 0.0;
      final matchedCompLabels = <String>[];
      if (signals.domainWeights.isNotEmpty) {
        double totalWeight = 0.0;
        double weightedMatch = 0.0;
        for (final entry in signals.domainWeights.entries) {
          totalWeight += entry.value;
          final comp = compByDomain[entry.key];
          if (comp != null) {
            final mult = comp.isExplicit
                ? 1.0
                : (comp.source == 'prompt' ? 0.65 : 0.35);
            weightedMatch += entry.value * mult;
            final displayLabel = AgentDomainTaxonomy.displayLabel(
              comp.domainKey,
              languageCode: lang,
            );
            if (!matchedCompLabels.contains(displayLabel)) {
              matchedCompLabels.add(displayLabel);
            }
          }
        }
        if (totalWeight > 0) {
          compScore = 45.0 * (weightedMatch / totalWeight);
        }
      }

      // Bonus if an explicit task label matches an explicit agent competency
      final hasExplicitLabelHit = signals.normalizedLabels.any(
        (lbl) => compByDomain[lbl]?.isExplicit == true,
      );
      if (hasExplicitLabelHit) {
        compScore = math.min(55.0, compScore + 10.0);
      }

      // B) Skill match via DARF_NUTZEN & GEHOERT_ZU_DOMAIN (0..30), weighted by specificity
      final allowedCount = profile.allowedSkills.length;
      final specificity =
          0.4 + 0.6 * (1.0 - (allowedCount / totalSkillDenominator).clamp(0.0, 1.0));

      final directMatchedSkills = <String>[];
      final domainMatchedSkills = <String>[];

      for (final skill in profile.allowedSkills) {
        if (taskMatchedSkillSlugs.contains(skill.slug)) {
          directMatchedSkills.add(skill.name);
        } else {
          final skillDom = profile.skillDomainsBySlug[skill.slug] ??
              AgentDomainTaxonomy.canonicalDomainKey(skill.category);
          if (signals.domainWeights.containsKey(skillDom)) {
            domainMatchedSkills.add(skill.name);
          }
        }
      }

      double directSkillPts = 0.0;
      if (directMatchedSkills.isNotEmpty) {
        directSkillPts =
            (directMatchedSkills.length == 1 ? 15.0 : 22.0) * specificity;
      }
      double domainSkillPts = 0.0;
      if (domainMatchedSkills.isNotEmpty) {
        domainSkillPts =
            math.min(8.0, domainMatchedSkills.length * 4.0) * specificity;
      }
      final skillScore = math.min(30.0, directSkillPts + domainSkillPts);

      // C) Direct agent name mention (0..10)
      double nameScore = 0.0;
      if (def.name.length >= 3 && _containsWholeWord(signals.combinedTextLower, def.name.toLowerCase())) {
        nameScore = 10.0;
      }

      // D) Active workload penalty (0..15)
      final activeCount = activeCounts[def.id] ?? 0;
      final loadPenalty = (activeCount * 5.0).clamp(0.0, 15.0);

      final totalScore =
          (compScore + skillScore + nameScore - loadPenalty).clamp(0.0, 100.0);

      final combinedMatchedSkills = <String>[
        ...directMatchedSkills,
        ...domainMatchedSkills.where((s) => !directMatchedSkills.contains(s)),
      ];

      scored.add(
        AgentRoutingCandidate(
          agentId: def.id,
          agentName: def.name,
          totalScore: totalScore,
          competencyScore: compScore,
          skillScore: skillScore,
          nameScore: nameScore,
          loadPenalty: loadPenalty,
          activeTasks: activeCount,
          matchedCompetencies: matchedCompLabels,
          matchedSkills: combinedMatchedSkills,
        ),
      );
    }

    scored.sort((a, b) {
      final scoreCmp = b.totalScore.compareTo(a.totalScore);
      if (scoreCmp != 0) return scoreCmp;
      final loadCmp = a.activeTasks.compareTo(b.activeTasks);
      if (loadCmp != 0) return loadCmp;
      final compCmp = b.competencyScore.compareTo(a.competencyScore);
      if (compCmp != 0) return compCmp;
      return a.agentId.compareTo(b.agentId);
    });

    final defaultCand = scored.where((c) => c.isDefaultAgent).firstOrNull;
    final bestCustom = scored.where((c) => !c.isDefaultAgent).firstOrNull;

    AgentRoutingCandidate selected;
    bool fallbackUsed;

    if (bestCustom != null &&
        bestCustom.totalScore >= minSpecialistScore &&
        (defaultCand == null ||
            bestCustom.totalScore - defaultCand.totalScore >=
                minMarginOverDefault)) {
      selected = bestCustom;
      fallbackUsed = false;
    } else if (defaultCand != null) {
      selected = defaultCand;
      fallbackUsed = true;
    } else {
      selected = scored.first;
      fallbackUsed = selected.totalScore < minSpecialistScore;
    }

    final reason = _buildRoutingReason(selected, fallbackUsed: fallbackUsed);
    return AgentRoutingDecision(
      selectedAgentId: selected.agentId,
      selectedAgentName: selected.agentName,
      fallbackUsed: fallbackUsed,
      score: selected.totalScore,
      reason: reason,
      matchedCompetencies: selected.matchedCompetencies,
      matchedSkills: selected.matchedSkills,
      candidates: scored,
      decidedAt: DateTime.now(),
    );
  }

  /// Suggest the best agent ID for a task based on the ontology capability graph.
  Future<String?> suggestAgent(KanbanTask task) async {
    final decision = await evaluateAgentRouting(task);
    return decision.selectedAgentId;
  }

  /// Routes a Kanban task to the best agent via ontology and documents the
  /// decision in `task.metadata['routing']` plus a transparent task comment.
  Future<AgentRoutingDecision?> routeTask(
    String taskId, {
    bool force = false,
    List<String> excludeAgentIds = const [],
  }) async {
    if (_disposed) return null;
    final task = taskManager.getTask(taskId);
    if (task == null) return null;

    if (!force && !task.isAutoRoutingRequested) {
      return null;
    }

    if (!force &&
        task.status != TaskStatus.backlog &&
        task.status != TaskStatus.inProgress) {
      return null;
    }

    // Idempotency: if already auto-routed to a concrete agent and not forced, skip.
    if (!force &&
        task.assignedAgentId != null &&
        task.assignedAgentId != KanbanTask.autoAgentId &&
        task.routingInfo != null) {
      return null;
    }

    final existingInFlight = _routingInFlight[taskId];
    if (existingInFlight != null) {
      return existingInFlight;
    }

    final future = _performRouteTask(
      taskId,
      task,
      force: force,
      excludeAgentIds: excludeAgentIds,
    );
    _routingInFlight[taskId] = future;
    try {
      return await future;
    } finally {
      if (identical(_routingInFlight[taskId], future)) {
        _routingInFlight.remove(taskId);
      }
    }
  }

  Future<AgentRoutingDecision?> _performRouteTask(
    String taskId,
    KanbanTask task, {
    required bool force,
    required List<String> excludeAgentIds,
  }) async {
    final decision = await evaluateAgentRouting(
      task,
      excludeAgentIds: excludeAgentIds,
    );
    if (_disposed) return decision;

    final current = taskManager.getTask(taskId);
    if (current == null) return decision;
    if (!force &&
        current.status != TaskStatus.backlog &&
        current.status != TaskStatus.inProgress) {
      return null;
    }

    final nextMetadata = Map<String, dynamic>.from(current.metadata)
      ..['routing'] = decision.toMetadataJson();

    final updated = current.copyWith(
      assignedAgentId: decision.selectedAgentId,
      assignedAgentName: decision.selectedAgentName,
      metadata: nextMetadata,
    );
    await taskManager.updateTask(updated);

    if (_disposed) return decision;

    final commentText =
        '🧭 Auto-Routed zu ${decision.selectedAgentName} (${decision.reason})';
    await taskManager.addComment(
      taskId,
      authorId: 'system',
      authorName: 'Ghost Orchestrator',
      content: commentText,
    );

    _log.info(
      'Routed task $taskId ("${current.title}") -> ${decision.selectedAgentName} (${decision.selectedAgentId}), score=${decision.score.toStringAsFixed(1)}',
    );
    return decision;
  }

  String _buildRoutingReason(
    AgentRoutingCandidate selected, {
    required bool fallbackUsed,
  }) {
    if (fallbackUsed) {
      return 'Standard-Fallback – kein Spezialist signifikant besser';
    }
    final parts = <String>[
      ...selected.matchedCompetencies.take(2),
      ...selected.matchedSkills.take(2).map((s) => '$s-Skill'),
    ];
    if (selected.nameScore > 0 && parts.isEmpty) {
      parts.add('Direkte Nennung');
    }
    if (parts.isEmpty) {
      return 'Score: ${selected.totalScore.toStringAsFixed(0)}';
    }
    return 'Match: ${parts.join(', ')}';
  }

  bool _taskMatchesSkill(TaskRoutingSignals signals, SkillOntologySummary skill) {
    final slugLower = skill.slug.toLowerCase();
    final slugWords = slugLower.replaceAll(RegExp(r'[-_]+'), ' ');
    final nameLower = skill.name.toLowerCase();

    if (_containsWholeWord(signals.combinedTextLower, slugLower) ||
        (slugWords != slugLower &&
            _containsWholeWord(signals.combinedTextLower, slugWords)) ||
        (nameLower.length >= 3 &&
            _containsWholeWord(signals.combinedTextLower, nameLower))) {
      return true;
    }

    // Match significant keywords from skill shortDescription (>= 5 chars)
    final descTokens = RegExp(r'[\p{L}\p{N}_-]{5,}', unicode: true)
        .allMatches(skill.shortDescription.toLowerCase())
        .map((m) => m.group(0)!)
        .toSet();
    var descHits = 0;
    for (final tok in descTokens) {
      if (signals.tokens.contains(tok)) {
        descHits++;
        if (descHits >= 2) return true;
      }
    }
    return false;
  }

  bool _containsWholeWord(String text, String needle) {
    if (needle.trim().isEmpty) return false;
    final escaped = RegExp.escape(needle.trim());
    final pattern = RegExp(
      '(^|[^\\p{L}\\p{N}_-])$escaped(\$|[^\\p{L}\\p{N}_-])',
      caseSensitive: false,
      unicode: true,
    );
    return pattern.hasMatch(text);
  }

  void _handleTaskEvent(TaskEvent event) {
    if (_disposed) return;
    final task = event.task;
    if (task == null) return;

    // 1. Auto-route newly created tasks requesting ontology routing or immediate start
    if (event.type == TaskEventType.created) {
      if (task.assignedAgentId == KanbanTask.autoAgentId ||
          (task.status == TaskStatus.inProgress && task.assignedAgentId == null)) {
        unawaited(routeTask(task.id));
      }
      return;
    }

    // 2. Auto-route tasks moved from Backlog -> In Progress ("To Do") without explicit agent
    if (event.type == TaskEventType.moved &&
        event.oldStatus == TaskStatus.backlog &&
        event.newStatus == TaskStatus.inProgress &&
        task.isAutoRoutingRequested) {
      unawaited(routeTask(task.id));
    }

    // 3. When a task moves to 'done', check for dependents.
    if (event.type == TaskEventType.updated || event.type == TaskEventType.moved) {
      if (task.status == TaskStatus.done) {
        _log.info('Task ${task.id} is DONE. Checking for dependents...');
        unawaited(_processDependents(task.id));
      }
    }
  }

  /// Check all tasks that depend on the completed task.
  Future<void> _processDependents(String completedTaskId) async {
    if (_disposed) return;
    final allTasks = taskManager.tasks;
    final dependents =
        allTasks.where((t) => t.dependsOnIds.contains(completedTaskId)).toList();

    for (final dependent in dependents) {
      if (_disposed) return;
      _log.info('Checking dependent task: ${dependent.title} (${dependent.id})');

      // Check if ALL dependencies are met
      bool allMet = true;
      for (final depId in dependent.dependsOnIds) {
        final depTask = taskManager.getTask(depId);
        if (depTask == null || depTask.status != TaskStatus.done) {
          allMet = false;
          _log.info('Dependency $depId not met yet for ${dependent.id}');
          break;
        }
      }

      if (allMet) {
        _log.info(
          'All dependencies met for ${dependent.id}. Auto-starting or moving to backlog.',
        );

        await taskManager.addComment(
          dependent.id,
          authorId: 'system',
          authorName: 'Ghost Orchestrator',
          content: 'All dependencies met. Task is now ready for execution.',
        );

        var currentDependent = taskManager.getTask(dependent.id) ?? dependent;
        if (currentDependent.isAutoRoutingRequested) {
          await routeTask(currentDependent.id);
          currentDependent = taskManager.getTask(dependent.id) ?? currentDependent;
        }

        // If it's assigned (explicitly or via ontology), auto-start execution
        if (currentDependent.assignedAgentId != null &&
            currentDependent.assignedAgentId != KanbanTask.autoAgentId &&
            currentDependent.status == TaskStatus.backlog) {
          _log.info(
            'Auto-starting task ${currentDependent.id} with agent ${currentDependent.assignedAgentId}.',
          );
          await taskManager.moveTask(currentDependent.id, TaskStatus.inProgress);
          unawaited(_executeTaskWithAgent(currentDependent));
        }
      }
    }
  }

  /// Autonomously executes a Kanban task using its assigned agent.
  Future<void> executeTask(KanbanTask task) => _executeTaskWithAgent(task);

  Future<void> _executeTaskWithAgent(KanbanTask task) async {
    final agentId = task.assignedAgentId;
    if (agentId == null || agentId == KanbanTask.autoAgentId) return;

    try {
      final agent = agentManager.getAgent(agentId);

      final sessionId = task.sessionId ?? 'task_${task.id}';
      if (task.sessionId == null) {
        final updated = task.copyWith(sessionId: sessionId);
        await taskManager.updateTask(updated);
      }

      _log.info(
        'Orchestrator starting autonomous execution of "${task.title}" with agent $agentId in session $sessionId',
      );

      await taskManager.addComment(
        task.id,
        authorId: 'system',
        authorName: 'Ghost Orchestrator',
        content: '🤖 Agent "${agent.name}" führt die Aufgabe jetzt autonom aus...',
      );

      final goalPrompt = '/goal ${task.title}\n\n${task.description}';

      if (agentManager.sessionManager.getSession(sessionId) == null) {
        agentManager.sessionManager.createSession(
          id: sessionId,
          channelType: 'kanban',
          peerId: agentId,
        );
      }

      await agentManager.sessionManager.addMessage(
        sessionId: sessionId,
        role: 'user',
        content: goalPrompt,
      );

      await agent.processMessage(
        sessionId: sessionId,
        content: goalPrompt,
      );

      await taskManager.moveTask(task.id, TaskStatus.done);
      await taskManager.addComment(
        task.id,
        authorId: 'system',
        authorName: 'Ghost Orchestrator',
        content: '✅ Aufgabe erfolgreich abgeschlossen.',
      );
      _log.info('Task ${task.id} successfully completed by agent $agentId.');
    } catch (e) {
      _log.severe('Error executing task ${task.id} with agent $agentId: $e');
      await taskManager.moveTask(task.id, TaskStatus.review);
      await taskManager.addComment(
        task.id,
        authorId: 'system',
        authorName: 'Ghost Orchestrator',
        content: '⚠️ Ausführung fehlgeschlagen: $e',
      );
    }
  }

  /// Check whether adding dependencies to a task would create a circular dependency cycle.
  bool wouldCreateCycle(String taskId, List<String> newDependsOnIds) {
    final visited = <String>{};

    bool hasPath(String current, String target) {
      if (current == target) return true;
      if (!visited.add(current)) return false;
      final t = taskManager.getTask(current);
      if (t == null) return false;
      for (final dep in t.dependsOnIds) {
        if (hasPath(dep, target)) return true;
      }
      return false;
    }

    for (final depId in newDependsOnIds) {
      if (hasPath(depId, taskId)) {
        return true;
      }
    }
    return false;
  }

  /// Create a pipeline of tasks.
  /// Each task in the list depends on the previous one.
  Future<List<KanbanTask>> createPipeline({
    required List<String> titles,
    String? assignedAgentId,
    String? assignedAgentName,
  }) async {
    final createdTasks = <KanbanTask>[];
    String? lastTaskId;

    for (final title in titles) {
      final task = await taskManager.createTask(
        title: title,
        assignedAgentId: assignedAgentId,
        assignedAgentName: assignedAgentName,
      );

      if (lastTaskId != null) {
        final updated = task.copyWith(dependsOnIds: [lastTaskId]);
        await taskManager.updateTask(updated);
        createdTasks.add(updated);
      } else {
        createdTasks.add(task);
      }

      lastTaskId = task.id;
    }

    return createdTasks;
  }
}
