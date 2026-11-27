import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants.dart';
import '../../../../engine/automations/automation_models.dart';
import '../../../../engine/automations/cron_utils.dart';
import '../../../widgets/app_styles.dart';

/// Reusable Monolith-styled human-readable schedule picker supporting
/// Daily, Weekdays (multi-time), Weekly, Hourly, free Interval (minutes/hours),
/// and Custom Cron with minute-exact time selection and live next-run prediction.
class SchedulePickerWidget extends StatefulWidget {
  const SchedulePickerWidget({
    super.key,
    required this.schedule,
    required this.onChanged,
  });

  final AutomationSchedule schedule;
  final ValueChanged<AutomationSchedule> onChanged;

  @override
  State<SchedulePickerWidget> createState() => _SchedulePickerWidgetState();
}

class _SchedulePickerWidgetState extends State<SchedulePickerWidget> {
  late TextEditingController _customCronCtrl;
  late TextEditingController _intervalValueCtrl;
  late TextEditingController _hourlyIntervalCtrl;
  late TextEditingController _hourlyMinuteCtrl;
  bool _showNextRuns = false;

  @override
  void initState() {
    super.initState();
    _customCronCtrl = TextEditingController(
      text: widget.schedule.customCron ??
          (widget.schedule.toCronExpressions().isNotEmpty
              ? widget.schedule.toCronExpressions().first
              : '0 9 * * *'),
    );
    _intervalValueCtrl = TextEditingController(
      text: '${widget.schedule.intervalValue}',
    );
    _hourlyIntervalCtrl = TextEditingController(
      text: '${widget.schedule.intervalValue.clamp(1, 24)}',
    );
    final parsedHourly = widget.schedule.times.isNotEmpty
        ? AutomationSchedule.parseTime(widget.schedule.times.first)
        : null;
    _hourlyMinuteCtrl = TextEditingController(
      text: (parsedHourly?.minute ?? 0).toString().padLeft(2, '0'),
    );
  }

  @override
  void didUpdateWidget(covariant SchedulePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.schedule.mode == AutomationScheduleMode.custom) {
      final expected = widget.schedule.customCron ?? '';
      if (_customCronCtrl.text != expected && expected.isNotEmpty) {
        _customCronCtrl.text = expected;
      }
    }
    if (widget.schedule.mode == AutomationScheduleMode.interval) {
      final expected = '${widget.schedule.intervalValue}';
      if (_intervalValueCtrl.text != expected &&
          int.tryParse(_intervalValueCtrl.text) !=
              widget.schedule.intervalValue) {
        _intervalValueCtrl.text = expected;
      }
    }
    if (widget.schedule.mode == AutomationScheduleMode.hourly) {
      final expectedH = '${widget.schedule.intervalValue}';
      if (_hourlyIntervalCtrl.text != expectedH &&
          int.tryParse(_hourlyIntervalCtrl.text) !=
              widget.schedule.intervalValue) {
        _hourlyIntervalCtrl.text = expectedH;
      }
      final parsedHourly = widget.schedule.times.isNotEmpty
          ? AutomationSchedule.parseTime(widget.schedule.times.first)
          : null;
      final expectedM = (parsedHourly?.minute ?? 0).toString().padLeft(2, '0');
      if (_hourlyMinuteCtrl.text != expectedM &&
          int.tryParse(_hourlyMinuteCtrl.text) != (parsedHourly?.minute ?? 0)) {
        _hourlyMinuteCtrl.text = expectedM;
      }
    }
  }

  @override
  void dispose() {
    _customCronCtrl.dispose();
    _intervalValueCtrl.dispose();
    _hourlyIntervalCtrl.dispose();
    _hourlyMinuteCtrl.dispose();
    super.dispose();
  }

  void _selectMode(AutomationScheduleMode mode) {
    if (mode == widget.schedule.mode) return;
    if (mode == AutomationScheduleMode.custom) {
      final currentExpr = widget.schedule.toCronExpressions().isNotEmpty
          ? widget.schedule.toCronExpressions().first
          : '0 9 * * *';
      _customCronCtrl.text = currentExpr;
      widget.onChanged(
        widget.schedule.copyWith(
          mode: mode,
          customCron: currentExpr,
        ),
      );
      return;
    }

    // If switching from custom back to structured, try preserving pattern if possible
    if (widget.schedule.mode == AutomationScheduleMode.custom) {
      final inferred =
          CronUtils.scheduleFromCron(widget.schedule.customCron ?? '');
      if (inferred.mode == mode) {
        _intervalValueCtrl.text = '${inferred.intervalValue}';
        _hourlyIntervalCtrl.text = '${inferred.intervalValue}';
        widget.onChanged(inferred);
        return;
      }
    }

    var nextDays = widget.schedule.daysOfWeek;
    if (mode == AutomationScheduleMode.weekdays) {
      nextDays = const [1, 2, 3, 4, 5];
    } else if (mode == AutomationScheduleMode.weekly && nextDays.isEmpty) {
      nextDays = const [1];
    }

    var nextTimes = widget.schedule.times;
    if (nextTimes.isEmpty) {
      nextTimes = const ['09:00'];
    }

    var nextInterval = widget.schedule.intervalValue;
    if (mode == AutomationScheduleMode.hourly) {
      nextInterval = nextInterval.clamp(1, 24);
      _hourlyIntervalCtrl.text = '$nextInterval';
      final parsed = AutomationSchedule.parseTime(nextTimes.first);
      _hourlyMinuteCtrl.text =
          (parsed?.minute ?? 0).toString().padLeft(2, '0');
    } else if (mode == AutomationScheduleMode.interval) {
      final maxVal =
          widget.schedule.intervalUnit == AutomationIntervalUnit.hours ? 24 : 59;
      nextInterval = nextInterval.clamp(1, maxVal);
      _intervalValueCtrl.text = '$nextInterval';
    }

    widget.onChanged(
      widget.schedule.copyWith(
        mode: mode,
        times: nextTimes,
        daysOfWeek: nextDays,
        intervalValue: nextInterval,
        clearCustomCron: true,
      ),
    );
  }

  Future<({int hour, int minute})?> _showExactTimePicker(
    BuildContext context, {
    required int initialHour,
    required int initialMinute,
  }) {
    return showDialog<({int hour, int minute})>(
      context: context,
      builder: (_) => _ExactTimePickerDialog(
        initialHour: initialHour,
        initialMinute: initialMinute,
      ),
    );
  }

  Future<void> _addTime(BuildContext context) async {
    final picked = await _showExactTimePicker(
      context,
      initialHour: 9,
      initialMinute: 0,
    );
    if (picked == null) return;
    final formatted =
        AutomationSchedule.normalizeTime(picked.hour, picked.minute);
    final updated = List<String>.from(widget.schedule.times);
    if (!updated.contains(formatted)) {
      updated.add(formatted);
      updated.sort();
      widget.onChanged(widget.schedule.copyWith(times: updated));
    }
  }

  Future<void> _editTime(BuildContext context, int index) async {
    final parsed = AutomationSchedule.parseTime(widget.schedule.times[index]);
    final picked = await _showExactTimePicker(
      context,
      initialHour: parsed?.hour ?? 9,
      initialMinute: parsed?.minute ?? 0,
    );
    if (picked == null) return;
    final formatted =
        AutomationSchedule.normalizeTime(picked.hour, picked.minute);
    final updated = List<String>.from(widget.schedule.times);
    updated[index] = formatted;
    final deduped = updated.toSet().toList()..sort();
    widget.onChanged(widget.schedule.copyWith(times: deduped));
  }

  void _removeTime(int index) {
    if (widget.schedule.times.length <= 1) return;
    final updated = List<String>.from(widget.schedule.times)..removeAt(index);
    widget.onChanged(widget.schedule.copyWith(times: updated));
  }

  void _toggleWeekday(int day) {
    final updated = List<int>.from(widget.schedule.daysOfWeek);
    if (updated.contains(day)) {
      if (updated.length <= 1) return;
      updated.remove(day);
    } else {
      updated.add(day);
      updated.sort();
    }
    widget.onChanged(widget.schedule.copyWith(daysOfWeek: updated));
  }

  void _setIntervalValue(int next, {bool updateText = false}) {
    final max =
        widget.schedule.intervalUnit == AutomationIntervalUnit.hours ? 24 : 59;
    final clamped = next.clamp(1, max);
    if (updateText) {
      _intervalValueCtrl.text = '$clamped';
    }
    widget.onChanged(widget.schedule.copyWith(intervalValue: clamped));
  }

  void _setIntervalUnit(AutomationIntervalUnit unit) {
    final max = unit == AutomationIntervalUnit.hours ? 24 : 59;
    final clamped = widget.schedule.intervalValue.clamp(1, max);
    _intervalValueCtrl.text = '$clamped';
    widget.onChanged(
      widget.schedule.copyWith(
        intervalUnit: unit,
        intervalValue: clamped,
      ),
    );
  }

  void _setHourlyInterval(int next, {bool updateText = false}) {
    final clamped = next.clamp(1, 24);
    if (updateText) {
      _hourlyIntervalCtrl.text = '$clamped';
    }
    widget.onChanged(widget.schedule.copyWith(intervalValue: clamped));
  }

  void _setHourlyMinute(int next, {bool updateText = false}) {
    final clamped = next.clamp(0, 59);
    if (updateText) {
      _hourlyMinuteCtrl.text = clamped.toString().padLeft(2, '0');
    }
    widget.onChanged(
      widget.schedule.copyWith(
        times: [AutomationSchedule.normalizeTime(0, clamped)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = context.locale.languageCode;
    final schedule = widget.schedule;
    final validationError = CronUtils.validateSchedule(schedule);
    final humanText =
        CronUtils.formatHumanReadable(schedule, locale: localeCode);
    final upcoming = validationError == null
        ? CronUtils.computeNextRuns(schedule, count: 3)
        : const <DateTime>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode tabs
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ModeTab(
              label: 'automations.schedule_daily'.tr(),
              isActive: schedule.mode == AutomationScheduleMode.daily,
              onTap: () => _selectMode(AutomationScheduleMode.daily),
            ),
            _ModeTab(
              label: 'automations.schedule_weekdays'.tr(),
              isActive: schedule.mode == AutomationScheduleMode.weekdays,
              onTap: () => _selectMode(AutomationScheduleMode.weekdays),
            ),
            _ModeTab(
              label: 'automations.schedule_weekly'.tr(),
              isActive: schedule.mode == AutomationScheduleMode.weekly,
              onTap: () => _selectMode(AutomationScheduleMode.weekly),
            ),
            _ModeTab(
              label: 'automations.schedule_hourly'.tr(),
              isActive: schedule.mode == AutomationScheduleMode.hourly,
              onTap: () => _selectMode(AutomationScheduleMode.hourly),
            ),
            _ModeTab(
              label: 'automations.schedule_interval'.tr(),
              isActive: schedule.mode == AutomationScheduleMode.interval,
              onTap: () => _selectMode(AutomationScheduleMode.interval),
            ),
            _ModeTab(
              label: 'automations.schedule_custom'.tr(),
              isActive: schedule.mode == AutomationScheduleMode.custom,
              onTap: () => _selectMode(AutomationScheduleMode.custom),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Mode-specific controls
        if (schedule.mode == AutomationScheduleMode.weekly) ...[
          const AppFormLabel('automations.weekdays_label'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(7, (idx) {
              final day = idx + 1;
              final active = schedule.daysOfWeek.contains(day);
              return GestureDetector(
                onTap: () => _toggleWeekday(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.background,
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Text(
                    _weekdayLabel(day, localeCode),
                    style: TextStyle(
                      color: active ? AppColors.black : AppColors.textDim,
                      fontSize: AppConstants.fontSizeLabelTiny,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],

        if (schedule.mode == AutomationScheduleMode.daily ||
            schedule.mode == AutomationScheduleMode.weekdays ||
            schedule.mode == AutomationScheduleMode.weekly) ...[
          const AppFormLabel('automations.times_label'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...schedule.times.asMap().entries.map((entry) {
                final idx = entry.key;
                final time = entry.value;
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _editTime(context, idx),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_outlined,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatDisplayTime(time, localeCode),
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontSize: AppConstants.fontSizeBody,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (schedule.times.length > 1)
                        InkWell(
                          onTap: () => _removeTime(idx),
                          child: const Padding(
                            padding: EdgeInsets.only(
                              right: 8,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              InkWell(
                key: const Key('add_time_button'),
                onTap: () => _addTime(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'automations.add_time'.tr(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: AppConstants.fontSizeLabelTiny,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ] else if (schedule.mode == AutomationScheduleMode.hourly) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.every_hours_label'),
                    const SizedBox(height: 6),
                    _NumericStepperField(
                      fieldKey: const Key('hourly_interval_input'),
                      controller: _hourlyIntervalCtrl,
                      min: 1,
                      max: 24,
                      suffix: 'automations.unit_hours'.tr(),
                      onChanged: (val) => _setHourlyInterval(val),
                      onStep: (delta) => _setHourlyInterval(
                        schedule.intervalValue + delta,
                        updateText: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.at_minute_label'),
                    const SizedBox(height: 6),
                    _NumericStepperField(
                      fieldKey: const Key('hourly_minute_input'),
                      controller: _hourlyMinuteCtrl,
                      min: 0,
                      max: 59,
                      padZero: true,
                      prefix: ':',
                      onChanged: (val) => _setHourlyMinute(val),
                      onStep: (delta) {
                        final parsed = schedule.times.isNotEmpty
                            ? AutomationSchedule.parseTime(schedule.times.first)
                            : null;
                        final current = parsed?.minute ?? 0;
                        _setHourlyMinute(current + delta, updateText: true);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else if (schedule.mode == AutomationScheduleMode.interval) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.interval_value_label'),
                    const SizedBox(height: 6),
                    _NumericStepperField(
                      fieldKey: const Key('interval_value_input'),
                      controller: _intervalValueCtrl,
                      min: 1,
                      max: schedule.intervalUnit == AutomationIntervalUnit.hours
                          ? 24
                          : 59,
                      onChanged: (val) => _setIntervalValue(val),
                      onStep: (delta) => _setIntervalValue(
                        schedule.intervalValue + delta,
                        updateText: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.interval_unit_label'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _UnitButton(
                            key: const Key('interval_unit_minutes'),
                            label: 'automations.unit_minutes'.tr(),
                            isActive: schedule.intervalUnit ==
                                AutomationIntervalUnit.minutes,
                            onTap: () =>
                                _setIntervalUnit(AutomationIntervalUnit.minutes),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _UnitButton(
                            key: const Key('interval_unit_hours'),
                            label: 'automations.unit_hours'.tr(),
                            isActive: schedule.intervalUnit ==
                                AutomationIntervalUnit.hours,
                            onTap: () =>
                                _setIntervalUnit(AutomationIntervalUnit.hours),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'automations.interval_range_hint'.tr(
              namedArgs: {
                'max': schedule.intervalUnit == AutomationIntervalUnit.hours
                    ? '24'
                    : '59',
              },
            ),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: AppConstants.fontSizeLabelTiny,
            ),
          ),
        ] else if (schedule.mode == AutomationScheduleMode.custom) ...[
          const AppFormLabel('automations.custom_cron_label'),
          const SizedBox(height: 6),
          TextField(
            controller: _customCronCtrl,
            style: const TextStyle(
              color: AppColors.textMain,
              fontFamily: 'monospace',
              fontSize: AppConstants.fontSizeBody,
            ),
            decoration: AppInputDecoration.compact(
              hint: '0 9 * * 1-5',
            ),
            onChanged: (val) {
              widget.onChanged(
                schedule.copyWith(
                  mode: AutomationScheduleMode.custom,
                  customCron: val.trim(),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'automations.custom_cron_hint'.tr(),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: AppConstants.fontSizeLabelTiny,
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Live preview banner (Human-Readable + Next Run)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(
              color: validationError != null
                  ? AppColors.error
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    validationError != null
                        ? Icons.error_outline
                        : Icons.event_repeat_outlined,
                    size: 16,
                    color: validationError != null
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validationError ?? humanText,
                      style: TextStyle(
                        color: validationError != null
                            ? AppColors.error
                            : AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (upcoming.length > 1)
                    InkWell(
                      onTap: () =>
                          setState(() => _showNextRuns = !_showNextRuns),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          _showNextRuns
                              ? 'automations.hide_upcoming'.tr()
                              : 'automations.show_upcoming'.tr(),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: AppConstants.fontSizeLabelTiny,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${'automations.next_run_prefix'.tr()}: ${_formatDateTime(upcoming.first, localeCode)}',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: AppConstants.fontSizeSmall,
                  ),
                ),
                if (_showNextRuns && upcoming.length > 1) ...[
                  const SizedBox(height: 4),
                  ...upcoming.skip(1).map(
                        (dt) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '• ${_formatDateTime(dt, localeCode)}',
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: AppConstants.fontSizeLabelTiny,
                            ),
                          ),
                        ),
                      ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _weekdayLabel(int day, String localeCode) {
    final isDe = localeCode.toLowerCase().startsWith('de');
    const en = {1: 'MON', 2: 'TUE', 3: 'WED', 4: 'THU', 5: 'FRI', 6: 'SAT', 7: 'SUN'};
    const de = {1: 'MO', 2: 'DI', 3: 'MI', 4: 'DO', 5: 'FR', 6: 'SA', 7: 'SO'};
    return (isDe ? de : en)[day] ?? '$day';
  }

  String _formatDisplayTime(String raw, String localeCode) {
    final parsed = AutomationSchedule.parseTime(raw);
    if (parsed == null) return raw;
    if (localeCode.toLowerCase().startsWith('de')) {
      return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    }
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    final h12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    return '$h12:${parsed.minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDateTime(DateTime dt, String localeCode) {
    return DateFormat('EEE, dd.MM.yyyy · HH:mm', localeCode).format(dt.toLocal());
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.background,
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isActive ? AppColors.black : AppColors.textDim,
            fontSize: AppConstants.fontSizeLabelTiny,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _UnitButton extends StatelessWidget {
  const _UnitButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.background,
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isActive ? AppColors.black : AppColors.textDim,
            fontSize: AppConstants.fontSizeLabelTiny,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _NumericStepperField extends StatelessWidget {
  const _NumericStepperField({
    this.fieldKey,
    required this.controller,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onStep,
    this.prefix,
    this.suffix,
    this.padZero = false,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onStep;
  final String? prefix;
  final String? suffix;
  final bool padZero;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => onStep(-1),
            child: const SizedBox(
              width: 34,
              height: 40,
              child: Icon(Icons.remove, size: 15, color: AppColors.textDim),
            ),
          ),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: const TextStyle(
                color: AppColors.textMain,
                fontFamily: 'monospace',
                fontSize: AppConstants.fontSizeBody,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                prefixText: prefix,
                prefixStyle: const TextStyle(
                  color: AppColors.textDim,
                  fontFamily: 'monospace',
                  fontSize: AppConstants.fontSizeBody,
                ),
                suffixText: suffix != null ? ' $suffix' : null,
                suffixStyle: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: AppConstants.fontSizeLabelTiny,
                ),
              ),
              onChanged: (raw) {
                final parsed = int.tryParse(raw);
                if (parsed == null) return;
                if (parsed >= min && parsed <= max) {
                  onChanged(parsed);
                }
              },
              onEditingComplete: () {
                final parsed = int.tryParse(controller.text) ?? min;
                final clamped = parsed.clamp(min, max);
                controller.text = padZero
                    ? clamped.toString().padLeft(2, '0')
                    : '$clamped';
                onChanged(clamped);
              },
            ),
          ),
          InkWell(
            onTap: () => onStep(1),
            child: const SizedBox(
              width: 34,
              height: 40,
              child: Icon(Icons.add, size: 15, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// Monolith Noir minute-exact time picker dialog (`00..23` : `00..59`).
class _ExactTimePickerDialog extends StatefulWidget {
  const _ExactTimePickerDialog({
    required this.initialHour,
    required this.initialMinute,
  });

  final int initialHour;
  final int initialMinute;

  @override
  State<_ExactTimePickerDialog> createState() => _ExactTimePickerDialogState();
}

class _ExactTimePickerDialogState extends State<_ExactTimePickerDialog> {
  late int _hour;
  late int _minute;
  late TextEditingController _hourCtrl;
  late TextEditingController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialHour.clamp(0, 23);
    _minute = widget.initialMinute.clamp(0, 59);
    _hourCtrl = TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minuteCtrl =
        TextEditingController(text: _minute.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _stepHour(int delta) {
    setState(() {
      _hour = (_hour + delta) % 24;
      if (_hour < 0) _hour += 24;
      _hourCtrl.text = _hour.toString().padLeft(2, '0');
    });
  }

  void _stepMinute(int delta) {
    setState(() {
      _minute = (_minute + delta) % 60;
      if (_minute < 0) _minute += 60;
      _minuteCtrl.text = _minute.toString().padLeft(2, '0');
    });
  }

  void _confirm() {
    final h = (int.tryParse(_hourCtrl.text) ?? _hour).clamp(0, 23);
    final m = (int.tryParse(_minuteCtrl.text) ?? _minute).clamp(0, 59);
    Navigator.of(context).pop((hour: h, minute: m));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'automations.time_picker_title'.tr().toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: AppConstants.fontSizeSubhead,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppFormLabel('automations.hour_label'),
                          const SizedBox(height: 6),
                          _NumericStepperField(
                            fieldKey: const Key('time_picker_hour'),
                            controller: _hourCtrl,
                            min: 0,
                            max: 23,
                            padZero: true,
                            onChanged: (v) => setState(() => _hour = v),
                            onStep: _stepHour,
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 20, left: 10, right: 10),
                      child: Text(
                        ':',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppFormLabel('automations.minute_label'),
                          const SizedBox(height: 6),
                          _NumericStepperField(
                            fieldKey: const Key('time_picker_minute'),
                            controller: _minuteCtrl,
                            min: 0,
                            max: 59,
                            padZero: true,
                            onChanged: (v) => setState(() => _minute = v),
                            onStep: _stepMinute,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    AppActionButton(
                      label: 'common.cancel',
                      isPrimary: false,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    AppSaveButton(
                      key: const Key('time_picker_confirm'),
                      label: 'common.save',
                      icon: Icons.check,
                      onPressed: _confirm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
