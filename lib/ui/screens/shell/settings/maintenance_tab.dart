import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_dialogs.dart';

class MaintenanceTab extends ConsumerStatefulWidget {
  const MaintenanceTab({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  ConsumerState<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends ConsumerState<MaintenanceTab> with SettingsSaveMixin {
  final List<String> _subTabLabels = [
    'settings.maintenance.tab',
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(shellProvider.select((s) => s.settingsSubTabIndices[10] ?? 0));

    return AppSettingsPage(
      subTabLabels: _subTabLabels,
      currentSubTabIndex: currentIndex,
      onSubTabChanged: (index) => ref.read(shellProvider.notifier).setSettingsSubTabIndex(10, index),
      onBack: widget.onBack,
      body: IndexedStack(
        index: currentIndex,
        children: [
          _buildMaintenanceContent(),
        ],
      ),
    );
  }

  Widget _buildMaintenanceContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.settingsPagePadding,
        0,
        AppConstants.settingsPagePadding,
        AppConstants.settingsPagePadding,
      ),
      children: [
        // 1. Factory Reset
        _buildSection(
          title: 'settings.maintenance.factory_reset_section',
          description: 'settings.maintenance.factory_reset_desc',
          buttonLabel: 'settings.maintenance.factory_reset_button',
          buttonColor: AppColors.error,
          onPressed: _onFactoryReset,
          isLoading: isSaveLoading,
          icon: Icons.refresh_rounded,
        ),

        const SizedBox(height: 32),
        const Divider(color: AppColors.border),
        const SizedBox(height: 32),

        // 2. Backup
        _buildSection(
          title: 'settings.maintenance.backup_restore_section',
          description: 'settings.maintenance.backup_desc',
          buttonLabel: 'settings.maintenance.backup_button',
          onPressed: _onBackup,
          isLoading: isSaveLoading,
          icon: Icons.save_alt_rounded,
        ),

        const SizedBox(height: 24),

        // 3. Restore
        _buildSection(
          description: 'settings.maintenance.restore_desc',
          buttonLabel: 'settings.maintenance.restore_button',
          onPressed: _onRestore,
          isLoading: isSaveLoading,
          icon: Icons.upload_file_rounded,
        ),
      ],
    );
  }

  Widget _buildSection({
    String? title,
    required String description,
    required String buttonLabel,
    required VoidCallback onPressed,
    required IconData icon,
    Color? buttonColor,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          AppSectionHeader(title, large: true),
          const SizedBox(height: 8),
        ],
        Text(
          description.tr(),
          style: TextStyle(
            fontSize: AppConstants.fontSizeBody,
            color: AppColors.textMain.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        AppSaveButton(
          label: buttonLabel,
          onPressed: isLoading ? null : onPressed,
          icon: icon,
          isLoading: isLoading,
          expand: true,
        ),
      ],
    );
  }

  Future<void> _onFactoryReset() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.maintenance.factory_reset_confirm_title'.tr(),
      content: 'settings.maintenance.factory_reset_confirm_content'.tr(),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      await handleSave(() async {
        final gateway = ref.read(gatewayClientProvider);
        await gateway.call('config.factoryReset', {});
        
        if (mounted) {
          // Show persistent dialog instead of snackbar
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AppAlertDialog(
              title: Text('settings.maintenance.reset_success_title'.tr()),
              content: Text('settings.maintenance.reset_success_content'.tr()),
              actions: [
                TextButton(
                  onPressed: () => exit(0),
                  child: Text('settings.maintenance.exit_button'.tr()),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    
                    // Invalidate providers to force a re-fetch of the token (which is now in the vault)
                    // and a refresh of the configuration.
                    ref.invalidate(authTokenProvider);
                    ref.invalidate(configProvider);
                    ref.invalidate(connectionStatusProvider);
                    ref.invalidate(gatewayUrlProvider);

                    // Also clear local shell state
                    ref.invalidate(shellProvider);
                  },
                  child: Text(
                    'settings.maintenance.restart_button'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }
      });
    }
  }

  Future<void> _onBackup() async {
    await handleSave(() async {
      final gateway = ref.read(gatewayClientProvider);
      final response = await gateway.call('config.backup', {});
      
      final zipBase64 = response['zip'] as String?;
      final filename = response['filename'] as String? ?? 'ghost-backup.zip';

      if (zipBase64 != null) {
        final bytes = base64Decode(zipBase64);
        
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'settings.maintenance.backup_button'.tr(),
          fileName: filename,
          bytes: bytes,
        );

        if (result != null && mounted) {
          AppSnackBar.showSuccess(context, 'settings.maintenance.backup_success'.tr());
        }
      }
    });
  }

  Future<void> _onRestore() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.maintenance.restore_confirm_title'.tr(),
      content: 'settings.maintenance.restore_confirm_content'.tr(),
      confirmLabel: 'settings.maintenance.restore_button'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        await handleSave(
          () async {
            final file = File(result.files.single.path!);
            final bytes = await file.readAsBytes();
            final zipBase64 = base64Encode(bytes);

            final gateway = ref.read(gatewayClientProvider);
            await gateway.call('config.restore', {'zip': zipBase64});

            // Set state to restoring before invalidating providers to ensure
            // the UI switches to the loading/restoring screen immediately.
            gateway.setRestoring();

            // Invalidate providers to force a re-fetch of all data after reconnection.
            ref.invalidate(authTokenProvider);
            ref.invalidate(configProvider);
            ref.invalidate(connectionStatusProvider);
            ref.invalidate(gatewayUrlProvider);
            ref.invalidate(sessionsProvider);
            ref.invalidate(skillsProvider);
          },
          successMessage: 'settings.maintenance.restore_success'.tr(),
        );
      }
    }
  }

}

