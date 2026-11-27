import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../engine/automations/automation_models.dart';
import '../../../engine/automations/cron_utils.dart';
import '../../../providers/automations_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/gateway_provider.dart';
import '../../../providers/shell_provider.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_styles.dart';
import 'automations_overview.dart';
import 'widgets/schedule_picker_widget.dart';

/// Dedicated Detail View for a single Automation:
/// - Header: inline-editable Title, Active switch, Run Now, Delete
/// - Settings card: SchedulePicker + Agent selector (incl. Auto Ontology) + Model override
/// - Instructions card: collapsible viewer + inline Edit/Save/Cancel
/// - Runs history card: chronological run list; tap opens the full Chat transcript
class AutomationDetailView extends ConsumerStatefulWidget {
  const AutomationDetailView({super.key, required this.automationId});

  final String automationId;

  @override
  ConsumerState<AutomationDetailView> createState() =>
      _AutomationDetailViewState();
}

class _AutomationDetailViewState extends ConsumerState<AutomationDetailView> {
  // Title inline editing
  bool _editingTitle = false;
  late TextEditingController _titleCtrl;

  // Settings form state
  String? _syncedAutomationId;
  DateTime? _syncedUpdatedAt;
  late AutomationSchedule _draftSchedule;
  late String _draftAgentId;
  String? _draftProviderOverride;
  String? _draftModelOverride;
  bool _settingsDirty = false;
  bool _savingSettings = false;
  List<String> _availableModels = [];
  bool _loadingModels = false;
  Map<String, dynamic>? _routingPreview;

  // Instructions inline editing & collapse
  bool _instructionsExpanded = false;
  bool _editingInstructions = false;
  bool _savingInstructions = false;
  late TextEditingController _instructionsCtrl;

  bool _startingRun = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _instructionsCtrl = TextEditingController();
    _draftSchedule = const AutomationSchedule();
    _draftAgentId = Automation.autoAgentId;

    Future.microtask(() {
      ref.read(automationsProvider.notifier).loadDetail(widget.automationId);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  void _syncFromAutomation(Automation a) {
    if (_syncedAutomationId == a.id && _syncedUpdatedAt == a.updatedAt) {
      return;
    }
    _syncedAutomationId = a.id;
    _syncedUpdatedAt = a.updatedAt;

    if (!_editingTitle) {
      _titleCtrl.text = a.title;
    }
    if (!_editingInstructions) {
      _instructionsCtrl.text = a.instructions;
    }
    if (!_settingsDirty) {
      _draftSchedule = a.schedule;
      _draftAgentId = a.agentId;
      _draftProviderOverride = a.providerOverride;
      _draftModelOverride = a.modelOverride;
      if (_draftProviderOverride != null) {
        _loadModels(_draftProviderOverride!);
      } else {
        _availableModels = [];
      }
    }
    if (_draftAgentId == Automation.autoAgentId) {
      Future.microtask(() => _refreshRoutingPreview(a.title, a.instructions));
    }
  }

  Future<void> _loadModels(String provider) async {
    setState(() => _loadingModels = true);
    try {
      final models =
          await ref.read(configProvider.notifier).listModels(provider, null);
      if (mounted) {
        setState(() {
          _availableModels = models;
          _loadingModels = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _refreshRoutingPreview(String title, String instructions) async {
    final decision = await ref
        .read(automationsProvider.notifier)
        .previewRouting(title: title, instructions: instructions);
    if (mounted) {
      setState(() => _routingPreview = decision);
    }
  }

  Future<void> _saveTitle(Automation a) async {
    final nextTitle = _titleCtrl.text.trim();
    if (nextTitle.isEmpty) {
      AppSnackBar.showError(context, 'automations.error_title_required'.tr());
      return;
    }
    setState(() => _editingTitle = false);
    if (nextTitle == a.title) return;
    try {
      await ref
          .read(automationsProvider.notifier)
          .update(a.id, title: nextTitle);
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, e.toString());
    }
  }

  Future<void> _saveSettings(Automation a) async {
    final err = CronUtils.validateSchedule(_draftSchedule);
    if (err != null) {
      AppSnackBar.showError(context, err);
      return;
    }
    setState(() => _savingSettings = true);
    try {
      await ref.read(automationsProvider.notifier).update(
            a.id,
            schedule: _draftSchedule,
            agentId: _draftAgentId,
            providerOverride: _draftProviderOverride,
            clearProviderOverride: _draftProviderOverride == null,
            modelOverride: _draftModelOverride,
            clearModelOverride: _draftModelOverride == null,
          );
      if (mounted) {
        setState(() {
          _settingsDirty = false;
          _savingSettings = false;
        });
        AppSnackBar.showSuccess(context, 'automations.settings_saved'.tr());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingSettings = false);
        AppSnackBar.showError(context, e.toString());
      }
    }
  }

  void _cancelSettings(Automation a) {
    setState(() {
      _draftSchedule = a.schedule;
      _draftAgentId = a.agentId;
      _draftProviderOverride = a.providerOverride;
      _draftModelOverride = a.modelOverride;
      _settingsDirty = false;
    });
    if (a.providerOverride != null) {
      _loadModels(a.providerOverride!);
    }
  }

  Future<void> _saveInstructions(Automation a) async {
    setState(() => _savingInstructions = true);
    try {
      await ref
          .read(automationsProvider.notifier)
          .update(a.id, instructions: _instructionsCtrl.text.trim());
      if (mounted) {
        setState(() {
          _editingInstructions = false;
          _savingInstructions = false;
        });
        AppSnackBar.showSuccess(
          context,
          'automations.instructions_saved'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingInstructions = false);
        AppSnackBar.showError(context, e.toString());
      }
    }
  }

  Future<void> _runNow(Automation a) async {
    setState(() => _startingRun = true);
    try {
      await ref.read(automationsProvider.notifier).runNow(a.id);
      if (mounted) {
        setState(() => _startingRun = false);
        AppSnackBar.showSuccess(context, 'automations.run_started'.tr());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _startingRun = false);
        AppSnackBar.showError(context, e.toString());
      }
    }
  }

  Future<void> _deleteAutomation(Automation a) async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'automations.delete_confirm_title'.tr(),
      content: 'automations.delete_confirm_msg'
          .tr(namedArgs: {'title': a.title}),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );
    if (confirmed == true) {
      try {
        await ref.read(automationsProvider.notifier).delete(a.id);
        if (mounted) {
          AppSnackBar.showSuccess(context, 'automations.deleted'.tr());
        }
      } catch (e) {
        if (mounted) AppSnackBar.showError(context, e.toString());
      }
    }
  }

  Future<void> _openRunTranscript(AutomationRun run) async {
    ref.read(chatProvider.notifier).initSession(run.sessionId);
    await ref.read(sessionsProvider.notifier).refresh();
    if (mounted) {
      ref.read(shellProvider.notifier).openSession(run.sessionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale;
    final state = ref.watch(automationsProvider);
    final item = state.items
        .where((i) => i.automation.id == widget.automationId)
        .firstOrNull;

    if (item == null) {
      return Container(
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              AppActionButton(
                label: 'automations.back_to_list',
                isPrimary: false,
                onPressed: () => ref
                    .read(selectedAutomationIdProvider.notifier)
                    .select(null),
              ),
            ],
          ),
        ),
      );
    }

    final automation = item.automation;
    _syncFromAutomation(automation);

    final runs = state.runsByAutomation[automation.id] ?? const [];
    final isRunning = item.isRunning || _startingRun;
    final config = ref.watch(configProvider);
    final localeCode = context.locale.languageCode;

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Header bar
          _buildHeader(automation, isRunning),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Settings Card
                      _buildSettingsCard(automation, config),
                      const SizedBox(height: AppConstants.settingsSectionSpacing),

                      // Instructions Section
                      _buildInstructionsCard(automation),
                      const SizedBox(height: AppConstants.settingsSectionSpacing),

                      // Runs History
                      _buildRunsCard(runs, localeCode),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Automation a, bool isRunning) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.textMain,
              size: 20,
            ),
            tooltip: 'automations.back_to_list'.tr(),
            onPressed: () =>
                ref.read(selectedAutomationIdProvider.notifier).select(null),
          ),
          const SizedBox(width: 8),

          // Editable title
          Expanded(
            child: _editingTitle
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleCtrl,
                          autofocus: true,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: AppConstants.fontSizeTitle,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: AppInputDecoration.compact(),
                          onSubmitted: (_) => _saveTitle(a),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.check,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        onPressed: () => _saveTitle(a),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textDim,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _titleCtrl.text = a.title;
                            _editingTitle = false;
                          });
                        },
                      ),
                    ],
                  )
                : InkWell(
                    onTap: () => setState(() => _editingTitle = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              a.title,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: AppConstants.fontSizeHeading,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: AppColors.textDim,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          const SizedBox(width: 16),

          // Status label + Active switch
          Text(
            (a.enabled ? 'automations.status_active' : 'automations.status_paused')
                .tr()
                .toUpperCase(),
            style: TextStyle(
              color: a.enabled ? AppColors.textMain : AppColors.textDim,
              fontSize: AppConstants.fontSizeLabelTiny,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 8),
          AppSwitch(
            value: a.enabled,
            onChanged: (val) async {
              try {
                await ref
                    .read(automationsProvider.notifier)
                    .toggle(a.id, val);
              } catch (e) {
                if (mounted) AppSnackBar.showError(context, e.toString());
              }
            },
          ),
          const SizedBox(width: 16),

          // Run Now button
          AppActionButton(
            label: 'automations.run_now',
            icon: Icons.play_arrow_rounded,
            isPrimary: true,
            isLoading: isRunning,
            onPressed: isRunning ? null : () => _runNow(a),
          ),
          const SizedBox(width: 8),

          // Delete button
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
              size: 20,
            ),
            tooltip: 'common.delete'.tr(),
            onPressed: () => _deleteAutomation(a),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(Automation a, AppConfig config) {
    final customAgents = config.customAgents.where((c) => c.enabled).toList();
    final configuredProviders = _configuredProviders(config);
    final predictedAgent =
        _routingPreview?['selectedAgentName'] as String?;
    final predictedReason = _routingPreview?['reason'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppSectionHeader('automations.settings_section'),
              const Spacer(),
              if (_settingsDirty) ...[
                AppActionButton(
                  label: 'common.cancel',
                  isPrimary: false,
                  onPressed:
                      _savingSettings ? null : () => _cancelSettings(a),
                ),
                const SizedBox(width: 8),
                AppSaveButton(
                  label: 'common.save',
                  isLoading: _savingSettings,
                  onPressed: () => _saveSettings(a),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Schedule Picker
          const AppFormLabel('automations.field_schedule'),
          const SizedBox(height: 8),
          SchedulePickerWidget(
            schedule: _draftSchedule,
            onChanged: (next) {
              setState(() {
                _draftSchedule = next;
                _settingsDirty = true;
              });
            },
          ),
          const SizedBox(height: AppConstants.settingsContentSpacing),

          // Agent & Model Override row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.field_agent'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _validAgentValue(_draftAgentId, customAgents),
                      decoration: AppInputDecoration.compact(),
                      dropdownColor: AppColors.surface,
                      isExpanded: true,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: Automation.autoAgentId,
                          child: Text(
                            '🧭 ${'automations.auto_ontology'.tr()}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'default-agent',
                          child: Text('👻 ${config.identity.name}'),
                        ),
                        ...customAgents.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('🤖 ${c.name}'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _draftAgentId = val;
                            _settingsDirty = true;
                          });
                          if (val == Automation.autoAgentId) {
                            _refreshRoutingPreview(a.title, a.instructions);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.field_provider_override'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: configuredProviders
                              .any((p) => p['id'] == _draftProviderOverride)
                          ? _draftProviderOverride
                          : null,
                      decoration: AppInputDecoration.compact(),
                      dropdownColor: AppColors.surface,
                      isExpanded: true,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'automations.use_agent_default'.tr(),
                            style: const TextStyle(color: AppColors.textDim),
                          ),
                        ),
                        ...configuredProviders.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p['id'],
                            child: Text(p['label'] ?? p['id']!),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _draftProviderOverride = val;
                          _draftModelOverride = null;
                          _availableModels = [];
                          _settingsDirty = true;
                        });
                        if (val != null) {
                          _loadModels(val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('automations.field_model_override'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: _availableModels.contains(_draftModelOverride)
                          ? _draftModelOverride
                          : null,
                      decoration: AppInputDecoration.compact(),
                      dropdownColor: AppColors.surface,
                      isExpanded: true,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            _loadingModels
                                ? 'common.loading'.tr()
                                : 'automations.use_agent_default'.tr(),
                            style: const TextStyle(color: AppColors.textDim),
                          ),
                        ),
                        ..._availableModels.map(
                          (m) => DropdownMenuItem<String?>(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: _draftProviderOverride == null
                          ? null
                          : (val) {
                              setState(() {
                                _draftModelOverride = val;
                                _settingsDirty = true;
                              });
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_draftAgentId == Automation.autoAgentId &&
              predictedAgent != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hub_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${'automations.ontology_predicted_agent'.tr(namedArgs: {'agent': predictedAgent})}'
                      '${predictedReason != null ? ' — $predictedReason' : ''}',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: AppConstants.fontSizeSmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionsCard(Automation a) {
    final text = a.instructions;
    final isLong = text.split('\n').length > 6 || text.length > 340;

    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppSectionHeader('automations.instructions_section'),
              const Spacer(),
              if (!_editingInstructions) ...[
                if (isLong)
                  TextButton(
                    onPressed: () => setState(
                      () => _instructionsExpanded = !_instructionsExpanded,
                    ),
                    child: Text(
                      (_instructionsExpanded
                              ? 'automations.show_less'
                              : 'automations.show_all')
                          .tr()
                          .toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: AppConstants.fontSizeLabelTiny,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                AppActionButton(
                  label: 'common.edit',
                  icon: Icons.edit_outlined,
                  isPrimary: false,
                  onPressed: () {
                    _instructionsCtrl.text = a.instructions;
                    setState(() => _editingInstructions = true);
                  },
                ),
              ] else ...[
                AppActionButton(
                  label: 'common.cancel',
                  isPrimary: false,
                  onPressed: _savingInstructions
                      ? null
                      : () {
                          _instructionsCtrl.text = a.instructions;
                          setState(() => _editingInstructions = false);
                        },
                ),
                const SizedBox(width: 8),
                AppSaveButton(
                  label: 'common.save',
                  isLoading: _savingInstructions,
                  onPressed: () => _saveInstructions(a),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_editingInstructions)
            TextField(
              controller: _instructionsCtrl,
              maxLines: 10,
              minLines: 5,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: AppConstants.fontSizeBody,
                height: 1.5,
              ),
              decoration: AppInputDecoration.compact(
                hint: 'automations.field_instructions_hint'.tr(),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: AppColors.background,
              child: Text(
                text.isEmpty ? 'automations.no_instructions'.tr() : text,
                maxLines: _instructionsExpanded ? null : 6,
                overflow: _instructionsExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: text.isEmpty ? AppColors.textDim : AppColors.textMain,
                  fontSize: AppConstants.fontSizeBody,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRunsCard(List<AutomationRun> runs, String localeCode) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppSectionHeader('automations.runs_section'),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                color: AppColors.background,
                child: Text(
                  '${runs.length}',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: AppConstants.fontSizeLabelTiny,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (runs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: AppColors.background,
              child: Text(
                'automations.no_runs'.tr(),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: AppConstants.fontSizeBody,
                ),
              ),
            )
          else
            ...runs.map(
              (run) => _RunHistoryTile(
                run: run,
                localeCode: localeCode,
                onTap: () => _openRunTranscript(run),
              ),
            ),
        ],
      ),
    );
  }

  String _validAgentValue(String current, List<CustomAgentConfig> custom) {
    if (current == Automation.autoAgentId || current == 'default-agent') {
      return current;
    }
    if (custom.any((c) => c.id == current)) return current;
    return Automation.autoAgentId;
  }

  List<Map<String, String>> _configuredProviders(AppConfig config) {
    final vaultKeys = config.vaultKeys;
    return AppConstants.aiProviders.where((p) {
      final id = p['id']!;
      if (id == _draftProviderOverride) return true;
      final isLocal = AppConstants.isLocalProvider(id);
      final key = isLocal ? '${id}_base_url' : '${id}_api_key';
      return vaultKeys.contains(key) ||
          config.detectedLocalProviders.any((dp) => dp['id'] == id);
    }).toList();
  }
}

class _RunHistoryTile extends StatelessWidget {
  const _RunHistoryTile({
    required this.run,
    required this.localeCode,
    required this.onTap,
  });

  final AutomationRun run;
  final String localeCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusIcon = switch (run.status) {
      AutomationRunStatus.success => const Icon(
          Icons.check_circle_outline,
          size: 18,
          color: AppColors.success,
        ),
      AutomationRunStatus.failed => const Icon(
          Icons.error_outline,
          size: 18,
          color: AppColors.error,
        ),
      AutomationRunStatus.running => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      AutomationRunStatus.cancelled => const Icon(
          Icons.cancel_outlined,
          size: 18,
          color: AppColors.textDim,
        ),
    };

    final exactTime =
        DateFormat('dd.MM.yyyy HH:mm:ss', localeCode).format(run.startedAt.toLocal());
    final durationLabel = run.durationMs != null
        ? _formatDuration(run.durationMs!)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.background,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.surfaceLight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: statusIcon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              run.title,
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: AppConstants.fontSizeBody,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (run.resolvedAgentName != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              color: AppColors.surface,
                              child: Text(
                                run.resolvedAgentName!,
                                style: const TextStyle(
                                  color: AppColors.textDim,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            color: AppColors.surface,
                            child: Text(
                              (run.trigger == 'manual'
                                      ? 'automations.trigger_manual'
                                      : 'automations.trigger_scheduled')
                                  .tr()
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (run.errorMessage != null &&
                          run.errorMessage!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          run.errorMessage!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: AppConstants.fontSizeSmall,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (run.summary != null &&
                          run.summary!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          run.summary!,
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: AppConstants.fontSizeSmall,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: exactTime,
                      child: Text(
                        formatRelativePast(run.startedAt, localeCode),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: AppConstants.fontSizeSmall,
                        ),
                      ),
                    ),
                    if (durationLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        durationLabel,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: AppConstants.fontSizeLabelTiny,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    final seconds = (ms / 1000).round();
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final rem = seconds % 60;
    return '${mins}m ${rem}s';
  }
}
