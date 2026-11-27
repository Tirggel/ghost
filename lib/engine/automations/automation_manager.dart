// Ghost — Automation Execution, Scheduling & AI Drafting Engine.
// Pure Dart (no Flutter/dart:ui imports).

import 'dart:async';
import 'dart:convert';

import 'package:cron/cron.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../agent/agent.dart';
import '../agent/manager.dart';
import '../models/message.dart';
import '../sessions/manager.dart';
import '../sessions/session.dart';
import '../tasks/task_orchestrator.dart';
import 'automation_models.dart';
import 'automation_store.dart';
import 'cron_utils.dart';

final _log = Logger('Ghost.AutomationManager');
const _uuid = Uuid();

/// Manages Ghost Automations: persistence, multi-trigger cron scheduling,
/// ontology-driven agent routing, run history, and AI prompt drafting.
class AutomationManager {
  AutomationManager({
    required this.store,
    required this.agentManager,
    required this.sessionManager,
    this.orchestrator,
    this.onChanged,
    this.onRunUpdated,
    this.onSessionDeleted,
  });

  final AutomationStore store;
  final AgentManager agentManager;
  final SessionManager sessionManager;
  final TaskOrchestrator? orchestrator;

  final void Function(String? automationId, String action)? onChanged;
  final void Function(String automationId, AutomationRun run)? onRunUpdated;
  final void Function(String sessionId)? onSessionDeleted;

  final Cron _cron = Cron();
  final Map<String, Automation> _automations = {};
  final Map<String, List<ScheduledTask>> _scheduledTasks = {};
  final Set<String> _activeRunIds = {};
  bool _initialized = false;

  List<Automation> get automations {
    final list = _automations.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Automation? getAutomation(String id) => _automations[id];

  bool isRunning(String automationId) => _activeRunIds.contains(automationId);

  /// Initialize store, clean up interrupted runs, and schedule enabled jobs.
  Future<void> initialize() async {
    await store.initialize();
    final loaded = await store.loadAll();
    _automations.clear();

    for (var automation in loaded) {
      // Mark any leftover 'running' entries from an unclean shutdown as cancelled
      final runs = await store.loadRuns(automation.id);
      var anyStaleRun = false;
      for (final run in runs) {
        if (run.status == AutomationRunStatus.running) {
          anyStaleRun = true;
          final now = DateTime.now();
          final updatedRun = run.copyWith(
            status: AutomationRunStatus.cancelled,
            finishedAt: now,
            durationMs: now.difference(run.startedAt).inMilliseconds,
            errorMessage: 'Interrupted by system restart',
          );
          await store.saveRun(updatedRun);
          if (automation.lastRunId == run.id) {
            automation = automation.copyWith(
              lastRunStatus: AutomationRunStatus.cancelled,
            );
            await store.save(automation);
          }
        }
      }
      if (anyStaleRun) {
        _log.info('Cleaned up stale running state for automation ${automation.id}');
      }
      _automations[automation.id] = automation;
    }

    _rescheduleAll();
    _initialized = true;
    _log.info('AutomationManager initialized with ${_automations.length} automations');
  }

  void _rescheduleAll() {
    for (final tasks in _scheduledTasks.values) {
      for (final t in tasks) {
        unawaited(t.cancel());
      }
    }
    _scheduledTasks.clear();

    for (final automation in _automations.values) {
      if (automation.enabled) {
        _scheduleAutomation(automation);
      }
    }
  }

  void _scheduleAutomation(Automation automation) {
    _cancelSchedule(automation.id);
    if (!automation.enabled) return;

    final exprs = automation.schedule.toCronExpressions();
    if (exprs.isEmpty) return;

    final tasks = <ScheduledTask>[];
    for (final expr in exprs) {
      try {
        final task = _cron.schedule(Schedule.parse(expr), () async {
          _log.info('Cron triggered automation "${automation.title}" (${automation.id})');
          final latest = _automations[automation.id] ?? automation;
          if (!latest.enabled) return;
          await _executeAutomation(latest, trigger: 'scheduled');
        });
        tasks.add(task);
      } catch (e) {
        _log.severe('Failed to schedule cron "$expr" for ${automation.title}: $e');
      }
    }
    if (tasks.isNotEmpty) {
      _scheduledTasks[automation.id] = tasks;
      _log.info('Scheduled "${automation.title}" with ${tasks.length} cron trigger(s): $exprs');
    }
  }

  void _cancelSchedule(String automationId) {
    final existing = _scheduledTasks.remove(automationId);
    if (existing != null) {
      for (final task in existing) {
        unawaited(task.cancel());
      }
    }
  }

  /// Create and persist a new automation.
  Future<Automation> createAutomation({
    required String title,
    required String instructions,
    required AutomationSchedule schedule,
    String agentId = Automation.autoAgentId,
    String? agentName,
    String? providerOverride,
    String? modelOverride,
    bool enabled = true,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Automation title cannot be empty');
    }
    final err = CronUtils.validateSchedule(schedule);
    if (err != null) {
      throw ArgumentError(err);
    }

    final now = DateTime.now();
    final automation = Automation(
      id: _uuid.v4(),
      title: trimmedTitle,
      instructions: instructions.trim(),
      schedule: schedule,
      enabled: enabled,
      agentId: agentId.trim().isEmpty ? Automation.autoAgentId : agentId.trim(),
      agentName: _resolveConfiguredAgentName(agentId, agentName),
      providerOverride:
          (providerOverride?.trim().isNotEmpty ?? false) ? providerOverride!.trim() : null,
      modelOverride:
          (modelOverride?.trim().isNotEmpty ?? false) ? modelOverride!.trim() : null,
      createdAt: now,
      updatedAt: now,
    );

    _automations[automation.id] = automation;
    await store.save(automation);
    if (automation.enabled) {
      _scheduleAutomation(automation);
    }
    onChanged?.call(automation.id, 'created');
    return automation;
  }

  /// Update an existing automation and reschedule its cron triggers.
  Future<Automation> updateAutomation(
    String id, {
    String? title,
    String? instructions,
    AutomationSchedule? schedule,
    bool? enabled,
    String? agentId,
    String? agentName,
    String? providerOverride,
    bool clearProviderOverride = false,
    String? modelOverride,
    bool clearModelOverride = false,
  }) async {
    final existing = _automations[id];
    if (existing == null) {
      throw StateError('Automation not found: $id');
    }

    final nextSchedule = schedule ?? existing.schedule;
    final err = CronUtils.validateSchedule(nextSchedule);
    if (err != null) {
      throw ArgumentError(err);
    }

    final nextAgentId = agentId != null
        ? (agentId.trim().isEmpty ? Automation.autoAgentId : agentId.trim())
        : existing.agentId;

    final updated = existing.copyWith(
      title: title != null ? title.trim() : existing.title,
      instructions:
          instructions != null ? instructions.trim() : existing.instructions,
      schedule: nextSchedule,
      enabled: enabled ?? existing.enabled,
      agentId: nextAgentId,
      agentName: agentId != null
          ? _resolveConfiguredAgentName(nextAgentId, agentName)
          : (agentName ?? existing.agentName),
      providerOverride: providerOverride,
      clearProviderOverride: clearProviderOverride,
      modelOverride: modelOverride,
      clearModelOverride: clearModelOverride,
      updatedAt: DateTime.now(),
    );

    _automations[id] = updated;
    await store.save(updated);

    if (updated.enabled) {
      _scheduleAutomation(updated);
    } else {
      _cancelSchedule(id);
    }

    onChanged?.call(id, 'updated');
    return updated;
  }

  /// Toggle active/paused state.
  Future<Automation> toggleAutomation(String id, bool enabled) {
    return updateAutomation(id, enabled: enabled);
  }

  /// Delete an automation, its run logs, and all linked `auto_<id>_*` sessions.
  Future<void> deleteAutomation(String id) async {
    _cancelSchedule(id);

    // Collect all session IDs belonging to this automation (from runs + active session cache)
    final runs = await store.loadRuns(id);
    final sessionIds = <String>{
      for (final r in runs) r.sessionId,
      for (final s in sessionManager.listSessions())
        if ((s['id'] as String?)?.startsWith('auto_${id}_') == true)
          s['id'] as String,
    };

    for (final sid in sessionIds) {
      agentManager.stop(sid);
    }
    if (sessionIds.isNotEmpty) {
      await sessionManager.deleteSessions(sessionIds.toList());
      for (final sid in sessionIds) {
        onSessionDeleted?.call(sid);
      }
    }

    _automations.remove(id);
    await store.delete(id);
    onChanged?.call(id, 'deleted');
  }

  Future<List<AutomationRun>> getRuns(String automationId, {int? limit}) {
    return store.loadRuns(automationId, limit: limit);
  }

  /// Trigger an immediate manual run, returning the initial [AutomationRun]
  /// synchronously while the agent executes asynchronously in the background.
  Future<AutomationRun> triggerRunNow(String id) async {
    final automation = _automations[id];
    if (automation == null) {
      throw StateError('Automation not found: $id');
    }
    if (_activeRunIds.contains(id)) {
      throw StateError('Automation "${automation.title}" is already running');
    }

    final prepared = await _prepareRun(automation, trigger: 'manual');
    unawaited(_executePreparedRun(prepared));
    return prepared.run;
  }

  Future<void> _executeAutomation(
    Automation automation, {
    required String trigger,
  }) async {
    if (_activeRunIds.contains(automation.id)) {
      _log.warning(
        'Skipping scheduled run for "${automation.title}" (${automation.id}) — previous run still active',
      );
      return;
    }
    final prepared = await _prepareRun(automation, trigger: trigger);
    await _executePreparedRun(prepared);
  }

  Future<({
    Automation automation,
    AutomationRun run,
    Agent agent,
    Session session,
  })> _prepareRun(
    Automation automation, {
    required String trigger,
  }) async {
    _activeRunIds.add(automation.id);

    final runId = _uuid.v4().substring(0, 8);
    final sessionId = 'auto_${automation.id}_$runId';
    final startedAt = DateTime.now();

    // Resolve target agent (explicit or Auto via Ontology)
    Agent agent;
    String resolvedAgentId = automation.agentId;
    String resolvedAgentName;
    Map<String, dynamic>? routingMetadata;

    if (automation.isAutoRouting && orchestrator != null) {
      final decision = await orchestrator!.evaluateRoutingForRequest(
        title: automation.title,
        description: automation.instructions,
      );
      resolvedAgentId = decision.selectedAgentId;
      resolvedAgentName = decision.selectedAgentName;
      routingMetadata = decision.toMetadataJson();
      agent = agentManager.getAgent(resolvedAgentId);
    } else {
      agent = agentManager.getAgent(automation.agentId);
      resolvedAgentId = agent.id;
      resolvedAgentName = _resolveConfiguredAgentName(agent.id, null) ?? agent.name;
    }

    final resolvedProvider =
        automation.providerOverride ?? agent.provider.providerId;
    final resolvedModel = automation.modelOverride ?? agent.provider.modelId;

    final session = sessionManager.createSession(
      id: sessionId,
      channelType: 'automation',
      peerId: automation.id,
    );
    session.agentId = resolvedAgentId;
    session.agentName = resolvedAgentName;
    session.provider = resolvedProvider;
    session.model = resolvedModel;
    session.title = automation.title;

    final run = AutomationRun(
      id: runId,
      automationId: automation.id,
      title: automation.title,
      status: AutomationRunStatus.running,
      trigger: trigger,
      startedAt: startedAt,
      sessionId: sessionId,
      resolvedAgentId: resolvedAgentId,
      resolvedAgentName: resolvedAgentName,
      resolvedProvider: resolvedProvider,
      resolvedModel: resolvedModel,
      routingDecision: routingMetadata,
    );

    await store.saveRun(run);
    final updatedAutomation = (_automations[automation.id] ?? automation).copyWith(
      lastRunAt: startedAt,
      lastRunStatus: AutomationRunStatus.running,
      lastRunId: run.id,
      lastSessionId: sessionId,
      lastRoutingMetadata: routingMetadata,
    );
    _automations[automation.id] = updatedAutomation;
    await store.save(updatedAutomation);

    onRunUpdated?.call(automation.id, run);
    onChanged?.call(automation.id, 'run_started');

    return (
      automation: updatedAutomation,
      run: run,
      agent: agent,
      session: session,
    );
  }

  Future<void> _executePreparedRun(
    ({
      Automation automation,
      AutomationRun run,
      Agent agent,
      Session session,
    }) prepared,
  ) async {
    final automation = prepared.automation;
    final run = prepared.run;
    final agent = prepared.agent;
    final session = prepared.session;

    try {
      var prompt = automation.instructions.trim();
      if (prompt.isEmpty) {
        prompt = automation.title;
      }
      if (agent.skills.isNotEmpty) {
        prompt +=
            '\n\nIMPORTANT: Use your available skills when helpful to complete this automation task.';
      }

      await sessionManager.addMessage(
        sessionId: session.id,
        role: 'user',
        content: prompt,
        metadata: {
          'channelType': 'automation',
          'senderId': automation.id,
          'automationId': automation.id,
          'runId': run.id,
          'agentId': run.resolvedAgentId,
          'agentName': run.resolvedAgentName,
          if (automation.providerOverride != null)
            'provider': automation.providerOverride,
          if (automation.modelOverride != null) 'model': automation.modelOverride,
          'title': automation.title,
        },
      );

      await agent.processMessage(
        sessionId: session.id,
        content: prompt,
        model: automation.modelOverride,
        providerHint: automation.providerOverride,
        onPartialResponse: (chunk) {
          agentManager.onSessionStream?.call(session.id, chunk);
        },
        onActivityUpdate: (activity) {
          agentManager.onSessionActivity?.call(session.id, activity);
        },
      );

      // Persist session title cleanly (keep automation title or auto-generated summary)
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(run.startedAt).inMilliseconds;

      String? summary;
      final lastAssistant = session.history
          .where((m) => m.role == 'assistant' && m.content.trim().isNotEmpty)
          .lastOrNull;
      if (lastAssistant != null) {
        final raw = lastAssistant.content.trim().replaceAll(RegExp(r'\s+'), ' ');
        summary = raw.length > 280 ? '${raw.substring(0, 280)}...' : raw;
      }

      // Notify any open ChatScreen watching this session
      if (agentManager.onSessionUpdated != null && session.history.isNotEmpty) {
        agentManager.onSessionUpdated!(session.id, session.history.last);
      }

      final completedRun = run.copyWith(
        status: AutomationRunStatus.success,
        finishedAt: finishedAt,
        durationMs: durationMs,
        summary: summary,
      );
      await store.saveRun(completedRun);

      final latestAutomation = (_automations[automation.id] ?? automation).copyWith(
        lastRunAt: run.startedAt,
        lastRunStatus: AutomationRunStatus.success,
        lastRunId: run.id,
        lastSessionId: session.id,
      );
      _automations[automation.id] = latestAutomation;
      await store.save(latestAutomation);

      onRunUpdated?.call(automation.id, completedRun);
      onChanged?.call(automation.id, 'run_finished');
    } catch (e, stack) {
      _log.severe(
        'Automation "${automation.title}" (${automation.id}) failed: $e',
        e,
        stack,
      );
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(run.startedAt).inMilliseconds;
      final errorText = e.toString();

      try {
        await sessionManager.addMessage(
          sessionId: session.id,
          role: 'error',
          content: '⚠️ Automation failed: $errorText',
          metadata: {'is_error': true},
        );
        if (agentManager.onSessionUpdated != null &&
            session.history.isNotEmpty) {
          agentManager.onSessionUpdated!(session.id, session.history.last);
        }
      } catch (_) {}

      final failedRun = run.copyWith(
        status: AutomationRunStatus.failed,
        finishedAt: finishedAt,
        durationMs: durationMs,
        errorMessage: errorText,
      );
      await store.saveRun(failedRun);

      final latestAutomation = (_automations[automation.id] ?? automation).copyWith(
        lastRunAt: run.startedAt,
        lastRunStatus: AutomationRunStatus.failed,
        lastRunId: run.id,
        lastSessionId: session.id,
      );
      _automations[automation.id] = latestAutomation;
      await store.save(latestAutomation);

      onRunUpdated?.call(automation.id, failedRun);
      onChanged?.call(automation.id, 'run_failed');
    } finally {
      _activeRunIds.remove(automation.id);
    }
  }

  /// Evaluate Ontology Routing for an automation title/instructions without persisting.
  Future<Map<String, dynamic>?> previewRouting({
    required String title,
    required String instructions,
  }) async {
    if (orchestrator == null) return null;
    final decision = await orchestrator!.evaluateRoutingForRequest(
      title: title,
      description: instructions,
    );
    return decision.toMetadataJson();
  }

  /// Uses the default AI provider + Ontology context to generate a complete,
  /// editable automation draft from a short natural-language description.
  Future<Map<String, dynamic>> generateFromPrompt(
    String prompt, {
    String locale = 'en',
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw ArgumentError('Prompt cannot be empty');
    }

    final config = agentManager.config;
    final provider = agentManager.defaultAgent.provider;

    final agentCatalog = <Map<String, dynamic>>[
      {
        'id': Automation.autoAgentId,
        'name': 'Auto (Ontology)',
        'description':
            'Automatically selects the best specialist agent per run via the Knowledge Graph.',
      },
      {
        'id': 'default-agent',
        'name': config.identity.name,
        'competencies': config.agent.competencies,
      },
      for (final ca in config.customAgents)
        if (ca.enabled)
          {
            'id': ca.id,
            'name': ca.name,
            'competencies': ca.competencies,
            'systemPromptPreview': ca.systemPrompt.length > 160
                ? '${ca.systemPrompt.substring(0, 160)}...'
                : ca.systemPrompt,
          },
    ];

    final targetLang =
        locale.toLowerCase().startsWith('de') ? 'German' : 'English';

    final systemPrompt = '''
You are an expert Ghost Automation Architect.
Convert the user's brief automation request into a structured JSON object.
Respond ONLY with valid JSON (no markdown fences, no prose).
Use $targetLang for "title" and "instructions".

Available agents:
${jsonEncode(agentCatalog)}

JSON schema:
{
  "title": "Concise 2-6 word title",
  "instructions": "Detailed, actionable step-by-step instructions for the AI agent executing this automation.",
  "agentId": "auto | default-agent | <custom_agent_id>",
  "schedule": {
    "mode": "daily | weekdays | weekly | hourly | interval | custom",
    "times": ["HH:mm"],
    "daysOfWeek": [1, 2, 3, 4, 5],
    "intervalValue": 1,
    "intervalUnit": "minutes | hours",
    "customCron": null
  }
}

Rules:
- Prefer "agentId": "auto" unless the user clearly names a specific agent or one custom agent is an unmistakable exact match.
- NEVER round times or intervals to 5- or 15-minute steps; preserve exact minutes and interval counts from the prompt:
  * "every 3 minutes" / "alle 3 Minuten" -> "mode": "interval", "intervalValue": 3, "intervalUnit": "minutes"
  * "every 7 minutes" / "alle 7 Minuten" -> "mode": "interval", "intervalValue": 7, "intervalUnit": "minutes"
  * "every 2 hours" / "alle 2 Stunden" -> "mode": "interval", "intervalValue": 2, "intervalUnit": "hours"
  * "every 3 hours at :12" -> "mode": "hourly", "intervalValue": 3, "times": ["00:12"]
  * "daily at 8:12" / "täglich um 8:12" -> "mode": "daily", "times": ["08:12"]
  * "weekdays at 8:12 and 17:43" -> "mode": "weekdays", "times": ["08:12", "17:43"]
- For specific days (e.g. "Mondays and Thursdays at 10:07"), use "mode": "weekly" with ISO daysOfWeek (1=Mon..7=Sun).
- If no schedule is specified, default to daily at "09:00".
- Only use "mode": "custom" with a valid 5-field Unix cron if the pattern cannot be represented by the structured modes.
''';

    final response = await provider.chat(
      messages: [
        Message(
          role: 'user',
          content: trimmedPrompt,
          timestamp: DateTime.now(),
        ),
      ],
      systemPrompt: systemPrompt,
      maxTokens: 900,
      temperature: 0.2,
    );

    final parsed = _extractJsonObject(response.content);

    final title = (parsed['title'] as String?)?.trim().isNotEmpty == true
        ? (parsed['title'] as String).trim()
        : (trimmedPrompt.length > 48
            ? '${trimmedPrompt.substring(0, 48)}...'
            : trimmedPrompt);

    final instructions =
        (parsed['instructions'] as String?)?.trim().isNotEmpty == true
            ? (parsed['instructions'] as String).trim()
            : trimmedPrompt;

    var schedule = parsed['schedule'] is Map
        ? AutomationSchedule.fromJson(
            Map<String, dynamic>.from(parsed['schedule'] as Map),
          )
        : const AutomationSchedule();

    // Fallback to safe daily schedule if LLM produced invalid cron/fields,
    // and reconcile custom crons or exact prompt intervals/times.
    if (CronUtils.validateSchedule(schedule) != null) {
      if (schedule.customCron != null &&
          CronUtils.validateCron(schedule.customCron!) == null) {
        schedule = CronUtils.scheduleFromCron(schedule.customCron!);
      } else {
        schedule = const AutomationSchedule();
      }
    } else if (schedule.mode == AutomationScheduleMode.custom &&
        schedule.customCron != null) {
      final structured = CronUtils.scheduleFromCron(schedule.customCron!);
      if (structured.mode != AutomationScheduleMode.custom) {
        schedule = structured;
      }
    }
    schedule = _reconcilePromptSchedule(trimmedPrompt, schedule);

    var agentId = (parsed['agentId'] as String?)?.trim() ?? Automation.autoAgentId;
    final validAgentIds = {
      Automation.autoAgentId,
      'default-agent',
      for (final ca in config.customAgents)
        if (ca.enabled) ca.id,
    };
    if (!validAgentIds.contains(agentId)) {
      agentId = Automation.autoAgentId;
    }

    Map<String, dynamic>? routingPreview;
    if (agentId == Automation.autoAgentId && orchestrator != null) {
      routingPreview = await previewRouting(
        title: title,
        instructions: instructions,
      );
    }

    final nextRun = CronUtils.computeNextRun(schedule);

    return {
      'title': title,
      'instructions': instructions,
      'agentId': agentId,
      'agentName': _resolveConfiguredAgentName(agentId, null),
      'schedule': schedule.toJson(),
      'humanSchedule': CronUtils.formatHumanReadable(schedule, locale: locale),
      if (nextRun != null) 'nextRunAt': nextRun.toIso8601String(),
      if (routingPreview != null) 'routingPreview': routingPreview,
    };
  }

  /// Reconciles unambiguous interval numbers (e.g. "alle 3 Minuten") and
  /// explicit HH:mm times (e.g. "8:12") from [prompt] if the LLM rounded them.
  AutomationSchedule _reconcilePromptSchedule(
    String prompt,
    AutomationSchedule schedule,
  ) {
    final intervalMatch = RegExp(
      r'(?:alle|jede[nr]?|every|each)\s+(\d{1,2})\s*(min(?:ute|uten|s)?|std\.?|stunde(?:n)?|hour(?:s)?|h)\b',
      caseSensitive: false,
    ).firstMatch(prompt);

    if (intervalMatch != null &&
        (schedule.mode == AutomationScheduleMode.interval ||
            schedule.mode == AutomationScheduleMode.hourly)) {
      final rawNum = int.tryParse(intervalMatch.group(1)!);
      final rawUnit = intervalMatch.group(2)!.toLowerCase();
      if (rawNum != null && rawNum >= 1) {
        final isHours = rawUnit.startsWith('std') ||
            rawUnit.startsWith('hour') ||
            rawUnit == 'h';
        if (isHours && rawNum <= 24) {
          if (schedule.mode == AutomationScheduleMode.hourly) {
            return schedule.copyWith(intervalValue: rawNum);
          }
          return schedule.copyWith(
            mode: AutomationScheduleMode.interval,
            intervalValue: rawNum,
            intervalUnit: AutomationIntervalUnit.hours,
          );
        } else if (!isHours && rawNum <= 59) {
          return schedule.copyWith(
            mode: AutomationScheduleMode.interval,
            intervalValue: rawNum,
            intervalUnit: AutomationIntervalUnit.minutes,
          );
        }
      }
    }

    // Normalize HH:mm values in daily/weekdays/weekly without rounding minutes
    if (schedule.mode == AutomationScheduleMode.daily ||
        schedule.mode == AutomationScheduleMode.weekdays ||
        schedule.mode == AutomationScheduleMode.weekly) {
      final normalized = schedule.times
          .map((t) {
            final p = AutomationSchedule.parseTime(t);
            return p != null
                ? AutomationSchedule.normalizeTime(p.hour, p.minute)
                : t;
          })
          .toSet()
          .toList()
        ..sort();
      if (normalized.isNotEmpty) {
        return schedule.copyWith(times: normalized);
      }
    }

    return schedule;
  }

  Map<String, dynamic> _extractJsonObject(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start != -1 && end > start) {
        final slice = cleaned.substring(start, end + 1);
        final decoded = jsonDecode(slice);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    }
    return {};
  }

  String? _resolveConfiguredAgentName(String agentId, String? fallback) {
    if (agentId == Automation.autoAgentId) return 'Auto (Ontology)';
    if (agentId == 'default-agent') return agentManager.config.identity.name;
    for (final ca in agentManager.config.customAgents) {
      if (ca.id == agentId) return ca.name;
    }
    return fallback;
  }

  /// Shutdown cron tasks cleanly (e.g., before backup restore or factory reset).
  Future<void> shutdown() async {
    if (!_initialized && _scheduledTasks.isEmpty) return;
    for (final tasks in _scheduledTasks.values) {
      for (final t in tasks) {
        await t.cancel();
      }
    }
    _scheduledTasks.clear();
    await _cron.close();
    store.dispose();
    _initialized = false;
  }
}
