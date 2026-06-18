import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class MemoryTab extends ConsumerStatefulWidget {

  const MemoryTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<MemoryTab> createState() => _MemoryTabState();
}

class _MemoryTabState extends ConsumerState<MemoryTab> with SettingsSaveMixin {
  late bool _standardEnabled;
  late bool _ragEnabled;
  late bool _workspaceRagEnabled;
  late String _embeddingProvider;
  late String _embeddingModel;
  bool _isInit = false;

  // Embedding model selector state
  String? _selectedProvider;
  String? _selectedModel;
  List<String> _availableModels = [];
  bool _loadingModels = false;
  bool _testingEmbedding = false;

  // Active providers derived from config
  List<Map<String, String>> _activeProviders = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final config = ref.read(configProvider);
      _standardEnabled = config.memory.enabled;
      _ragEnabled = config.memory.ragEnabled;
      _workspaceRagEnabled = config.memory.workspaceRagEnabled;
      _embeddingProvider = config.memory.embeddingProvider;
      _embeddingModel = config.memory.embeddingModel;
      _selectedProvider = _embeddingProvider.isNotEmpty
          ? _embeddingProvider
          : null;
      _selectedModel = _embeddingModel.isNotEmpty ? _embeddingModel : null;
      _isInit = true;
    }
    _updateActiveProviders();
  }

  void _updateActiveProviders() {
    final config = ref.read(configProvider);
    final vaultKeys = config.vaultKeys.toSet();
    const providers = AppConstants.aiProviders;
    final active = <Map<String, String>>[];

    for (final p in providers) {
      final service = p['id']!;
      // Skip non-AI providers
      if (service == 'telegram') continue;

      final isLocal = AppConstants.isLocalProvider(service);
      final storageKey = isLocal ? '${service}_base_url' : '${service}_api_key';
      final isDetected = config.detectedLocalProviders.any(
        (dp) => dp['id'] == service,
      );

      if (vaultKeys.contains(storageKey) || isDetected) {
        active.add(p);
      }
    }

    active.sort((a, b) => a['label']!.compareTo(b['label']!));
    setState(() => _activeProviders = active);
  }

  Future<void> _onProviderChanged(String? provider) async {
    if (provider == null) return;
    setState(() {
      _selectedProvider = provider;
      _selectedModel = null;
      _availableModels = [];
      _loadingModels = true;
      _ragEnabled = false; // Disable RAG on provider change
      _workspaceRagEnabled = false;
    });

    // Update backend immediately to disable RAG
    await ref.read(configProvider.notifier).updateMemory({
      'enabled': _standardEnabled,
      'ragEnabled': false,
      'workspaceRagEnabled': false,
      'embeddingProvider': provider,
      'embeddingModel': '',
    });

    final models = await ref
        .read(configProvider.notifier)
        .listModels(provider, null);
    setState(() {
      _availableModels = models;
      _loadingModels = false;
      _embeddingProvider = provider;

      if (_embeddingModel.isNotEmpty && models.contains(_embeddingModel)) {
        _selectedModel = _embeddingModel;
      } else {
        _selectedModel = null;
        _embeddingModel = '';
      }
    });
  }

  Future<void> _testAndEnableEmbedding() async {
    final provider = _selectedProvider;
    final model = _selectedModel;

    if (provider == null || model == null || model.isEmpty) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.embedding_no_provider'.tr(),
        );
      }
      return;
    }

    setState(() => _testingEmbedding = true);

    final result = await ref
        .read(configProvider.notifier)
        .testEmbedding(provider, model);

    setState(() => _testingEmbedding = false);

    if (!mounted) return;

    if (result['status'] == 'ok') {
      // Save provider + model + enable RAG
      setState(() {
        _ragEnabled = true;
        _embeddingProvider = provider;
        _embeddingModel = model;
      });
      await ref.read(configProvider.notifier).updateMemory({
        'enabled': _standardEnabled,
        'ragEnabled': true,
        'workspaceRagEnabled': _workspaceRagEnabled,
        'embeddingProvider': provider,
        'embeddingModel': model,
      });
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.memory.embedding_success'.tr(),
        );
      }
    } else {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.embedding_not_supported'.tr(),
        );
      }
    }
  }

  Future<void> _backupStandard() async {
    try {
      final res = await ref.read(gatewayClientProvider).call('memory.backup');
      final data = res['data'] as String?;
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.memory.save_dialog_standard'.tr(),
        fileName: 'ghost_memory.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.backup_success'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.backup_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _restoreStandard() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final data = await File(result.files.single.path!).readAsString();
        await ref.read(gatewayClientProvider).call('memory.restore', {
          'data': data,
        });
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.restore_success'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.restore_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _backupRag() async {
    try {
      final res = await ref
          .read(gatewayClientProvider)
          .call('memory.rag.backup');
      final data = res['data'] as String?;
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.memory.save_dialog_rag'.tr(),
        fileName: 'ghost_rag.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.rag_backup_success'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.rag_backup_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _restoreRag() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final data = await File(result.files.single.path!).readAsString();
        await ref.read(gatewayClientProvider).call('memory.rag.restore', {
          'data': data,
        });
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.rag_restore_success'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.rag_restore_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _clearMemory(
    String type,
    String titleKey,
    String contentKey,
  ) async {
    final confirm = await AppAlertDialog.showConfirmation(
      context: context,
      title: titleKey.tr(),
      content: contentKey.tr(),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirm == true) {
      try {
        await ref.read(gatewayClientProvider).call('config.clearMemory', {
          'type': type,
        });
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.clear_success'.tr(),
          );
        }
      } catch (e) {
        if (mounted) {
          showAppErrorDialog(
            context,
            'settings.memory.clear_failed'.tr(
              namedArgs: {'error': e.toString()},
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch config to react to changes from outside (e.g. after connect)
    ref.listen(configProvider, (prev, next) {
      if (isSaveLoading || !_isInit) return;
      if (next.memory.embeddingProvider != _embeddingProvider ||
          next.memory.embeddingModel != _embeddingModel) {
        setState(() {
          _embeddingProvider = next.memory.embeddingProvider;
          _embeddingModel = next.memory.embeddingModel;
        });
      }
    });


    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      topPadding: widget.topPadding,
      onSave: () async {
        await handleSave(() async {
          await ref.read(configProvider.notifier).updateMemory({
            'enabled': _standardEnabled,
            'ragEnabled': _ragEnabled,
            'workspaceRagEnabled': _workspaceRagEnabled,
            'embeddingProvider': _embeddingProvider,
            'embeddingModel': _embeddingModel,
          });
        }, successMessage: 'settings.memory.saved'.tr());
      },
      isSaveLoading: isSaveLoading,
      children: [
        const AppSectionHeader('settings.memory.standard_section', large: true),
        Text(
          'settings.memory.standard_desc'.tr(),
          style: const TextStyle(color: AppColors.textDim),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),
        AppSwitchListTile(
          title: Text(
            'settings.memory.standard_enable'.tr().toUpperCase(),
            style: const TextStyle(
              fontSize: AppConstants.fontSizeLabelTiny,
              fontWeight: FontWeight.w900,
            ),
          ),
          value: _standardEnabled,
          onChanged: (val) async {
            setState(() => _standardEnabled = val);
            await ref.read(configProvider.notifier).updateMemory({
              'enabled': val,
              'ragEnabled': _ragEnabled,
              'workspaceRagEnabled': _workspaceRagEnabled,
            });
            if (!context.mounted) return;
            AppSnackBar.showSuccess(
              context,
              'settings.memory.saved'.tr(),
            );
          },
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _standardEnabled ? _backupStandard : null,
              icon: const Icon(Icons.download, size: 18),
              label: Text('settings.memory.backup'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.border,
                foregroundColor: AppColors.textMain,
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _standardEnabled ? _restoreStandard : null,
              icon: const Icon(Icons.upload, size: 18),
              label: Text('settings.memory.restore'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.border,
                foregroundColor: AppColors.textMain,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _standardEnabled
                  ? () => _clearMemory(
                      'standard',
                      'settings.memory.delete_standard_title',
                      'settings.memory.delete_standard_content',
                    )
                  : null,
              icon: const Icon(Icons.delete_forever, size: 18),
              label: Text('settings.memory.delete_all'.tr()),
              style:
                  ElevatedButton.styleFrom(
                    backgroundColor: AppColors.border,
                    foregroundColor: AppColors.textMain,
                  ).copyWith(
                    backgroundColor:
                        WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return Colors.red.withValues(alpha: 0.1);
                          }
                          return AppColors.border;
                        }),
                    foregroundColor:
                        WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return Colors.redAccent;
                          }
                          return AppColors.textMain;
                        }),
                    side: WidgetStateProperty.resolveWith<BorderSide?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.hovered)) {
                        return BorderSide(
                          color: Colors.red.withValues(alpha: 0.2),
                        );
                      }
                      return const BorderSide(color: Colors.transparent);
                    }),
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.settingsSectionSpacing),
        const AppSectionHeader('settings.memory.rag_section', large: true),
        Text(
          'settings.memory.rag_desc'.tr(),
          style: const TextStyle(color: AppColors.textDim),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),

        // ── Embedding model selector ─────────────────────────────────
        _buildEmbeddingSelector(),

        const SizedBox(height: AppConstants.settingsContentSpacing),

        // RAG on/off switch (disabled until a model is configured)
        AppSwitchListTile(
          title: Text('settings.memory.rag_enable'.tr()),
          subtitle:
              (_embeddingProvider.isEmpty || _embeddingModel.isEmpty)
              ? Text(
                  'settings.memory.embedding_no_provider'.tr(),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                )
              : null,
          value: _ragEnabled,
          onChanged:
              (_embeddingProvider.isEmpty ||
                  _embeddingModel.isEmpty)
              ? null // can't enable without a model
              : (val) async {
                  final newWorkspaceRag = val ? _workspaceRagEnabled : false;
                  setState(() {
                    _ragEnabled = val;
                    if (!val) _workspaceRagEnabled = false;
                  });
                  await ref.read(configProvider.notifier).updateMemory({
                    'enabled': _standardEnabled,
                    'ragEnabled': val,
                    'workspaceRagEnabled': newWorkspaceRag,
                    'embeddingProvider': _embeddingProvider,
                    'embeddingModel': _embeddingModel,
                  });
                  if (!context.mounted) return;
                  AppSnackBar.showSuccess(
                    context,
                    'settings.memory.saved'.tr(),
                  );
                },
        ),

        const SizedBox(height: AppConstants.settingsContentSpacing),

        // Workspace RAG on/off switch
        AppSwitchListTile(
          title: Text('settings.memory.workspace_rag_enable'.tr()),
          subtitle: (!_ragEnabled)
              ? const Text(
                  'Workspace RAG (RAG Required)',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                )
              : (!AppConstants.isLocalProvider(_embeddingProvider))
                  ? Text(
                      'settings.memory.workspace_rag_local_only'.tr(),
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                      ),
                    )
                  : Text(
                      'settings.memory.workspace_rag_desc'.tr(),
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
          value: _workspaceRagEnabled,
          onChanged: (!_ragEnabled || !AppConstants.isLocalProvider(_embeddingProvider))
              ? null
              : (val) async {
                  setState(() => _workspaceRagEnabled = val);
                  await ref.read(configProvider.notifier).updateMemory({
                    'enabled': _standardEnabled,
                    'ragEnabled': _ragEnabled,
                    'workspaceRagEnabled': val,
                    'embeddingProvider': _embeddingProvider,
                    'embeddingModel': _embeddingModel,
                  });
                  if (!context.mounted) return;
                  AppSnackBar.showSuccess(
                    context,
                    'settings.memory.saved'.tr(),
                  );
                },
        ),

        const SizedBox(height: AppConstants.settingsContentSpacing),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _ragEnabled ? _backupRag : null,
              icon: const Icon(Icons.download, size: 18),
              label: Text('settings.memory.backup'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.border,
                foregroundColor: AppColors.textMain,
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _ragEnabled ? _restoreRag : null,
              icon: const Icon(Icons.upload, size: 18),
              label: Text('settings.memory.restore'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.border,
                foregroundColor: AppColors.textMain,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _ragEnabled
                  ? () => _clearMemory(
                      'rag',
                      'settings.memory.delete_rag_title',
                      'settings.memory.delete_rag_content',
                    )
                  : null,
              icon: const Icon(Icons.delete_forever, size: 18),
              label: Text('settings.memory.delete_all'.tr()),
              style:
                  ElevatedButton.styleFrom(
                    backgroundColor: AppColors.border,
                    foregroundColor: AppColors.textMain,
                  ).copyWith(
                    backgroundColor:
                        WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return Colors.red.withValues(alpha: 0.1);
                          }
                          return AppColors.border;
                        }),
                    foregroundColor:
                        WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return Colors.redAccent;
                          }
                          return AppColors.textMain;
                        }),
                    side: WidgetStateProperty.resolveWith<BorderSide?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.hovered)) {
                        return BorderSide(
                          color: Colors.red.withValues(alpha: 0.2),
                        );
                      }
                      return const BorderSide(color: Colors.transparent);
                    }),
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmbeddingSelector() {
    final hasConfig =
        _embeddingProvider.isNotEmpty && _embeddingModel.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'settings.memory.embedding_section'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              // Show current config badge
              if (hasConfig)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$_embeddingProvider / ${_embeddingModel.contains('/') ? _embeddingModel.split('/').last : _embeddingModel}',
                    style: const TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.settingsElementSpacing),

          // Provider dropdown
          Row(
            children: [
              Expanded(
                child: AppUnifiedPicker<String>(
                  value:
                      _activeProviders.any((p) => p['id'] == _selectedProvider)
                      ? _selectedProvider
                      : null,
                  label: 'settings.memory.embedding_provider_label',
                  hint: _activeProviders.isEmpty
                      ? 'settings.memory.embedding_no_active_provider'
                      : 'settings.memory.embedding_choose_provider',
                  items: _activeProviders.map((e) => e['id']!).toList(),
                  displayValue: (id) => id,
                  itemPrefixIcon: (id) {
                    final p = _activeProviders.firstWhere((e) => e['id'] == id);
                    return Image.asset(
                      AppConstants.getProviderIcon(p['id']!),
                      width: 16,
                      height: 16,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.psychology, size: 16),
                    );
                  },
                  onChanged: _activeProviders.isEmpty
                      ? (_) {}
                      : _onProviderChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppConstants.settingsElementSpacing),

          // Model dropdown
          Row(
            children: [
              Expanded(
                child: AppUnifiedPicker<String>(
                  value: _selectedModel,
                  items: _availableModels,
                  displayValue: (v) => v,
                  onChanged: (val) async {
                    if (val != null && _embeddingModel != val) {
                      setState(() {
                        _selectedModel = val;
                        _embeddingProvider = _selectedProvider ?? '';
                        _embeddingModel = val;
                        _ragEnabled = false; // Disable RAG on model change
                        _workspaceRagEnabled = false;
                      });
                      // Update backend to disable RAG
                      await ref
                          .read(configProvider.notifier)
                          .updateMemory({
                            'enabled': _standardEnabled,
                            'ragEnabled': false,
                            'workspaceRagEnabled': false,
                            'embeddingProvider': _embeddingProvider,
                            'embeddingModel': val,
                          });
                    }
                  },
                  label: 'settings.memory.embedding_model_label',
                  hint: _selectedProvider == null
                      ? 'settings.memory.embedding_choose_provider_first'
                      : _availableModels.isEmpty
                      ? 'settings.memory.embedding_no_models'
                      : 'settings.memory.embedding_model_label',
                  loading: _loadingModels,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppConstants.settingsElementSpacing),

          // Test & Enable button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_selectedProvider == null ||
                      _selectedModel == null ||
                      _testingEmbedding)
                  ? null
                  : _testAndEnableEmbedding,
              icon: _testingEmbedding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.science, size: 18),
              label: Text(
                (_testingEmbedding
                        ? 'settings.memory.embedding_testing'.tr()
                        : 'settings.memory.embedding_test_button'.tr())
                    .toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
