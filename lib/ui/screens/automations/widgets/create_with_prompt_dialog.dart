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

/// Two-step AI wizard ("+ Create with Prompt") that drafts title, schedule,
/// ontology agent assignment, and structured instructions from a short prompt.
class CreateWithPromptDialog extends ConsumerStatefulWidget {
  const CreateWithPromptDialog({super.key});

  @override
  ConsumerState<CreateWithPromptDialog> createState() =>
      _CreateWithPromptDialogState();
}

class _CreateWithPromptDialogState
    extends ConsumerState<CreateWithPromptDialog> {
  final _promptCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();

  bool _hasDraft = false;
  bool _generating = false;
  bool _saving = false;

  AutomationSchedule _schedule = const AutomationSchedule();
  String _agentId = Automation.autoAgentId;
  Map<String, dynamic>? _routingPreview;

  @override
  void dispose() {
    _promptCtrl.dispose();
    _titleCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      AppSnackBar.showError(context, 'automations.error_prompt_required'.tr());
      return;
    }

    setState(() => _generating = true);
    try {
      final locale = context.locale.languageCode;
      final draft = await ref
          .read(automationsProvider.notifier)
          .generateFromPrompt(prompt, locale: locale);
      if (!mounted) return;

      _titleCtrl.text = (draft['title'] as String?) ?? '';
      _instructionsCtrl.text = (draft['instructions'] as String?) ?? '';
      final rawSchedule = draft['schedule'];
      if (rawSchedule is Map) {
        _schedule = AutomationSchedule.fromJson(
          Map<String, dynamic>.from(rawSchedule),
        );
      }
      _agentId = (draft['agentId'] as String?) ?? Automation.autoAgentId;
      _routingPreview = draft['routingPreview'] is Map
          ? Map<String, dynamic>.from(draft['routingPreview'] as Map)
          : null;

      setState(() {
        _hasDraft = true;
        _generating = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        AppSnackBar.showError(context, e.toString());
      }
    }
  }

  Future<void> _refreshRoutingPreview() async {
    if (_agentId != Automation.autoAgentId) {
      setState(() => _routingPreview = null);
      return;
    }
    final decision = await ref
        .read(automationsProvider.notifier)
        .previewRouting(
          title: _titleCtrl.text.trim(),
          instructions: _instructionsCtrl.text.trim(),
        );
    if (mounted) {
      setState(() => _routingPreview = decision);
    }
  }

  Future<void> _create() async {
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

    return Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
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
                      Icons.auto_awesome_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'automations.prompt_wizard_title'.tr().toUpperCase(),
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
                  child: !_hasDraft
                      ? _buildPromptStep()
                      : _buildReviewStep(config, customAgents),
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
                    if (_hasDraft) ...[
                      AppActionButton(
                        label: 'automations.back_to_prompt',
                        isPrimary: false,
                        onPressed: _saving || _generating
                            ? null
                            : () => setState(() => _hasDraft = false),
                      ),
                      const SizedBox(width: 12),
                      AppActionButton(
                        label: 'automations.regenerate',
                        icon: Icons.refresh,
                        isPrimary: false,
                        isLoading: _generating,
                        onPressed: _saving ? null : _generate,
                      ),
                      const SizedBox(width: 12),
                      AppSaveButton(
                        label: 'automations.create_button',
                        icon: Icons.check,
                        isLoading: _saving,
                        onPressed: _generating ? null : _create,
                      ),
                    ] else ...[
                      AppActionButton(
                        label: 'common.cancel',
                        isPrimary: false,
                        onPressed: _generating
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      AppSaveButton(
                        label: 'automations.generate_button',
                        icon: Icons.auto_awesome,
                        isLoading: _generating,
                        onPressed: _generate,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptStep() {
    final examples = [
      'automations.prompt_example_1'.tr(),
      'automations.prompt_example_2'.tr(),
      'automations.prompt_example_3'.tr(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'automations.prompt_wizard_desc'.tr(),
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: AppConstants.fontSizeBody,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        AppFormField.text(
          controller: _promptCtrl,
          label: 'automations.prompt_input_label',
          hint: 'automations.prompt_input_hint',
          maxLines: 5,
        ),
        const SizedBox(height: 8),
        const AppFormLabel('automations.prompt_examples_label'),
        const SizedBox(height: 8),
        ...examples.map(
          (example) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppHoverCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onTap: () => setState(() => _promptCtrl.text = example),
              child: Row(
                children: [
                  const Icon(
                    Icons.north_west,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      example,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeSmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep(AppConfig config, List<CustomAgentConfig> customAgents) {
    final matchedAgentName =
        _routingPreview?['selectedAgentName'] as String?;
    final matchedReason = _routingPreview?['reason'] as String?;

    return Column(
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
            if (val != null) {
              setState(() => _agentId = val);
              _refreshRoutingPreview();
            }
          },
        ),
        if (_agentId == Automation.autoAgentId && matchedAgentName != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
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
                    '${'automations.ontology_predicted_agent'.tr(namedArgs: {'agent': matchedAgentName})}'
                    '${matchedReason != null ? ' — $matchedReason' : ''}',
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
        const SizedBox(height: AppConstants.settingsElementSpacing),
        AppFormField.text(
          controller: _instructionsCtrl,
          label: 'automations.field_instructions',
          hint: 'automations.field_instructions_hint',
          maxLines: 6,
        ),
      ],
    );
  }
}
