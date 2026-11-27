// Ghost — Cron Validation, Next-Run Calculation & Human-Readable Formatting
// Pure Dart (no Flutter/dart:ui imports) — shared between Engine and UI.

import 'package:cron/cron.dart' as cron_pkg;

import 'automation_models.dart';

/// Parsed 5-field cron schedule (`minute hour dom month dow`) for next-run math.
class _ParsedCron {
  const _ParsedCron({
    required this.minutes,
    required this.hours,
    required this.daysOfMonth,
    required this.months,
    required this.daysOfWeek,
    required this.domRestricted,
    required this.dowRestricted,
  });

  final Set<int> minutes;
  final Set<int> hours;
  final Set<int> daysOfMonth;
  final Set<int> months;
  final Set<int> daysOfWeek; // 1=Mon..7=Sun (ISO)
  final bool domRestricted;
  final bool dowRestricted;

  bool matches(DateTime dt) {
    if (!months.contains(dt.month)) return false;
    if (!hours.contains(dt.hour)) return false;
    if (!minutes.contains(dt.minute)) return false;

    final domMatch = daysOfMonth.contains(dt.day);
    final dowMatch = daysOfWeek.contains(dt.weekday);
    if (domRestricted && dowRestricted) {
      return domMatch || dowMatch;
    }
    if (domRestricted) return domMatch;
    if (dowRestricted) return dowMatch;
    return true;
  }
}

/// Utilities for validating, parsing, formatting, and predicting cron schedules.
class CronUtils {
  const CronUtils._();

  /// Validates a 5-field Unix cron expression. Returns `null` if valid, or a
  /// concise error message if invalid.
  static String? validateCron(String expr) {
    final trimmed = expr.trim();
    if (trimmed.isEmpty) {
      return 'Cron expression cannot be empty';
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return 'Expected 5 fields (minute hour day month weekday)';
    }

    try {
      cron_pkg.Schedule.parse(trimmed);
    } catch (e) {
      return 'Invalid cron syntax: $e';
    }

    final parsed = _parseFiveFieldCron(trimmed);
    if (parsed == null) {
      return 'Unsupported cron field range';
    }
    return null;
  }

  /// Validates every compiled cron expression in [schedule].
  static String? validateSchedule(AutomationSchedule schedule) {
    if (schedule.mode == AutomationScheduleMode.custom) {
      return validateCron(schedule.customCron ?? '');
    }
    if (schedule.mode == AutomationScheduleMode.weekly &&
        schedule.daysOfWeek.isEmpty) {
      return 'Select at least one weekday';
    }
    if (schedule.mode == AutomationScheduleMode.interval) {
      final max =
          schedule.intervalUnit == AutomationIntervalUnit.hours ? 24 : 59;
      if (schedule.intervalValue < 1 || schedule.intervalValue > max) {
        return 'Interval must be between 1 and $max';
      }
    }
    if (schedule.mode == AutomationScheduleMode.hourly) {
      if (schedule.intervalValue < 1 || schedule.intervalValue > 24) {
        return 'Hourly interval must be between 1 and 24';
      }
    }
    if ((schedule.mode == AutomationScheduleMode.daily ||
            schedule.mode == AutomationScheduleMode.weekdays ||
            schedule.mode == AutomationScheduleMode.weekly) &&
        schedule.times.isEmpty) {
      return 'Select at least one execution time';
    }
    for (final raw in schedule.times) {
      if (AutomationSchedule.parseTime(raw) == null &&
          (schedule.mode == AutomationScheduleMode.daily ||
              schedule.mode == AutomationScheduleMode.weekdays ||
              schedule.mode == AutomationScheduleMode.weekly ||
              schedule.mode == AutomationScheduleMode.hourly)) {
        return 'Invalid time format "$raw" (expected HH:mm)';
      }
    }

    final exprs = schedule.toCronExpressions();
    if (exprs.isEmpty) return 'Schedule produces no cron triggers';
    for (final expr in exprs) {
      final err = validateCron(expr);
      if (err != null) return err;
    }
    return null;
  }

  /// Computes the next trigger timestamp strictly after [from] (default now).
  static DateTime? computeNextRun(
    AutomationSchedule schedule, {
    DateTime? from,
  }) {
    final runs = computeNextRuns(schedule, count: 1, from: from);
    return runs.isEmpty ? null : runs.first;
  }

  /// Computes up to [count] upcoming trigger timestamps strictly after [from].
  static List<DateTime> computeNextRuns(
    AutomationSchedule schedule, {
    int count = 3,
    DateTime? from,
  }) {
    if (count <= 0) return const [];
    final exprs = schedule.toCronExpressions();
    if (exprs.isEmpty) return const [];

    final parsedExprs = exprs
        .map(_parseFiveFieldCron)
        .whereType<_ParsedCron>()
        .toList();
    if (parsedExprs.isEmpty) return const [];

    final start = (from ?? DateTime.now()).toLocal();
    // Next minute boundary (seconds & ms zeroed)
    var cursor = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    ).add(const Duration(minutes: 1));

    // Bound search to 366 days (+1 day for leap year) so invalid combinations
    // like Feb 31 cannot hang.
    final limit = cursor.add(const Duration(days: 367));
    final results = <DateTime>[];

    while (cursor.isBefore(limit) && results.length < count) {
      // Fast-skip months that cannot match any expression
      final anyMonth = parsedExprs.any((p) => p.months.contains(cursor.month));
      if (!anyMonth) {
        cursor = DateTime(cursor.year, cursor.month + 1, 1, 0, 0);
        continue;
      }

      // Fast-skip days that cannot match any expression
      final anyDay = parsedExprs.any((p) {
        if (!p.months.contains(cursor.month)) return false;
        final domOk = !p.domRestricted || p.daysOfMonth.contains(cursor.day);
        final dowOk = !p.dowRestricted || p.daysOfWeek.contains(cursor.weekday);
        if (p.domRestricted && p.dowRestricted) {
          return p.daysOfMonth.contains(cursor.day) ||
              p.daysOfWeek.contains(cursor.weekday);
        }
        return domOk && dowOk;
      });
      if (!anyDay) {
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1, 0, 0);
        continue;
      }

      // Fast-skip hours that cannot match any expression
      final anyHour = parsedExprs.any(
        (p) => p.months.contains(cursor.month) && p.hours.contains(cursor.hour),
      );
      if (!anyHour) {
        cursor = cursor.add(const Duration(hours: 1));
        cursor = DateTime(cursor.year, cursor.month, cursor.day, cursor.hour, 0);
        continue;
      }

      if (parsedExprs.any((p) => p.matches(cursor))) {
        results.add(cursor);
      }
      cursor = cursor.add(const Duration(minutes: 1));
    }

    return results;
  }

  /// Renders a concise, human-readable summary of [schedule] in `de` or `en`.
  static String formatHumanReadable(
    AutomationSchedule schedule, {
    String locale = 'en',
  }) {
    final isDe = locale.toLowerCase().startsWith('de');

    switch (schedule.mode) {
      case AutomationScheduleMode.daily:
        final timesStr = _formatTimeList(schedule.times, isDe: isDe);
        return isDe ? 'Täglich um $timesStr' : 'Daily at $timesStr';

      case AutomationScheduleMode.weekdays:
        final timesStr = _formatTimeList(schedule.times, isDe: isDe);
        return isDe ? 'Werktags um $timesStr' : 'Weekdays at $timesStr';

      case AutomationScheduleMode.weekly:
        final days = (schedule.daysOfWeek.toSet().toList()..sort());
        final timesStr = _formatTimeList(schedule.times, isDe: isDe);
        if (days.length == 5 &&
            days[0] == 1 &&
            days[1] == 2 &&
            days[2] == 3 &&
            days[3] == 4 &&
            days[4] == 5) {
          return isDe ? 'Werktags um $timesStr' : 'Weekdays at $timesStr';
        }
        if (days.length == 7) {
          return isDe ? 'Täglich um $timesStr' : 'Daily at $timesStr';
        }
        final dayNames = days.map((d) => _dayShort(d, isDe: isDe)).join(', ');
        return isDe ? '$dayNames um $timesStr' : '$dayNames at $timesStr';

      case AutomationScheduleMode.hourly:
        final parsed = schedule.times.isNotEmpty
            ? AutomationSchedule.parseTime(schedule.times.first)
            : null;
        final minStr = (parsed?.minute ?? 0).toString().padLeft(2, '0');
        final step = schedule.intervalValue;
        if (step <= 1) {
          return isDe
              ? 'Stündlich zur Minute :$minStr'
              : 'Hourly at :$minStr';
        }
        return isDe
            ? 'Alle $step Std. um :$minStr'
            : 'Every $step hours at :$minStr';

      case AutomationScheduleMode.interval:
        final step = schedule.intervalValue;
        if (schedule.intervalUnit == AutomationIntervalUnit.hours) {
          if (step <= 1) {
            return isDe ? 'Jede Stunde' : 'Every hour';
          }
          return isDe ? 'Alle $step Stunden' : 'Every $step hours';
        }
        if (step <= 1) {
          return isDe ? 'Jede Minute' : 'Every minute';
        }
        return isDe ? 'Alle $step Minuten' : 'Every $step minutes';

      case AutomationScheduleMode.custom:
        final raw = (schedule.customCron ?? '').trim();
        if (raw.isEmpty) {
          return isDe ? 'Benutzerdefiniert' : 'Custom cron';
        }
        // Try decoding common custom crons into human text
        final inferred = tryDecodeCronToHuman(raw, locale: locale);
        if (inferred != null) return inferred;
        return 'Cron: $raw';
    }
  }

  /// Attempts to convert a standard 5-field cron into a structured
  /// [AutomationSchedule] when it matches a known preset pattern.
  static AutomationSchedule scheduleFromCron(String cron) {
    final trimmed = cron.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return AutomationSchedule(
        mode: AutomationScheduleMode.custom,
        customCron: trimmed,
      );
    }

    final minStr = parts[0];
    final hourStr = parts[1];
    final domStr = parts[2];
    final monthStr = parts[3];
    final dowStr = parts[4];

    if (domStr == '*' && monthStr == '*') {
      // Every minute / every N minutes
      if (hourStr == '*' && dowStr == '*') {
        if (minStr == '*') {
          return const AutomationSchedule(
            mode: AutomationScheduleMode.interval,
            intervalValue: 1,
          );
        }
        final stepMatch = RegExp(r'^\*/(\d+)$').firstMatch(minStr);
        if (stepMatch != null) {
          final step = int.tryParse(stepMatch.group(1)!);
          if (step != null && step >= 1 && step <= 59) {
            return AutomationSchedule(
              mode: AutomationScheduleMode.interval,
              intervalValue: step,
            );
          }
        }
      }

      // Hourly / every N hours
      final minSingle = int.tryParse(minStr);
      if (minSingle != null && minSingle >= 0 && minSingle <= 59 && dowStr == '*') {
        if (hourStr == '*') {
          if (minSingle == 0) {
            return const AutomationSchedule(
              mode: AutomationScheduleMode.interval,
              intervalValue: 1,
              intervalUnit: AutomationIntervalUnit.hours,
            );
          }
          return AutomationSchedule(
            mode: AutomationScheduleMode.hourly,
            times: [AutomationSchedule.normalizeTime(0, minSingle)],
            intervalValue: 1,
          );
        }
        final hourStep = RegExp(r'^\*/(\d+)$').firstMatch(hourStr);
        if (hourStep != null) {
          final step = int.tryParse(hourStep.group(1)!);
          if (step != null && step >= 1 && step <= 24) {
            if (minSingle == 0) {
              return AutomationSchedule(
                mode: AutomationScheduleMode.interval,
                intervalValue: step,
                intervalUnit: AutomationIntervalUnit.hours,
              );
            }
            return AutomationSchedule(
              mode: AutomationScheduleMode.hourly,
              times: [AutomationSchedule.normalizeTime(0, minSingle)],
              intervalValue: step,
            );
          }
        }
      }

      // Daily / Weekdays / Weekly with comma-separated hours & single minute
      if (minSingle != null && minSingle >= 0 && minSingle <= 59) {
        final hours = _parseIntList(hourStr, min: 0, max: 23);
        if (hours != null && hours.isNotEmpty) {
          final times = hours
              .map((h) => AutomationSchedule.normalizeTime(h, minSingle))
              .toList();
          if (dowStr == '*') {
            return AutomationSchedule(
              mode: AutomationScheduleMode.daily,
              times: times,
            );
          }
          if (dowStr == '1-5') {
            return AutomationSchedule(
              mode: AutomationScheduleMode.weekdays,
              times: times,
              daysOfWeek: const [1, 2, 3, 4, 5],
            );
          }
          final dows = _parseDowList(dowStr);
          if (dows != null && dows.isNotEmpty) {
            return AutomationSchedule(
              mode: AutomationScheduleMode.weekly,
              times: times,
              daysOfWeek: dows,
            );
          }
        }
      }
    }

    return AutomationSchedule(
      mode: AutomationScheduleMode.custom,
      customCron: trimmed,
    );
  }

  /// Decodes simple 5-field crons to human-readable text, returning `null` for
  /// complex expressions.
  static String? tryDecodeCronToHuman(String cron, {String locale = 'en'}) {
    final inferred = scheduleFromCron(cron);
    if (inferred.mode == AutomationScheduleMode.custom) return null;
    return formatHumanReadable(inferred, locale: locale);
  }

  static String _formatTimeList(List<String> times, {required bool isDe}) {
    final valid = times
        .map(AutomationSchedule.parseTime)
        .whereType<({int hour, int minute})>()
        .toList();
    if (valid.isEmpty) return '09:00';

    final formatted = valid.map((t) {
      if (isDe) {
        return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      }
      final period = t.hour >= 12 ? 'PM' : 'AM';
      final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
    }).toList();

    if (formatted.length == 1) return formatted.first;
    if (formatted.length == 2) {
      return isDe
          ? '${formatted[0]} & ${formatted[1]}'
          : '${formatted[0]} & ${formatted[1]}';
    }
    return '${formatted.sublist(0, formatted.length - 1).join(', ')} & ${formatted.last}';
  }

  static String _dayShort(int isoWeekday, {required bool isDe}) {
    const enDays = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    const deDays = {
      1: 'Mo',
      2: 'Di',
      3: 'Mi',
      4: 'Do',
      5: 'Fr',
      6: 'Sa',
      7: 'So',
    };
    return (isDe ? deDays : enDays)[isoWeekday] ?? '$isoWeekday';
  }

  static List<int>? _parseIntList(String field, {required int min, required int max}) {
    final parts = field.split(',');
    final out = <int>{};
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null || n < min || n > max) return null;
      out.add(n);
    }
    return out.toList()..sort();
  }

  static List<int>? _parseDowList(String field) {
    final values = _parseCronField(field, min: 0, max: 7);
    if (values == null) return null;
    final normalized = values.map((d) => d == 0 ? 7 : d).toSet().toList()..sort();
    return normalized;
  }

  static _ParsedCron? _parseFiveFieldCron(String expr) {
    final parts = expr.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) return null;

    final minutes = _parseCronField(parts[0], min: 0, max: 59);
    final hours = _parseCronField(parts[1], min: 0, max: 23);
    final daysOfMonth = _parseCronField(parts[2], min: 1, max: 31);
    final months = _parseCronField(parts[3], min: 1, max: 12);
    final rawDow = _parseCronField(parts[4], min: 0, max: 7);

    if (minutes == null ||
        hours == null ||
        daysOfMonth == null ||
        months == null ||
        rawDow == null) {
      return null;
    }

    final daysOfWeek = rawDow.map((d) => d == 0 ? 7 : d).toSet();

    return _ParsedCron(
      minutes: minutes,
      hours: hours,
      daysOfMonth: daysOfMonth,
      months: months,
      daysOfWeek: daysOfWeek,
      domRestricted: parts[2] != '*',
      dowRestricted: parts[4] != '*',
    );
  }

  static Set<int>? _parseCronField(
    String raw, {
    required int min,
    required int max,
  }) {
    final result = <int>{};
    for (final segment in raw.split(',')) {
      final part = segment.trim();
      if (part.isEmpty) return null;

      final stepSplit = part.split('/');
      if (stepSplit.length > 2) return null;
      final rangePart = stepSplit[0];
      final int step;
      if (stepSplit.length == 2) {
        final parsedStep = int.tryParse(stepSplit[1]);
        if (parsedStep == null || parsedStep <= 0) return null;
        step = parsedStep;
      } else {
        step = 1;
      }

      int start;
      int end;
      if (rangePart == '*') {
        start = min;
        end = max;
      } else if (rangePart.contains('-')) {
        final bounds = rangePart.split('-');
        if (bounds.length != 2) return null;
        final a = int.tryParse(bounds[0]);
        final b = int.tryParse(bounds[1]);
        if (a == null || b == null || a < min || b > max || a > b) return null;
        start = a;
        end = b;
      } else {
        final single = int.tryParse(rangePart);
        if (single == null || single < min || single > max) return null;
        if (stepSplit.length == 2) {
          start = single;
          end = max;
        } else {
          result.add(single);
          continue;
        }
      }

      for (var v = start; v <= end; v += step) {
        result.add(v);
      }
    }
    return result.isEmpty ? null : result;
  }
}
