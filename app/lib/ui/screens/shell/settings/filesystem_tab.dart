import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_selector/file_selector.dart' as fs;
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';

class FilesystemTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const FilesystemTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<FilesystemTab> createState() => _FilesystemTabState();
}

class _FilesystemTabState extends ConsumerState<FilesystemTab> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(configProvider).agent.workspace ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(configProvider.notifier).updateAgentWorkspace(_controller.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.workspace.saved'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (prev, next) {
      final ws = next.agent.workspace;
      if (ws != null && ws.isNotEmpty && _controller.text.isEmpty) {
        _controller.text = ws;
      }
    });

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const AppSectionHeader('settings.workspace.section', large: true),
              Text(
                'settings.workspace.desc'.tr(),
                style: const TextStyle(color: AppColors.textDim, fontSize: AppConstants.fontSizeBody),
              ),
              const SizedBox(height: 16),
              AppFormField.text(
                controller: _controller,
                label: 'settings.workspace.path_label',
                hint: 'settings.workspace.path_hint',
                prefixIcon: const Icon(
                  AppConstants.folderIcon,
                  color: AppColors.textDim,
                  size: AppConstants.iconSizeSmall,
                ),
                suffixIcon: IconButton(
                  onPressed: _browse,
                  icon: const Icon(
                    Icons.folder_open,
                    color: AppColors.primary,
                    size: AppConstants.settingsIconSize,
                  ),
                  tooltip: 'common.browse'.tr(),
                ),
                onSubmitted: (_) {},
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  _controller.clear();
                  await ref.read(configProvider.notifier).updateAgentWorkspace('');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('settings.workspace.reset_done'.tr())),
                    );
                  }
                },
                icon: const Icon(Icons.refresh, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textDim,
                  side: const BorderSide(color: AppColors.border),
                ),
                label: Text('settings.workspace.reset'.tr()),
              ),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  Future<void> _browse() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('settings.workspace.browse_web_error'.tr()),
            backgroundColor: AppColors.errorDark,
          ),
        );
      }
      return;
    }
    try {
      final String? result = await fs.getDirectoryPath(
        confirmButtonText: 'settings.workspace.select_dir'.tr(),
      );
      if (result != null) {
        setState(() => _controller.text = result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('file_picker.pick_error'.tr(namedArgs: {'error': e.toString()})),
            backgroundColor: AppColors.errorDark,
          ),
        );
      }
    }
  }

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onSave: _save,
      onNext: widget.onNext,
    );
  }
}
