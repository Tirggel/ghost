import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import '../app_snackbar.dart';
import '../app_dialogs.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepRestore extends ConsumerStatefulWidget {
  const WizardStepRestore({super.key});

  @override
  ConsumerState<WizardStepRestore> createState() => _WizardStepRestoreState();
}

class _WizardStepRestoreState extends ConsumerState<WizardStepRestore> {
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    return WizardStepBase(
      icon: Icons.settings_backup_restore_rounded,
      title: 'wizard.step_restore'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardStepHeader(text: 'wizard.step_restore'.tr()),
          const SizedBox(height: 16),
          
          // 1. Start Fresh
          _buildSelectionCard(
            title: 'wizard.restore_fresh_title'.tr(),
            description: 'wizard.restore_fresh_desc'.tr(),
            icon: Icons.auto_awesome_rounded,
            onTap: _onStartFresh,
          ),
          
          const SizedBox(height: 12),
          
          // 2. Restore from Backup
          _buildSelectionCard(
            title: 'wizard.restore_backup_title'.tr(),
            description: 'wizard.restore_backup_desc'.tr(),
            icon: Icons.upload_file_rounded,
            onTap: _isRestoring ? () {} : _onRestore,
            isLoading: _isRestoring,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return AppHoverCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: isLoading 
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeTitle,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeSmall,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ],
      ),
    );
  }

  void _onStartFresh() {
    final state = ref.read(setupWizardProvider);
    ref.read(setupWizardProvider.notifier).setStep(state.currentStep + 1);
  }

  Future<void> _onRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() => _isRestoring = true);
      try {
        // Send the local file path — the backend reads it directly.
        // This avoids encoding hundreds of MB as base64 over the WebSocket.
        final filePath = result.files.single.path!;

        final gateway = ref.read(gatewayClientProvider);

        // Clear local token first so the frontend waits for the backend to provide the new one
        await ref.read(authTokenProvider.notifier).clearLocalToken();

        final response = await gateway.call('config.restore', {'path': filePath});
        final restoredToken = response['token'] as String?;

        if (mounted) {
          setState(() => _isRestoring = false);
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AppAlertDialog(
              title: const Text('System wiederhergestellt'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Das System wurde erfolgreich wiederhergestellt. Bitte starte die App neu.'),
                  if (restoredToken != null) ...[
                    const SizedBox(height: 16),
                    const Text('Dein neuer Token lautet:'),
                    const SizedBox(height: 8),
                    SelectableText(
                      restoredToken,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => exit(0),
                  child: const Text('App schließen', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(context, e.toString());
          setState(() => _isRestoring = false);
        }
      }
    }
  }
}
