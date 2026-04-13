import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart' as fs;
import '../../../core/constants.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import '../app_snackbar.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepWorkspace extends ConsumerWidget {
  final SetupWizardState state;
  final TextEditingController workspaceController;
  const WizardStepWorkspace({
    super.key,
    required this.state,
    required this.workspaceController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(setupWizardProvider.notifier);
    return WizardStepBase(
      icon: AppConstants.folderIcon,
      iconColor: AppConstants.folderIconColor,
      title: 'wizard.step_workspace'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardStepHeader(text: 'wizard.workspace_desc'.tr()),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      notifier.updateWorkspace(workspaceController.text);
                    }
                  },
                  child: TextField(
                    controller: workspaceController,
                    onChanged: notifier.updateWorkspace,
                    onSubmitted: (val) => notifier.updateWorkspace(val),
                    decoration: AppInputDecoration.compact(
                      hint: 'wizard.workspace_hint'.tr(),
                    ).copyWith(
                      prefixIcon: const Icon(
                        AppConstants.folderIcon,
                        color: AppConstants.folderIconColor,
                        size: AppConstants.settingsIconSize,
                      ),
                    ),
                  ),
                ),
              ),
              if (!kIsWeb) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    try {
                      final String? result = await fs.getDirectoryPath(
                        confirmButtonText: 'settings.workspace.select_dir'.tr(),
                      );
                      if (result != null) {
                        workspaceController.text = result;
                        notifier.updateWorkspace(result);
                      }
                    } catch (e) {
                        AppSnackBar.showError(
                          context,
                          'file_picker.pick_error'.tr(
                            namedArgs: {'error': e.toString()},
                          ),
                        );
                    }
                  },
                  icon: const Icon(
                    AppConstants.folderIcon,
                    color: AppConstants.folderIconColor,
                    size: AppConstants.settingsIconSize,
                  ),
                  tooltip: 'common.browse'.tr(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
