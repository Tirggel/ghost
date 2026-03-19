import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepTelegram extends ConsumerWidget {
  final SetupWizardState state;
  final TextEditingController tgTokenController;

  const WizardStepTelegram({
    super.key,
    required this.state,
    required this.tgTokenController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(setupWizardProvider.notifier);

    return WizardStepBase(
      icon: Icons.send,
      title: 'wizard.step_telegram'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.identName.isNotEmpty)
            WizardSummaryBadge(
              label: state.identName,
            ),
          const SizedBox(height: 16),
          AppFormLabel('settings.channels.tg_token_label'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      notifier.verifyTelegram();
                    }
                  },
                  child: TextField(
                    controller: tgTokenController,
                    obscureText: true,
                    decoration: AppInputDecoration.compact(
                      hint: 'wizard.telegram_optional',
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: notifier.updateTgToken,
                    onSubmitted: (_) => notifier.verifyTelegram(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (state.verifyingTg)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () => notifier.verifyTelegram(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: state.tgVerified
                        ? AppColors.success
                        : AppColors.primary,
                    foregroundColor: AppColors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.buttonBorderRadius,
                      ),
                    ),
                  ),
                  child: Text(
                    state.tgVerified
                        ? 'wizard.key_verified'.tr()
                        : 'wizard.verify_key'.tr(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (state.tgError != null) ...[
            const SizedBox(height: 6),
            Text(
              state.tgError!,
              style: const TextStyle(color: AppColors.errorDark, fontSize: 12),
            ),
          ],
          if (state.tgVerified) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'wizard.telegram_verified'.tr(),
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
