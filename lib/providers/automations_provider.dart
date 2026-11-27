// Ghost — Automations Riverpod Provider.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/gateway.dart';
import '../engine/automations/automation_models.dart';
import '../engine/automations/cron_utils.dart';
import 'gateway_provider.dart';

/// Enriched automation item returned by `automations.list` / `automations.get`.
class AutomationListItem {
  const AutomationListItem({
    required this.automation,
    required this.humanSchedule,
    required this.cronExpressions,
    this.nextRunAt,
    this.isRunning = false,
  });

  factory AutomationListItem.fromJson(
    Map<String, dynamic> json, {
    String locale = 'en',
  }) {
    final automation = Automation.fromJson(json);
    final humanSchedule = json['humanSchedule'] as String? ??
        CronUtils.formatHumanReadable(automation.schedule, locale: locale);
    final cronExprs = (json['cronExpressions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        automation.schedule.toCronExpressions();
    final nextRunAt = json['nextRunAt'] != null
        ? DateTime.tryParse(json['nextRunAt'] as String)
        : (automation.enabled
            ? CronUtils.computeNextRun(automation.schedule)
            : null);

    return AutomationListItem(
      automation: automation,
      humanSchedule: humanSchedule,
      cronExpressions: cronExprs,
      nextRunAt: nextRunAt,
      isRunning: json['isRunning'] as bool? ??
          automation.lastRunStatus == AutomationRunStatus.running,
    );
  }

  final Automation automation;
  final String humanSchedule;
  final List<String> cronExpressions;
  final DateTime? nextRunAt;
  final bool isRunning;
}

class AutomationsState {
  const AutomationsState({
    this.items = const [],
    this.runsByAutomation = const {},
    this.nextRunsByAutomation = const {},
    this.isLoading = false,
    this.error,
  });

  final List<AutomationListItem> items;
  final Map<String, List<AutomationRun>> runsByAutomation;
  final Map<String, List<DateTime>> nextRunsByAutomation;
  final bool isLoading;
  final String? error;

  AutomationsState copyWith({
    List<AutomationListItem>? items,
    Map<String, List<AutomationRun>>? runsByAutomation,
    Map<String, List<DateTime>>? nextRunsByAutomation,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return AutomationsState(
      items: items ?? this.items,
      runsByAutomation: runsByAutomation ?? this.runsByAutomation,
      nextRunsByAutomation: nextRunsByAutomation ?? this.nextRunsByAutomation,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final automationsSearchQueryProvider =
    NotifierProvider<AutomationsSearchQueryNotifier, String>(() {
  return AutomationsSearchQueryNotifier();
});

class AutomationsSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String q) => state = q;
  void clear() => state = '';
}

final selectedAutomationIdProvider =
    NotifierProvider<SelectedAutomationIdNotifier, String?>(() {
  return SelectedAutomationIdNotifier();
});

class SelectedAutomationIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final automationsProvider =
    NotifierProvider<AutomationsNotifier, AutomationsState>(() {
  return AutomationsNotifier();
});

class AutomationsNotifier extends Notifier<AutomationsState> {
  String _locale() {
    final lang = ref.read(configProvider).user.language;
    return (lang != null && lang.isNotEmpty) ? lang : 'en';
  }

  @override
  AutomationsState build() {
    ref.listen(connectionStatusProvider, (prev, next) {
      if (next.value == ConnectionStatus.authenticated) {
        refresh();
      }
    });

    ref.listen(configProvider.select((c) => c.user.language), (prev, next) {
      if (prev != next &&
          ref.read(connectionStatusProvider).value ==
              ConnectionStatus.authenticated) {
        refresh();
      }
    });

    final sub = ref.read(gatewayClientProvider).messages.listen((msg) {
      final method = msg['method'] as String?;
      if (method == 'automations.changed') {
        final automationId = msg['params']?['automationId'] as String?;
        refresh();
        if (automationId != null &&
            ref.read(selectedAutomationIdProvider) == automationId) {
          loadDetail(automationId);
        }
      } else if (method == 'automations.run_updated') {
        final automationId = msg['params']?['automationId'] as String?;
        final rawRun = msg['params']?['run'];
        if (automationId != null && rawRun is Map) {
          final run =
              AutomationRun.fromJson(Map<String, dynamic>.from(rawRun));
          _upsertRunLocally(automationId, run);
          refresh();
        }
      }
    });
    ref.onDispose(() => sub.cancel());

    final status = ref.read(connectionStatusProvider).value;
    if (status == ConnectionStatus.authenticated) {
      Future.microtask(() => refresh());
    }

    return const AutomationsState();
  }

  void _upsertRunLocally(String automationId, AutomationRun run) {
    final current = List<AutomationRun>.from(
      state.runsByAutomation[automationId] ?? const [],
    );
    final idx = current.indexWhere((r) => r.id == run.id);
    if (idx >= 0) {
      current[idx] = run;
    } else {
      current.insert(0, run);
    }
    current.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    state = state.copyWith(
      runsByAutomation: {
        ...state.runsByAutomation,
        automationId: current,
      },
    );
  }

  Future<void> refresh({bool silent = true}) async {
    final client = ref.read(gatewayClientProvider);
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final locale = _locale();
      final result = await client.call('automations.list', {'locale': locale});
      final rawList = (result['automations'] as List<dynamic>? ?? const []);
      final items = rawList
          .map(
            (e) => AutomationListItem.fromJson(
              Map<String, dynamic>.from(e as Map),
              locale: locale,
            ),
          )
          .toList();
      state = state.copyWith(
        items: items,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadDetail(String id) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final locale = _locale();
      final result = await client.call('automations.get', {
        'id': id,
        'locale': locale,
      });
      final item = AutomationListItem.fromJson(
        Map<String, dynamic>.from(result['automation'] as Map),
        locale: locale,
      );
      final runs = (result['runs'] as List<dynamic>? ?? const [])
          .map(
            (e) => AutomationRun.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      final nextRuns = (result['nextRuns'] as List<dynamic>? ?? const [])
          .map((e) => DateTime.tryParse(e.toString()))
          .whereType<DateTime>()
          .toList();

      final updatedItems = List<AutomationListItem>.from(state.items);
      final idx = updatedItems.indexWhere((i) => i.automation.id == id);
      if (idx >= 0) {
        updatedItems[idx] = item;
      } else {
        updatedItems.add(item);
      }

      state = state.copyWith(
        items: updatedItems,
        runsByAutomation: {
          ...state.runsByAutomation,
          id: runs,
        },
        nextRunsByAutomation: {
          ...state.nextRunsByAutomation,
          id: nextRuns,
        },
      );
    } catch (_) {}
  }

  Future<AutomationListItem> create({
    required String title,
    required String instructions,
    required AutomationSchedule schedule,
    String agentId = Automation.autoAgentId,
    String? providerOverride,
    String? modelOverride,
    bool enabled = true,
  }) async {
    final client = ref.read(gatewayClientProvider);
    final locale = _locale();
    final result = await client.call('automations.create', {
      'title': title,
      'instructions': instructions,
      'schedule': schedule.toJson(),
      'agentId': agentId,
      if (providerOverride != null) 'providerOverride': providerOverride,
      if (modelOverride != null) 'modelOverride': modelOverride,
      'enabled': enabled,
      'locale': locale,
    });
    final created = AutomationListItem.fromJson(
      Map<String, dynamic>.from(result['automation'] as Map),
      locale: locale,
    );
    await refresh();
    return created;
  }

  Future<AutomationListItem> update(
    String id, {
    String? title,
    String? instructions,
    AutomationSchedule? schedule,
    bool? enabled,
    String? agentId,
    String? providerOverride,
    bool clearProviderOverride = false,
    String? modelOverride,
    bool clearModelOverride = false,
  }) async {
    final client = ref.read(gatewayClientProvider);
    final locale = _locale();
    final result = await client.call('automations.update', {
      'id': id,
      if (title != null) 'title': title,
      if (instructions != null) 'instructions': instructions,
      if (schedule != null) 'schedule': schedule.toJson(),
      if (enabled != null) 'enabled': enabled,
      if (agentId != null) 'agentId': agentId,
      if (providerOverride != null) 'providerOverride': providerOverride,
      if (clearProviderOverride) 'clearProviderOverride': true,
      if (modelOverride != null) 'modelOverride': modelOverride,
      if (clearModelOverride) 'clearModelOverride': true,
      'locale': locale,
    });
    final updated = AutomationListItem.fromJson(
      Map<String, dynamic>.from(result['automation'] as Map),
      locale: locale,
    );
    await loadDetail(id);
    await refresh();
    return updated;
  }

  Future<void> toggle(String id, bool enabled) async {
    final client = ref.read(gatewayClientProvider);
    final locale = _locale();
    // Optimistic update
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.automation.id == id) {
          final nextAuto = item.automation.copyWith(enabled: enabled);
          return AutomationListItem(
            automation: nextAuto,
            humanSchedule: item.humanSchedule,
            cronExpressions: item.cronExpressions,
            nextRunAt:
                enabled ? CronUtils.computeNextRun(nextAuto.schedule) : null,
            isRunning: item.isRunning,
          );
        }
        return item;
      }).toList(),
    );

    try {
      await client.call('automations.toggle', {
        'id': id,
        'enabled': enabled,
        'locale': locale,
      });
      await refresh();
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final client = ref.read(gatewayClientProvider);
    await client.call('automations.delete', {'id': id});
    if (ref.read(selectedAutomationIdProvider) == id) {
      ref.read(selectedAutomationIdProvider.notifier).select(null);
    }
    final nextRuns = Map<String, List<AutomationRun>>.from(state.runsByAutomation)
      ..remove(id);
    state = state.copyWith(
      items: state.items.where((i) => i.automation.id != id).toList(),
      runsByAutomation: nextRuns,
    );
  }

  Future<AutomationRun> runNow(String id) async {
    final client = ref.read(gatewayClientProvider);
    final result = await client.call('automations.runNow', {'id': id});
    final run =
        AutomationRun.fromJson(Map<String, dynamic>.from(result['run'] as Map));
    _upsertRunLocally(id, run);
    await refresh();
    return run;
  }

  Future<Map<String, dynamic>> generateFromPrompt(
    String prompt, {
    String? locale,
  }) async {
    final client = ref.read(gatewayClientProvider);
    final result = await client.call('automations.generateFromPrompt', {
      'prompt': prompt,
      'locale': locale ?? _locale(),
    });
    return Map<String, dynamic>.from(result['draft'] as Map);
  }

  Future<Map<String, dynamic>?> previewRouting({
    required String title,
    required String instructions,
  }) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('automations.previewRouting', {
        'title': title,
        'instructions': instructions,
      });
      final raw = result['decision'];
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {}
    return null;
  }
}

final filteredAutomationsProvider = Provider<List<AutomationListItem>>((ref) {
  final state = ref.watch(automationsProvider);
  final query = ref.watch(automationsSearchQueryProvider).trim().toLowerCase();

  if (query.isEmpty) return state.items;

  return state.items.where((item) {
    final a = item.automation;
    return a.title.toLowerCase().contains(query) ||
        a.instructions.toLowerCase().contains(query) ||
        (a.agentName?.toLowerCase().contains(query) ?? false) ||
        item.humanSchedule.toLowerCase().contains(query);
  }).toList();
});
