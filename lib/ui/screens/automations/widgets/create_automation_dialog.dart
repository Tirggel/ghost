import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants.dart';
import '../../../../engine/automations/automation_models.dart';
import '../../../../engine/automations/cron_utils.dart';
import '../../../../providers/automations_provider.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_styles.dart';
import 'schedule_picker_widget.dart';

/// Manual creation modal for a new Automation ("+ New").
class CreateAutomationDialog extends ConsumerStatefulWidget {
  const CreateAutomationDialog({super.key});

  @override
  ConsumerState<CreateAutomationDialog> createState() =>
      _CreateAutomationDialogState();
}

class _CreateAutomationDialogState
    extends ConsumerState<CreateAutomationDialog> {
  final _titleCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  AutomationSchedule _schedule = const AutomationSchedule(
    mode: AutomationScheduleMode.weekdays,
    times: ['08:15', '17:15'],
    daysOfWeek: [1, 2, 3, 4, 5],
  );
  String _agentId = Automation.autoAgentId;
  String? _providerOverride;
  String? _modelOverride;
  List<String> _availableModels = [];
  bool _loadingModels = false;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadModels(String provider) async {
    setState(() {
      _loadingModels = true;
      _availableModels = [];
    });
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

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      AppSnackBar.showError(context, 'automations.error_title_required'.tr());
      return;
    }
    final err = CronUtils.validateSchedule(_schedule);
    if (err != null) {
      AppSnackBar.showError(context, err);
      return;
    }

    setState(() => _saving = true);
    try {
      final created = await ref.read(automationsProvider.notifier).create(
            title: title,
            instructions: _instructionsCtrl.text.trim(),
            schedule: _schedule,
            agentId: _agentId,
            providerOverride: _providerOverride,
            modelOverride: _modelOverride,
          );
      if (mounted) {
        Navigator.of(context).pop(created.automation.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnackBar.showError(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final customAgents = config.customAgents.where((a) => a.enabled).toList();
    final configuredProviders = _configuredProviders(config);

    return Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'automations.create_title'.tr().toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: AppConstants.fontSizeTitle,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textDim,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppFormField.text(
                        controller: _titleCtrl,
                        label: 'automations.field_title',
                        hint: 'automations.field_title_hint',
                      ),

                      const AppFormLabel('automations.field_schedule'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: AppColors.surface,
                        child: SchedulePickerWidget(
                          schedule: _schedule,
                          onChanged: (next) => setState(() => _schedule = next),
                        ),
                      ),
                      const SizedBox(height: AppConstants.settingsElementSpacing),

                      // Agent selection
                      const AppFormLabel('automations.field_agent'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _agentId,
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
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text('🤖 ${a.name}'),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _agentId = val);
                        },
                      ),
                      const SizedBox(height: AppConstants.settingsElementSpacing),

                      // Optional model override
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const AppFormLabel(
                                  'automations.field_provider_override',
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String?>(
                                  initialValue: _providerOverride,
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
                                        style: const TextStyle(
                                          color: AppColors.textDim,
                                        ),
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
                                      _providerOverride = val;
                                      _modelOverride = null;
                                      _availableModels = [];
                                    });
                                    if (val != null) {
                                      _loadModels(val);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const AppFormLabel(
                                  'automations.field_model_override',
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String?>(
                                  initialValue:
                                      _availableModels.contains(_modelOverride)
                                          ? _modelOverride
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
                                            : 'automations.use_agent_default'
                                                .tr(),
                                        style: const TextStyle(
                                          color: AppColors.textDim,
                                        ),
                                      ),
                                    ),
                                    ..._availableModels.map(
                                      (m) => DropdownMenuItem<String?>(
                                        value: m,
                                        child: Text(
                                          m,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: _providerOverride == null
                                      ? null
                                      : (val) =>
                                          setState(() => _modelOverride = val),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.settingsElementSpacing),

                      // Instructions
                      AppFormField.text(
                        controller: _instructionsCtrl,
                        label: 'automations.field_instructions',
                        hint: 'automations.field_instructions_hint',
                        maxLines: 6,
                      ),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppActionButton(
                      label: 'common.cancel',
                      isPrimary: false,
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    AppSaveButton(
                      label: 'automations.create_button',
                      icon: Icons.check,
                      isLoading: _saving,
                      onPressed: _submit,
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

  List<Map<String, String>> _configuredProviders(AppConfig config) {
    final vaultKeys = config.vaultKeys;
    return AppConstants.aiProviders.where((p) {
      final id = p['id']!;
      if (id == _providerOverride) return true;
      final isLocal = AppConstants.isLocalProvider(id);
      final key = isLocal ? '${id}_base_url' : '${id}_api_key';
      return vaultKeys.contains(key) ||
          config.detectedLocalProviders.any((dp) => dp['id'] == id);
    }).toList();
  }
}
