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

  const WizardStepProvider({
    super.key,
    required this.state,
    required this.apiKeyController,
  });
  final SetupWizardState state;
  final TextEditingController apiKeyController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const providers = AppConstants.aiProviders;
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
            displayValue: (id) => AppConstants.getProviderLabel(id),
            itemBuilder: (id) {
              return WizardDropdownItem(
                label: AppConstants.getProviderLabel(id),
                iconPath: AppConstants.getProviderIcon(id),
              );
            },
            selectedItemBuilder: (BuildContext context) {
              return providers.map((p) {
                final id = p['id']!;
                return WizardDropdownItem(
                  label: AppConstants.getProviderLabel(id),
                  iconPath: AppConstants.getProviderIcon(id),
                  isSelected: true,
                );
              }).toList();
            },
            onChanged: (val) {
              notifier.updateProvider(val);
            },
          ),
          if (state.isLocalProvider) ...[
            const SizedBox(height: 16),
            WizardVerificationField(
              controller: apiKeyController,
              label: 'settings.api_keys.base_url_label',
              hint: 'settings.api_keys.base_url_hint',
              isVerifying: state.loadingModels,
              isVerified: state.keyVerified,
              error: state.keyError,
              onVerify: () =>
                  notifier.fetchLocalModels(state.selectedProvider!),
              onChanged: notifier.updateApiKey,
              obscureText: false,
              verifyLabel: 'wizard.verify_url'.tr(),
            ),
            if (state.keyVerified) ...[
              const SizedBox(height: 12),
              WizardStatusCard(
                text: 'settings.api_keys.detected_url'.tr(),
                status: WizardStatus.success,
              ),
            ],
            if (state.keyError != null) ...[
              const SizedBox(height: 12),
              WizardStatusCard(
                text: 'settings.api_keys.detection_failed'.tr(),
                status: WizardStatus.error,
              ),
            ],
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
            if (state.keyError != null) ...[
              const SizedBox(height: 12),
              WizardStatusCard(
                text:
                    state.keyError!.toLowerCase().contains('401') ||
                        state.keyError!.toLowerCase().contains('invalid')
                    ? 'errors.invalid_key_simple'.tr()
                    : state.keyError!,
                status: WizardStatus.error,
              ),
            ],
          ],
          if (state.keyVerified) ...[
            const SizedBox(height: 16),
            const AppFormLabel('wizard.model_label'),
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
                providerId: state.selectedProvider,
                loading: state.verifyingKey || state.loadingModels,
              ),
          ],
        ],
      ),
    );
  }
}
