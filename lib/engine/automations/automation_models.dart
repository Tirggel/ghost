// Ghost — Automations Data Models (Pure Dart, no Flutter/dart:ui imports).

import 'dart:convert';

/// Schedule mode for an Automation.
enum AutomationScheduleMode {
  daily,
  weekdays,
  weekly,
  hourly,
  interval,
  custom,
}

/// Unit for [AutomationScheduleMode.interval] schedules.
enum AutomationIntervalUnit {
  minutes,
  hours,
}

/// Execution status of an Automation run.
enum AutomationRunStatus {
  running,
  success,
  failed,
  cancelled,
}

/// Structured, human-friendly schedule that compiles into one or more
/// standard 5-field Unix cron expressions (`min hour dom month dow`).
class AutomationSchedule {
  const AutomationSchedule({
    this.mode = AutomationScheduleMode.daily,
    this.times = const ['09:00'],
    this.daysOfWeek = const [1, 2, 3, 4, 5],
    this.intervalValue = 1,
    this.intervalUnit = AutomationIntervalUnit.minutes,
    this.customCron,
  });

  factory AutomationSchedule.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? 'daily';
    final mode = AutomationScheduleMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => AutomationScheduleMode.daily,
    );

    final unitName = (json['intervalUnit'] as String? ?? '').toLowerCase();
    final intervalUnit = unitName == 'hours' || unitName == 'hour'
        ? AutomationIntervalUnit.hours
        : AutomationIntervalUnit.minutes;

    final rawTimes = (json['times'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const ['09:00'];

    final rawDays = ((json['daysOfWeek'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .where((d) => d >= 1 && d <= 7)
                .toSet()
                .toList() ??
            <int>[1, 2, 3, 4, 5])
        ..sort();

    final maxInterval =
        (mode == AutomationScheduleMode.hourly ||
                (mode == AutomationScheduleMode.interval &&
                    intervalUnit == AutomationIntervalUnit.hours))
            ? 24
            : 59;

    return AutomationSchedule(
      mode: mode,
      times: rawTimes.isEmpty ? const ['09:00'] : rawTimes,
      daysOfWeek: rawDays.isEmpty ? const [1, 2, 3, 4, 5] : rawDays,
      intervalValue:
          ((json['intervalValue'] as num?)?.toInt() ?? 1).clamp(1, maxInterval),
      intervalUnit: intervalUnit,
      customCron: json['customCron'] as String?,
    );
  }

  final AutomationScheduleMode mode;

  /// List of 24h time strings (`HH:mm`), e.g. `['08:15', '17:15']`.
  final List<String> times;

  /// ISO weekday numbers: `1` = Monday .. `7` = Sunday.
  final List<int> daysOfWeek;

  /// Interval value for `hourly` (`1..24`) or `interval` (`1..59` min / `1..24` h).
  final int intervalValue;

  /// Unit for [AutomationScheduleMode.interval] (`minutes` or `hours`).
  final AutomationIntervalUnit intervalUnit;

  /// Raw 5-field Unix cron expression used when [mode] is [AutomationScheduleMode.custom].
  final String? customCron;

  /// Parses `"HH:mm"` into `(hour, minute)`. Returns null if invalid.
  static ({int hour, int minute})? parseTime(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  /// Normalizes a time string to zero-padded `HH:mm`.
  static String normalizeTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Compiles this schedule into one or more 5-field Unix cron expressions.
  ///
  /// Multiple times with differing minutes (e.g. `08:15` and `17:30`) produce
  /// multiple cron expressions so `package:cron` triggers at the exact times.
  List<String> toCronExpressions() {
    switch (mode) {
      case AutomationScheduleMode.custom:
        final expr = (customCron ?? '').trim();
        return expr.isEmpty ? const [] : [expr];

      case AutomationScheduleMode.interval:
        if (intervalUnit == AutomationIntervalUnit.hours) {
          final step = intervalValue.clamp(1, 24);
          if (step == 1) return const ['0 * * * *'];
          if (step == 24) return const ['0 0 * * *'];
          return ['0 */$step * * *'];
        }
        final step = intervalValue.clamp(1, 59);
        if (step == 1) return const ['* * * * *'];
        return ['*/$step * * * *'];

      case AutomationScheduleMode.hourly:
        final parsed = times.isNotEmpty ? parseTime(times.first) : null;
        final minute = parsed?.minute ?? 0;
        final step = intervalValue.clamp(1, 24);
        if (step == 1) return ['$minute * * * *'];
        if (step == 24) return ['$minute 0 * * *'];
        return ['$minute */$step * * *'];

      case AutomationScheduleMode.daily:
        return _compileTimesWithDow('*');

      case AutomationScheduleMode.weekdays:
        return _compileTimesWithDow('1-5');

      case AutomationScheduleMode.weekly:
        final sortedDays = (daysOfWeek.toSet().toList()..sort());
        if (sortedDays.isEmpty) return const [];
        final dowExpr = sortedDays.length == 7 ? '*' : sortedDays.join(',');
        return _compileTimesWithDow(dowExpr);
    }
  }

  List<String> _compileTimesWithDow(String dowExpr) {
    final parsedTimes = times
        .map(parseTime)
        .whereType<({int hour, int minute})>()
        .toList();
    if (parsedTimes.isEmpty) {
      return ['0 9 * * $dowExpr'];
    }

    // Group hours by minute so identical minutes share one compact cron line
    final byMinute = <int, Set<int>>{};
    for (final t in parsedTimes) {
      byMinute.putIfAbsent(t.minute, () => <int>{}).add(t.hour);
    }

    final minutes = byMinute.keys.toList()..sort();
    final expressions = <String>[];
    for (final minute in minutes) {
      final hours = byMinute[minute]!.toList()..sort();
      expressions.add('$minute ${hours.join(',')} * * $dowExpr');
    }
    return expressions;
  }

  AutomationSchedule copyWith({
    AutomationScheduleMode? mode,
    List<String>? times,
    List<int>? daysOfWeek,
    int? intervalValue,
    AutomationIntervalUnit? intervalUnit,
    String? customCron,
    bool clearCustomCron = false,
  }) {
    return AutomationSchedule(
      mode: mode ?? this.mode,
      times: times ?? this.times,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      intervalValue: intervalValue ?? this.intervalValue,
      intervalUnit: intervalUnit ?? this.intervalUnit,
      customCron: clearCustomCron ? null : (customCron ?? this.customCron),
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'times': times,
        'daysOfWeek': daysOfWeek,
        'intervalValue': intervalValue,
        'intervalUnit': intervalUnit.name,
        if (customCron != null) 'customCron': customCron,
      };
}

/// Persistent metadata for a single execution of an [Automation].
class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.automationId,
    required this.title,
    required this.status,
    required this.trigger,
    required this.startedAt,
    required this.sessionId,
    this.finishedAt,
    this.durationMs,
    this.resolvedAgentId,
    this.resolvedAgentName,
    this.resolvedProvider,
    this.resolvedModel,
    this.routingDecision,
    this.summary,
    this.errorMessage,
  });

  factory AutomationRun.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'failed';
    final status = AutomationRunStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => AutomationRunStatus.failed,
    );

    return AutomationRun(
      id: json['id'] as String,
      automationId: json['automationId'] as String,
      title: json['title'] as String? ?? 'Automation Run',
      status: status,
      trigger: json['trigger'] as String? ?? 'scheduled',
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] != null
          ? DateTime.tryParse(json['finishedAt'] as String)
          : null,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      sessionId: json['sessionId'] as String,
      resolvedAgentId: json['resolvedAgentId'] as String?,
      resolvedAgentName: json['resolvedAgentName'] as String?,
      resolvedProvider: json['resolvedProvider'] as String?,
      resolvedModel: json['resolvedModel'] as String?,
      routingDecision: json['routingDecision'] is Map<String, dynamic>
          ? json['routingDecision'] as Map<String, dynamic>
          : (json['routingDecision'] is Map
              ? Map<String, dynamic>.from(json['routingDecision'] as Map)
              : null),
      summary: json['summary'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  final String id;
  final String automationId;
  final String title;
  final AutomationRunStatus status;
  final String trigger; // 'scheduled' | 'manual'
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? durationMs;
  final String sessionId;
  final String? resolvedAgentId;
  final String? resolvedAgentName;
  final String? resolvedProvider;
  final String? resolvedModel;
  final Map<String, dynamic>? routingDecision;
  final String? summary;
  final String? errorMessage;

  AutomationRun copyWith({
    String? title,
    AutomationRunStatus? status,
    DateTime? finishedAt,
    int? durationMs,
    String? resolvedAgentId,
    String? resolvedAgentName,
    String? resolvedProvider,
    String? resolvedModel,
    Map<String, dynamic>? routingDecision,
    String? summary,
    String? errorMessage,
  }) {
    return AutomationRun(
      id: id,
      automationId: automationId,
      title: title ?? this.title,
      status: status ?? this.status,
      trigger: trigger,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationMs: durationMs ?? this.durationMs,
      sessionId: sessionId,
      resolvedAgentId: resolvedAgentId ?? this.resolvedAgentId,
      resolvedAgentName: resolvedAgentName ?? this.resolvedAgentName,
      resolvedProvider: resolvedProvider ?? this.resolvedProvider,
      resolvedModel: resolvedModel ?? this.resolvedModel,
      routingDecision: routingDecision ?? this.routingDecision,
      summary: summary ?? this.summary,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'automationId': automationId,
        'title': title,
        'status': status.name,
        'trigger': trigger,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (durationMs != null) 'durationMs': durationMs,
        'sessionId': sessionId,
        if (resolvedAgentId != null) 'resolvedAgentId': resolvedAgentId,
        if (resolvedAgentName != null) 'resolvedAgentName': resolvedAgentName,
        if (resolvedProvider != null) 'resolvedProvider': resolvedProvider,
        if (resolvedModel != null) 'resolvedModel': resolvedModel,
        if (routingDecision != null) 'routingDecision': routingDecision,
        if (summary != null) 'summary': summary,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };
}

/// A scheduled or manually triggered Ghost Automation.
class Automation {
  const Automation({
    required this.id,
    required this.title,
    required this.instructions,
    required this.schedule,
    this.enabled = true,
    this.agentId = autoAgentId,
    this.agentName,
    this.providerOverride,
    this.modelOverride,
    required this.createdAt,
    required this.updatedAt,
    this.lastRunAt,
    this.lastRunStatus,
    this.lastRunId,
    this.lastSessionId,
    this.lastRoutingMetadata,
  });

  /// Sentinel agent ID requesting ontology-based automatic routing.
  static const String autoAgentId = 'auto';

  factory Automation.fromJson(Map<String, dynamic> json) {
    final lastStatusName = json['lastRunStatus'] as String?;
    final lastStatus = lastStatusName != null
        ? AutomationRunStatus.values
            .where((s) => s.name == lastStatusName)
            .firstOrNull
        : null;

    return Automation(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled Automation',
      instructions: json['instructions'] as String? ?? '',
      schedule: json['schedule'] is Map<String, dynamic>
          ? AutomationSchedule.fromJson(
              json['schedule'] as Map<String, dynamic>,
            )
          : (json['schedule'] is Map
              ? AutomationSchedule.fromJson(
                  Map<String, dynamic>.from(json['schedule'] as Map),
                )
              : const AutomationSchedule()),
      enabled: json['enabled'] as bool? ?? true,
      agentId: (json['agentId'] as String?)?.trim().isNotEmpty == true
          ? (json['agentId'] as String).trim()
          : autoAgentId,
      agentName: json['agentName'] as String?,
      providerOverride: (json['providerOverride'] as String?)?.isNotEmpty == true
          ? json['providerOverride'] as String
          : null,
      modelOverride: (json['modelOverride'] as String?)?.isNotEmpty == true
          ? json['modelOverride'] as String
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
      lastRunAt: json['lastRunAt'] != null
          ? DateTime.tryParse(json['lastRunAt'] as String)
          : null,
      lastRunStatus: lastStatus,
      lastRunId: json['lastRunId'] as String?,
      lastSessionId: json['lastSessionId'] as String?,
      lastRoutingMetadata: json['lastRoutingMetadata'] is Map<String, dynamic>
          ? json['lastRoutingMetadata'] as Map<String, dynamic>
          : (json['lastRoutingMetadata'] is Map
              ? Map<String, dynamic>.from(json['lastRoutingMetadata'] as Map)
              : null),
    );
  }

  final String id;
  final String title;
  final String instructions;
  final AutomationSchedule schedule;
  final bool enabled;
  final String agentId;
  final String? agentName;
  final String? providerOverride;
  final String? modelOverride;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastRunAt;
  final AutomationRunStatus? lastRunStatus;
  final String? lastRunId;
  final String? lastSessionId;
  final Map<String, dynamic>? lastRoutingMetadata;

  bool get isAutoRouting => agentId == autoAgentId;

  Automation copyWith({
    String? title,
    String? instructions,
    AutomationSchedule? schedule,
    bool? enabled,
    String? agentId,
    String? agentName,
    bool clearAgentName = false,
    String? providerOverride,
    bool clearProviderOverride = false,
    String? modelOverride,
    bool clearModelOverride = false,
    DateTime? updatedAt,
    DateTime? lastRunAt,
    AutomationRunStatus? lastRunStatus,
    String? lastRunId,
    String? lastSessionId,
    Map<String, dynamic>? lastRoutingMetadata,
  }) {
    return Automation(
      id: id,
      title: title ?? this.title,
      instructions: instructions ?? this.instructions,
      schedule: schedule ?? this.schedule,
      enabled: enabled ?? this.enabled,
      agentId: agentId ?? this.agentId,
      agentName: clearAgentName ? null : (agentName ?? this.agentName),
      providerOverride: clearProviderOverride
          ? null
          : (providerOverride ?? this.providerOverride),
      modelOverride:
          clearModelOverride ? null : (modelOverride ?? this.modelOverride),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastRunStatus: lastRunStatus ?? this.lastRunStatus,
      lastRunId: lastRunId ?? this.lastRunId,
      lastSessionId: lastSessionId ?? this.lastSessionId,
      lastRoutingMetadata: lastRoutingMetadata ?? this.lastRoutingMetadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'instructions': instructions,
        'schedule': schedule.toJson(),
        'enabled': enabled,
        'agentId': agentId,
        if (agentName != null) 'agentName': agentName,
        if (providerOverride != null) 'providerOverride': providerOverride,
        if (modelOverride != null) 'modelOverride': modelOverride,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
        if (lastRunStatus != null) 'lastRunStatus': lastRunStatus!.name,
        if (lastRunId != null) 'lastRunId': lastRunId,
        if (lastSessionId != null) 'lastSessionId': lastSessionId,
        if (lastRoutingMetadata != null)
          'lastRoutingMetadata': lastRoutingMetadata,
      };

  @override
  String toString() => jsonEncode(toJson());
}
