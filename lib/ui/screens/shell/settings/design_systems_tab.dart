import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/markdown.dart' as highlight_md;
import 'package:flutter_highlight/themes/dracula.dart';
import 'package:path/path.dart' as p;

import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_selectable_card.dart';
import '../../../widgets/app_snackbar.dart';

class DesignSystemsTab extends StatelessWidget {
  const DesignSystemsTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    return _DesignSystemsTabContent(onBack: onBack, onNext: onNext, topPadding: topPadding);
  }
}

class _DesignSystemsTabContent extends ConsumerStatefulWidget {
  const _DesignSystemsTabContent({this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<_DesignSystemsTabContent> createState() => _DesignSystemsTabContentState();
}

class _DesignSystemsTabContentState extends ConsumerState<_DesignSystemsTabContent> {
  bool _isDownloading = false;
  bool _isInstalling = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  Future<void> _downloadFromUrl() async {
    final urlController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text('settings.design_systems.download_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.design_systems.download_desc'.tr(),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              autofocus: true,
              style: const TextStyle(color: AppColors.white),
              decoration: AppInputDecoration.standard(
                'settings.design_systems.url_label'.tr(),
              ).copyWith(hintText: 'https://...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr(), style: const TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.ok'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && urlController.text.isNotEmpty) {
      try {
        setState(() => _isDownloading = true);
        await ref
            .read(configProvider.notifier)
            .addDesignSystemFromUrl(urlController.text);
        if (mounted) {
          AppSnackBar.showSuccess(context, 'settings.design_systems.download_success'.tr());
        }
      } catch (e) {
        if (mounted) {
          showAppErrorDialog(
            context,
            'settings.design_systems.download_failed'.tr(
              namedArgs: {'error': e.toString()},
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _installDesignSystem() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'md'],
        withData: true,
      );

      if (result == null) return;

      final file = result.files.single;
      final extension = file.extension?.toLowerCase();

      if (extension == 'md') {
        String? content;
        if (file.bytes != null) {
          content = utf8.decode(file.bytes!);
        } else if (file.path != null) {
          content = await File(file.path!).readAsString();
        }

        if (content != null) {
          setState(() => _isInstalling = true);
          final name = p.basenameWithoutExtension(file.name);
          await ref.read(configProvider.notifier).saveDesignSystem(name, name, content);
          if (mounted) {
            AppSnackBar.showSuccess(context, 'settings.design_systems.install_success'.tr());
          }
        }
        return;
      }

      // ZIP handling
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) return;

      setState(() => _isInstalling = true);
      final base64Zip = base64Encode(bytes);

      await ref.read(configProvider.notifier).installDesignSystem(base64Zip);
      if (mounted) {
        AppSnackBar.showSuccess(context, 'settings.design_systems.install_success'.tr());
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'settings.design_systems.install_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  Future<void> _backupDesignSystems() async {
    try {
      setState(() => _isBackingUp = true);
      final data = await ref.read(configProvider.notifier).backupDesignSystems();
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.design_systems.save_dialog'.tr(),
        fileName: 'ghost_design_systems.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          AppSnackBar.showSuccess(context, 'settings.design_systems.backup_success'.tr());
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.design_systems.backup_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreDesignSystems() async {
    try {
      setState(() => _isRestoring = true);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final data = await File(result.files.single.path!).readAsString();
        await ref.read(configProvider.notifier).restoreDesignSystems(data);
        if (mounted) {
          AppSnackBar.showSuccess(context, 'settings.design_systems.restore_success'.tr());
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.design_systems.restore_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  void _createNew() {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _DesignSystemEditDialog(
        id: '',
        name: '',
        isNew: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemsAsync = ref.watch(designSystemsProvider);

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      topPadding: widget.topPadding,
      children: [
        const AppSectionHeader(
          'settings.design_systems.section',
          large: true,
        ),
        Text(
          'settings.design_systems.desc'.tr(),
          style: TextStyle(
            color: AppColors.textDim.withValues(alpha: 0.8),
            fontSize: AppConstants.fontSizeBody,
          ),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _isDownloading || _isInstalling ? null : _createNew,
              icon: const Icon(
                Icons.add,
                size: AppConstants.settingsIconSize,
              ),
              label: Text('settings.design_systems.create_new'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.black,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isInstalling || _isDownloading
                  ? null
                  : _installDesignSystem,
              icon: _isInstalling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.upload_file,
                      size: AppConstants.settingsIconSize,
                    ),
              label: Text('settings.design_systems.install'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.black,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isDownloading || _isInstalling ? null : _downloadFromUrl,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.cloud_download,
                      size: AppConstants.settingsIconSize,
                    ),
              label: Text('settings.design_systems.download_url'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isInstalling || _isDownloading || _isBackingUp
                  ? null
                  : _backupDesignSystems,
              icon: _isBackingUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.backup,
                      size: AppConstants.settingsIconSize,
                    ),
              label: Text('settings.design_systems.backup'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isInstalling || _isDownloading || _isRestoring
                  ? null
                  : _restoreDesignSystems,
              icon: _isRestoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.restore,
                      size: AppConstants.settingsIconSize,
                    ),
              label: Text('settings.design_systems.restore'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.settingsSectionSpacing),
        systemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Text('Error: $err'),
          data: (systems) {
            if (systems.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'settings.design_systems.empty'.tr(),
                    style: const TextStyle(color: AppColors.textDim),
                  ),
                ),
              );
            }

            final currentSystem = ref.watch(configProvider.select((c) => c.agent.designSystem));

            return Column(
              children: systems.map((s) {
                final ds = s as Map<String, dynamic>;
                final id = ds['id'] as String;
                final name = ds['name'] as String;
                final isActive = currentSystem == id;

                return _DesignSystemItem(
                  id: id,
                  name: name,
                  isActive: isActive,
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => _DesignSystemEditDialog(
                        id: id,
                        name: name,
                        isNew: false,
                      ),
                    );
                  },
                  onDelete: () async {
                    final confirmed = await AppAlertDialog.showConfirmation(
                      context: context,
                      title: 'settings.design_systems.delete_title'.tr(),
                      content: 'settings.design_systems.delete_content'.tr(
                        namedArgs: {'name': name},
                      ),
                      confirmLabel: 'common.delete'.tr(),
                      isDestructive: true,
                    );
                    if (confirmed == true) {
                      await ref.read(configProvider.notifier).deleteDesignSystem(id);
                    }
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _DesignSystemItem extends StatelessWidget {
  const _DesignSystemItem({
    required this.id,
    required this.name,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  final String id;
  final String name;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppSelectableCard(
      isSelected: isActive,
      onTap: onTap,
      leading: const Icon(
        Icons.palette,
        color: AppConstants.iconColorPrimary,
        size: AppConstants.iconSizeLarge,
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.textMain,
          fontSize: AppConstants.fontSizeBody,
        ),
      ),
      subtitle: Text(
        id,
        style: const TextStyle(
          fontSize: AppConstants.fontSizeSmall,
          color: AppColors.textDim,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.white,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return AppColors.primary;
                }
                return AppColors.white;
              }),
            ),
            onPressed: onTap,
            tooltip: 'common.edit'.tr(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.white,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return AppColors.error;
                }
                return AppColors.white;
              }),
            ),
            onPressed: onDelete,
            tooltip: 'common.delete'.tr(),
          ),
        ],
      ),
    );
  }
}

class _DesignSystemEditDialog extends ConsumerStatefulWidget {
  const _DesignSystemEditDialog({required this.id, required this.name, required this.isNew});
  final String id;
  final String name;
  final bool isNew;

  @override
  ConsumerState<_DesignSystemEditDialog> createState() => _DesignSystemEditDialogState();
}

class _DesignSystemEditDialogState extends ConsumerState<_DesignSystemEditDialog> {
  final _codeController = CodeController(language: highlight_md.markdown);
  late TextEditingController _nameController;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _loadContent();
  }

  Future<void> _loadContent() async {
    if (widget.isNew) {
      _codeController.text = '# New Design System\n\nDefine your tokens here...';
      setState(() => _isLoading = false);
      return;
    }

    final ds = await ref
        .read(configProvider.notifier)
        .getDesignSystem(widget.id);
    if (mounted) {
      _codeController.text = ds?['content'] as String? ?? '';
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: widget.isNew 
          ? Text('settings.design_systems.create_new'.tr())
          : Text('settings.design_systems.edit_title'.tr(namedArgs: {'name': widget.name})),
      content: SizedBox(
        width: 800,
        height: 600,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: AppColors.white),
                    decoration: AppInputDecoration.standard(
                      'settings.design_systems.name_label'.tr(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: CodeTheme(
                      data: CodeThemeData(styles: {...draculaTheme}),
                      child: CodeField(controller: _codeController, expands: true),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr(), style: const TextStyle(color: AppColors.textDim)),
        ),
        AppSaveButton(
          onPressed: () async {
            if (_nameController.text.trim().isEmpty) return;
            
            setState(() => _isSaving = true);
            await ref
                .read(configProvider.notifier)
                .saveDesignSystem(
                  widget.isNew ? _nameController.text : widget.id, 
                  _nameController.text, 
                  _codeController.text,
                );
            if (context.mounted) Navigator.pop(context);
          },
          label: 'common.save',
          isLoading: _isSaving,
        ),
      ],
    );
  }
}
