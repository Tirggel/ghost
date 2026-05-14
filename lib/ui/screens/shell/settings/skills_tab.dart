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
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/skills_selector_widget.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class SkillsTab extends ConsumerStatefulWidget {
  const SkillsTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends ConsumerState<SkillsTab> with SettingsSaveMixin {

  Future<void> _downloadFromGithub() async {
    final urlController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text('settings.skills.download_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.skills.download_desc'.tr(),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              autofocus: true,
              style: const TextStyle(color: AppColors.white),
              decoration: AppInputDecoration.standard(
                'settings.skills.url_label'.tr(),
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
      await handleSave(() async {
        await ref
            .read(configProvider.notifier)
            .downloadSkillFromGithub(urlController.text);
      }, successMessage: 'settings.skills.download_success'.tr());
    }
  }

  Future<void> _installSkill() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(context, 'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}));
      }
      return;
    }

    if (result == null) return;

    await handleSave(() async {
      final file = result!.files.single;
      List<int>? bytes = file.bytes;

      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) return;

      final base64Zip = base64Encode(bytes);
      await ref.read(configProvider.notifier).installSkill(base64Zip);
    }, successMessage: 'settings.skills.install_success'.tr());
  }

  Future<void> _backupSkills() async {
    await handleSave(() async {
      final data = await ref.read(configProvider.notifier).backupSkills();
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.skills.save_dialog'.tr(),
        fileName: 'ghost_skills.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          AppSnackBar.showSuccess(context, 'settings.skills.backup_success'.tr());
        }
      }
    });
  }

  Future<void> _restoreSkills() async {
    await handleSave(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final data = await File(result.files.single.path!).readAsString();
        await ref.read(configProvider.notifier).restoreSkills(data);
        if (mounted) {
          AppSnackBar.showSuccess(context, 'settings.skills.restore_success'.tr());
        }
      }
    });
  }

  void _createNew() {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _SkillCreateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skillsAsync = ref.watch(skillsProvider);

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      topPadding: widget.topPadding,
      children: [
        const AppSectionHeader(
          'settings.skills.section',
          large: true,
        ),
        Text(
          'settings.skills.desc'.tr(),
          style: TextStyle(
            color: AppColors.textDim.withValues(alpha: 0.8),
            fontSize: AppConstants.fontSizeBody,
          ),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppActionButton(
              label: 'settings.skills.create_new',
              icon: Icons.add,
              onPressed: _createNew,
              isPrimary: true,
            ),
            AppActionButton(
              label: 'settings.skills.install',
              icon: Icons.upload_file,
              onPressed: isSaveLoading ? null : _installSkill,
              isLoading: isSaveLoading,
              isPrimary: true,
            ),
            AppActionButton(
              label: 'settings.skills.download_url',
              icon: Icons.cloud_download,
              onPressed: isSaveLoading ? null : _downloadFromGithub,
            ),
            AppActionButton(
              label: 'settings.skills.backup',
              icon: Icons.backup,
              onPressed: isSaveLoading ? null : _backupSkills,
            ),
            AppActionButton(
              label: 'settings.skills.restore',
              icon: Icons.restore,
              onPressed: isSaveLoading ? null : _restoreSkills,
            ),
          ],
        ),
        const SizedBox(height: AppConstants.settingsSectionSpacing),
        SkillsSelector(
          isManagement: true,
          title: '', // No internal header

          onTap: (slug) {
            final skills = skillsAsync.value ?? [];
            final skill = skills.firstWhere((s) => s['slug'] == slug);
            showDialog<void>(
              context: context,
              builder: (ctx) => _SkillEditDialog(
                slug: slug,
                name: (skill['name'] as String?) ?? slug,
              ),
            );
          },
          onDelete: (slug) async {
            final skills = skillsAsync.value ?? [];
            final skill = skills.firstWhere((s) => s['slug'] == slug);
            final config = ref.read(configProvider);
            final isUsedByIdentity = config.agent.skills.contains(slug);
            final isUsedByCustomAgent = config.customAgents.any((agent) {
              return agent.skills.contains(slug);
            });

            if (isUsedByIdentity || isUsedByCustomAgent) {
              if (mounted) {
                showAppErrorDialog(
                  context,
                  'settings.skills.delete_error_used'.tr(),
                );
              }
              return;
            }

            final confirmed = await AppAlertDialog.showConfirmation(
              context: context,
              title: 'settings.skills.delete_title'.tr(),
              content: 'settings.skills.delete_content'.tr(
                namedArgs: {'name': (skill['name'] as String?) ?? slug},
              ),
              confirmLabel: 'common.delete'.tr(),
              isDestructive: true,
            );
            if (confirmed == true) {
              await ref.read(configProvider.notifier).deleteSkill(slug);
            }
          },
        ),
      ],
    );
  }
}

class _SkillEditDialog extends ConsumerStatefulWidget {
  const _SkillEditDialog({required this.slug, required this.name});
  final String slug;
  final String name;

  @override
  ConsumerState<_SkillEditDialog> createState() => _SkillEditDialogState();
}

class _SkillEditDialogState extends ConsumerState<_SkillEditDialog> {
  final _codeController = CodeController(language: highlight_md.markdown);
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final content = await ref
        .read(configProvider.notifier)
        .getSkillMarkdown(widget.slug);
    if (mounted) {
      _codeController.text = content;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: Text(
        'settings.skills.edit_title'.tr(namedArgs: {'name': widget.name}),
      ),
      content: SizedBox(
        width: 800,
        height: 600,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CodeTheme(
                data: CodeThemeData(styles: {...draculaTheme}),
                child: CodeField(controller: _codeController, expands: true),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr(), style: const TextStyle(color: AppColors.textDim)),
        ),
        AppSaveButton(
          onPressed: () async {
            setState(() => _isSaving = true);
            await ref
                .read(configProvider.notifier)
                .updateSkillMarkdown(widget.slug, _codeController.text);
            if (context.mounted) Navigator.pop(context);
          },
          label: 'common.save',
          isLoading: _isSaving,
        ),
      ],
    );
  }
}

class _SkillCreateDialog extends ConsumerStatefulWidget {
  const _SkillCreateDialog();

  @override
  ConsumerState<_SkillCreateDialog> createState() => _SkillCreateDialogState();
}

class _SkillCreateDialogState extends ConsumerState<_SkillCreateDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _emojiController = TextEditingController(text: '🛠️');
  String _type = 'python';
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: Text('settings.skills.new_title'.tr()),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(color: AppColors.white),
              decoration: AppInputDecoration.standard(
                'settings.skills.name_label'.tr(),
              ).copyWith(hintText: 'settings.skills.name_hint'.tr()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              style: const TextStyle(color: AppColors.white),
              decoration: AppInputDecoration.standard(
                'settings.skills.desc_label'.tr(),
              ).copyWith(hintText: 'settings.skills.desc_hint'.tr()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emojiController,
              style: const TextStyle(color: AppColors.white),
              decoration: AppInputDecoration.standard(
                'settings.skills.emoji_label'.tr(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'settings.skills.type_label'.tr(),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: Text('settings.skills.type_python'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 14)),
                    value: 'python',
                    groupValue: _type,
                    onChanged: (val) => setState(() => _type = val!),
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: Text('settings.skills.type_node'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 14)),
                    value: 'node',
                    groupValue: _type,
                    onChanged: (val) => setState(() => _type = val!),
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
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
            
            setState(() => _isCreating = true);
            try {
              await ref.read(configProvider.notifier).createSkill(
                    name: _nameController.text.trim(),
                    description: _descController.text.trim(),
                    type: _type,
                    emoji: _emojiController.text.trim(),
                  );
              if (mounted) {
                AppSnackBar.showSuccess(context, 'settings.skills.create_success'.tr());
                Navigator.pop(context);
              }
            } catch (e) {
              if (mounted) {
                showAppErrorDialog(context, e.toString());
              }
            } finally {
              if (mounted) setState(() => _isCreating = false);
            }
          },
          label: 'settings.skills.create_button',
          isLoading: _isCreating,
        ),
      ],
    );
  }
}
