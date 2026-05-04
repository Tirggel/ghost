
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
        
        // Also clear local state to allow fresh discovery on restart
        await ref.read(authTokenProvider.notifier).logout();
        
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
    // Show section selection dialog
    final sections = await _showBackupSectionDialog();
    if (sections == null) return; // User cancelled

    await handleSave(() async {
      final gateway = ref.read(gatewayClientProvider);
      final response = await gateway.call('config.backup', {
        'sections': sections.toList(),
      });

      // Backend returns a local temp file path — no base64 transfer needed.
      final tempPath = response['path'] as String?;
      final filename = response['filename'] as String? ?? 'ghost-backup.zip';

      if (tempPath != null) {
        final bytes = await File(tempPath).readAsBytes();
        await File(tempPath).delete(); // Clean up temp file

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

  /// Shows a dialog to let the user pick which sections to include in the backup.
  /// Returns the selected sections set, or null if cancelled.
  Future<Set<String>?> _showBackupSectionDialog() async {
    final selected = <String>{
      'config',
      'vault',
      'sessions',
      'skills',
      'memory',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BackupSectionDialog(initialSelected: selected),
    );

    if (confirmed != true) return null;
    return selected;
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
        final filePath = result.files.single.path!;
        final gateway = ref.read(gatewayClientProvider);

        // 1. Clear the stale token from local storage AND the server-side
        // /client-token cache.
        await ref.read(authTokenProvider.notifier).clearLocalToken();

        // 2. Send the restore command. The backend reads the file directly
        // from disk (no base64 over WebSocket).
        final response = await gateway.call('config.restore', {'path': filePath});
        final restoredToken = response['token'] as String?;

        if (mounted) {
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
      }
    }
  }

}

// ---------------------------------------------------------------------------
// Backup Section Selection Dialog
// ---------------------------------------------------------------------------

class _BackupSectionDialog extends StatefulWidget {
  const _BackupSectionDialog({required this.initialSelected});
  final Set<String> initialSelected;

  @override
  State<_BackupSectionDialog> createState() => _BackupSectionDialogState();
}

class _BackupSectionDialogState extends State<_BackupSectionDialog> {
  late final Set<String> _selected;

  static const _sections = [
    ('config',   Icons.settings_rounded,           'settings.maintenance.backup_section_config',   'settings.maintenance.backup_section_config_desc'),
    ('vault',    Icons.lock_rounded,               'settings.maintenance.backup_section_vault',    'settings.maintenance.backup_section_vault_desc'),
    ('sessions', Icons.chat_bubble_outline_rounded,'settings.maintenance.backup_section_sessions', 'settings.maintenance.backup_section_sessions_desc'),
    ('skills',   Icons.extension_rounded,          'settings.maintenance.backup_section_skills',   'settings.maintenance.backup_section_skills_desc'),
    ('memory',   Icons.memory_rounded,             'settings.maintenance.backup_section_memory',   'settings.maintenance.backup_section_memory_desc'),
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: Text('settings.maintenance.backup_select_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'settings.maintenance.backup_select_desc'.tr(),
            style: TextStyle(
              fontSize: AppConstants.fontSizeSmall,
              color: AppColors.textMain.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          ..._sections.map((s) {
            final (key, icon, label, desc) = s;
            final isSelected = _selected.contains(key);
            return _SectionTile(
              icon: icon,
              label: label.tr(),
              desc: desc.tr(),
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(key);
                  } else {
                    _selected.remove(key);
                  }
                });
                // Propagate back to parent set
                widget.initialSelected.clear();
                widget.initialSelected.addAll(_selected);
              },
            );
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        TextButton(
          onPressed: _selected.isEmpty ? null : () => Navigator.of(context).pop(true),
          child: Text(
            'settings.maintenance.backup_button'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _selected.isEmpty ? AppColors.textDim : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: value ? AppColors.primary : AppColors.textDim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppConstants.fontSizeBody,
                      fontWeight: FontWeight.w600,
                      color: value ? AppColors.textMain : AppColors.textDim,
                    ),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: AppConstants.fontSizeSmall,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border, width: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

