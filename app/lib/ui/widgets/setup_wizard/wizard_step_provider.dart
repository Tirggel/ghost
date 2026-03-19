import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import '../searchable_model_picker.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepProvider extends ConsumerWidget {
  final SetupWizardState state;
  final TextEditingController apiKeyController;

  const WizardStepProvider({
    super.key,
    required this.state,
    required this.apiKeyController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = AppConstants.aiProviders;
    final notifier = ref.read(setupWizardProvider.notifier);

    return WizardStepBase(
      icon: Icons.smart_toy,
      iconColor: AppColors.white,
      title: 'wizard.step_provider'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppDropdownField<String>(
            value: state.selectedProvider,
            hint: 'settings.identity.choose_provider',
            items: providers.map((p) => p['id']!).toList(),
            displayValue: (id) =>
                providers.firstWhere((p) => p['id'] == id)['label']!,
            itemBuilder: (id) {
              final p = providers.firstWhere((p) => p['id'] == id);
              return WizardDropdownItem(
                label: p['label']!,
                iconPath: 'assets/icons/llm/${p['icon']}',
              );
            },
            selectedItemBuilder: (BuildContext context) {
              return providers.map((p) {
                return WizardDropdownItem(
                  label: p['label']!,
                  iconPath: 'assets/icons/llm/${p['icon']}',
                  isSelected: true,
                );
              }).toList();
            },
            onChanged: (val) {
              notifier.updateProvider(val);
              apiKeyController.clear();
            },
          ),
          if (state.selectedProvider == 'ollama') ...[
            const SizedBox(height: 16),
            WizardInfoCard(text: 'wizard.ollama_no_key'.tr()),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: state.loadingModels
                  ? null
                  : () => notifier.fetchOllamaModels(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('wizard.fetch_models'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonBorderRadius,
                  ),
                ),
              ),
            ),
          ] else if (state.selectedProvider != null) ...[
            const SizedBox(height: 16),
            WizardVerificationField(
              controller: apiKeyController,
              label: 'wizard.api_key_label',
              hint: 'wizard.api_key_hint',
              isVerifying: state.verifyingKey,
              isVerified: state.keyVerified,
              error: state.keyError,
              onVerify: notifier.verifyKey,
              onChanged: notifier.updateApiKey,
            ),
          ],
          if (state.keyVerified) ...[
            const SizedBox(height: 16),
            AppFormLabel('wizard.model_label'),
            const SizedBox(height: 6),
            if (state.loadingModels)
              const Center(child: CircularProgressIndicator())
            else
              SearchableModelPicker(
                selectedModel: state.selectedModel,
                models: state.models,
                label: 'wizard.model_label',
                hint: 'settings.identity.choose_model',
                onSelected: notifier.updateSelectedModel,
              ),
          ],
        ],
      ),
    );
  }
}
