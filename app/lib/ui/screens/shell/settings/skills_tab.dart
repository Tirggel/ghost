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

class SkillsTab extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const SkillsTab({super.key, this.onBack, this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(child: _SkillsTabContent()),
        _buildNavButtons(context),
      ],
    );
  }

  Widget _buildNavButtons(BuildContext context) {
    return AppSettingsNavBar(onBack: onBack, onNext: onNext);
  }
}

class _SkillsTabContent extends ConsumerStatefulWidget {
  const _SkillsTabContent();

  @override
  ConsumerState<_SkillsTabContent> createState() => _SkillsTabContentState();
}

class _SkillsTabContentState extends ConsumerState<_SkillsTabContent> {
  bool _isInstalling = false;
  bool _isDownloading = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  Future<void> _downloadFromGithub() async {
    final urlController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('settings.skills.download_github_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.skills.download_github_desc'.tr(),
              style: const TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              autofocus: true,
              style: const TextStyle(color: AppColors.white),
              decoration: AppInputDecoration.standard(
                'settings.skills.download_github_url_label'.tr(),
              ).copyWith(hintText: 'https://github.com/...'),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.black,
            ),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && urlController.text.isNotEmpty) {
      try {
        setState(() => _isDownloading = true);
        await ref
            .read(configProvider.notifier)
            .downloadSkillFromGithub(urlController.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.skills.download_success'.tr())),
          );
        }
      } catch (e) {
        if (mounted) {
          showAppErrorDialog(
            context,
            'settings.skills.install_failed'.tr(
              namedArgs: {'error': e.toString()},
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _installSkill() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );

      if (result == null) return;

      final file = result.files.single;
      List<int>? bytes = file.bytes;

      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) return;

      setState(() => _isInstalling = true);
      final base64Zip = base64Encode(bytes);

      await ref.read(configProvider.notifier).installSkill(base64Zip);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.skills.install_success'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'settings.skills.install_failed'.tr(
                namedArgs: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  Future<void> _backupSkills() async {
    try {
      setState(() => _isBackingUp = true);
      final data = await ref.read(configProvider.notifier).backupSkills();
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.skills.save_dialog'.tr(),
        fileName: 'ghost_skills.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.skills.backup_success'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.skills.backup_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreSkills() async {
    try {
      setState(() => _isRestoring = true);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final data = await File(result.files.single.path!).readAsString();
        await ref.read(configProvider.notifier).restoreSkills(data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.skills.restore_success'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.skills.restore_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skillsAsync = ref.watch(skillsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isInstalling || _isDownloading
                    ? null
                    : _installSkill,
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
                label: Text('settings.skills.install'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.black,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isInstalling || _isDownloading
                    ? null
                    : _downloadFromGithub,
                icon: _isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.download,
                        size: AppConstants.settingsIconSize,
                      ),
                label: Text('settings.skills.download_github'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isInstalling || _isDownloading || _isBackingUp
                    ? null
                    : _backupSkills,
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
                label: Text('settings.skills.backup'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isInstalling || _isDownloading || _isRestoring
                    ? null
                    : _restoreSkills,
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
                label: Text('settings.skills.restore'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.white,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SkillsSelector(
              isManagement: true,
              title: '', // No internal header
              onGlobalChanged: (slug, val) => ref
                  .read(configProvider.notifier)
                  .updateSkillGlobal(slug, val),
              onTap: (slug) {
                final skills = skillsAsync.value ?? [];
                final skill = skills.firstWhere((s) => s['slug'] == slug);
                showDialog(
                  context: context,
                  builder: (ctx) => _SkillEditDialog(
                    slug: slug,
                    name: skill['name'] ?? slug,
                  ),
                );
              },
              onDelete: (slug) async {
                final skills = skillsAsync.value ?? [];
                final skill = skills.firstWhere((s) => s['slug'] == slug);
                final config = ref.read(configProvider);
                final isUsedByIdentity = config.agent.skills.contains(slug);
                final isUsedByCustomAgent = config.customAgents.any((agent) {
                  final skills = (agent as Map<String, dynamic>)['skills']
                      as List<dynamic>?;
                  return skills?.contains(slug) ?? false;
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

                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: Text('settings.skills.delete_title'.tr()),
                    content: Text(
                      'settings.skills.delete_content'.tr(
                        namedArgs: {'name': skill['name'] ?? slug},
                      ),
                    ),
                    actions: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('common.cancel'.tr()),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          'common.delete'.tr(),
                          style: const TextStyle(
                            color: AppColors.errorDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(configProvider.notifier).deleteSkill(slug);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillEditDialog extends ConsumerStatefulWidget {
  final String slug;
  final String name;
  const _SkillEditDialog({required this.slug, required this.name});

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
    return AlertDialog(
      backgroundColor: AppColors.surface,
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
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
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
