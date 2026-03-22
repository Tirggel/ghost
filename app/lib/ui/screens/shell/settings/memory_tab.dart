import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/searchable_model_picker.dart';

class MemoryTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const MemoryTab({
    super.key,
    this.onBack,
    this.onNext,
  });

  @override
  ConsumerState<MemoryTab> createState() => _MemoryTabState();
}

class _MemoryTabState extends ConsumerState<MemoryTab> {
  late bool _standardEnabled;
  late bool _ragEnabled;
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
      _embeddingProvider = config.memory.embeddingProvider;
      _embeddingModel = config.memory.embeddingModel;
      _selectedProvider = _embeddingProvider.isNotEmpty ? _embeddingProvider : null;
      _selectedModel = _embeddingModel.isNotEmpty ? _embeddingModel : null;
      _isInit = true;
    }
    _updateActiveProviders();
  }

  void _updateActiveProviders() {
    final config = ref.read(configProvider);
    final vaultKeys = config.vaultKeys.toSet();
    final providers = AppConstants.aiProviders;
    final active = <Map<String, String>>[];

    for (final p in providers) {
      final service = p['id']!;
      // Skip non-AI providers
      if (service == 'telegram') continue;

      final isLocal = service == 'ollama' || service == 'vllm' || service == 'litellm';
      final storageKey = isLocal ? '${service}_base_url' : '${service}_api_key';
      final isDetected = config.detectedLocalProviders.any((dp) => dp['id'] == service);

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
    });

    // Update backend immediately to disable RAG
    await ref.read(configProvider.notifier).updateMemory({
      'enabled': _standardEnabled,
      'ragEnabled': false,
      'embeddingProvider': provider,
      'embeddingModel': '',
    });

    final models = await ref.read(configProvider.notifier).listModels(provider, null);
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
        'embeddingProvider': provider,
        'embeddingModel': model,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.memory.embedding_success'.tr())),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.memory.backup_success'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.backup_failed'.tr(namedArgs: {'error': e.toString()}),
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
        await ref.read(gatewayClientProvider).call('memory.restore', {'data': data});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.memory.restore_success'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.restore_failed'.tr(namedArgs: {'error': e.toString()}),
        );
      }
    }
  }

  Future<void> _backupRag() async {
    try {
      final res = await ref.read(gatewayClientProvider).call('memory.rag.backup');
      final data = res['data'] as String?;
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.memory.save_dialog_rag'.tr(),
        fileName: 'ghost_rag.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.memory.rag_backup_success'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.rag_backup_failed'.tr(namedArgs: {'error': e.toString()}),
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
        await ref.read(gatewayClientProvider).call('memory.rag.restore', {'data': data});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.memory.rag_restore_success'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.rag_restore_failed'.tr(namedArgs: {'error': e.toString()}),
        );
      }
    }
  }

  Future<void> _clearMemory(String type, String titleKey, String contentKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(titleKey.tr()),
        content: Text(contentKey.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(gatewayClientProvider).call('config.clearMemory', {'type': type});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('settings.memory.clear_success'.tr())),
          );
        }
      } catch (e) {
        if (mounted) {
          showAppErrorDialog(
            context,
            'settings.memory.clear_failed'.tr(namedArgs: {'error': e.toString()}),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch config to react to changes from outside (e.g. after connect)
    ref.listen(configProvider, (prev, next) {
      if (!_isInit) return;
      if (next.memory.embeddingProvider != _embeddingProvider ||
          next.memory.embeddingModel != _embeddingModel) {
        setState(() {
          _embeddingProvider = next.memory.embeddingProvider;
          _embeddingModel = next.memory.embeddingModel;
        });
      }
    });

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const AppSectionHeader('settings.memory.standard_section'),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'settings.memory.standard_desc'.tr(),
                  style: const TextStyle(color: AppColors.textDim),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                activeThumbColor: AppColors.primary,
                title: Text('settings.memory.standard_enable'.tr().toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                value: _standardEnabled,
                onChanged: (val) async {
                  setState(() => _standardEnabled = val);
                  await ref.read(configProvider.notifier).updateMemory({
                    'enabled': val,
                    'ragEnabled': _ragEnabled,
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('settings.memory.saved'.tr())),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
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
                    onPressed: _standardEnabled ? () => _clearMemory('standard', 'settings.memory.delete_standard_title', 'settings.memory.delete_standard_content') : null,
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: Text('settings.memory.delete_all'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              const AppSectionHeader('settings.memory.rag_section'),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'settings.memory.rag_desc'.tr(),
                  style: const TextStyle(color: AppColors.textDim),
                ),
              ),

              // ── Embedding model selector ─────────────────────────────────
              _buildEmbeddingSelector(),

              const SizedBox(height: 12),

              // RAG on/off switch (disabled until a model is configured)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                activeThumbColor: AppColors.primary,
                title: Text('settings.memory.rag_enable'.tr()),
                subtitle: (_embeddingProvider.isEmpty || _embeddingModel.isEmpty)
                    ? Text(
                        'settings.memory.embedding_no_provider'.tr(),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      )
                    : null,
                value: _ragEnabled,
                onChanged: (_embeddingProvider.isEmpty || _embeddingModel.isEmpty || !_ragEnabled)
                    ? null // can't enable without a model OR if it was disabled (must test first)
                    : (val) async {
                        setState(() => _ragEnabled = val);
                        await ref.read(configProvider.notifier).updateMemory({
                          'enabled': _standardEnabled,
                          'ragEnabled': val,
                          'embeddingProvider': _embeddingProvider,
                          'embeddingModel': _embeddingModel,
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('settings.memory.saved'.tr())),
                          );
                        }
                      },
              ),

              const SizedBox(height: 10),
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
                    onPressed: _ragEnabled ? () => _clearMemory('rag', 'settings.memory.delete_rag_title', 'settings.memory.delete_rag_content') : null,
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: Text('settings.memory.delete_all'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildNavButtons(context),
      ],
    );
  }

  Widget _buildEmbeddingSelector() {
    final hasConfig = _embeddingProvider.isNotEmpty && _embeddingModel.isNotEmpty;

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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '$_embeddingProvider / ${_embeddingModel.contains('/') ? _embeddingModel.split('/').last : _embeddingModel}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Provider dropdown
          Row(
            children: [
              Expanded(
                child: AppDropdownField<String>(
                  value: _activeProviders.any((p) => p['id'] == _selectedProvider)
                      ? _selectedProvider
                      : null,
                  label: 'settings.memory.embedding_provider_label',
                  hint: _activeProviders.isEmpty
                      ? 'settings.memory.embedding_no_active_provider'
                      : 'settings.memory.embedding_choose_provider',
                  items: _activeProviders.map((e) => e['id']!).toList(),
                  displayValue: (id) => id,
                  selectedItemBuilder: (context) {
                    return _activeProviders.map((p) {
                      return Row(
                        children: [
                          Image.asset(
                            AppConstants.getProviderIcon(p['id']!),
                            width: 16,
                            height: 16,
                            errorBuilder: (_, __, ___) => const Icon(Icons.psychology, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Text('providers.${p['id']}'.tr()),
                        ],
                      );
                    }).toList();
                  },
                  itemBuilder: (id) {
                    final p = _activeProviders.firstWhere((e) => e['id'] == id);
                    return Row(
                      children: [
                        Image.asset(
                          AppConstants.getProviderIcon(p['id']!),
                          width: 16,
                          height: 16,
                          errorBuilder: (_, __, ___) => const Icon(Icons.psychology, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text('providers.${p['id']}'.tr()),
                      ],
                    );
                  },
                  onChanged: _activeProviders.isEmpty ? (_) {} : _onProviderChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Model dropdown
          Row(
            children: [
              Expanded(
                child: _loadingModels
                    ? const LinearProgressIndicator()
                    : SearchableModelPicker(
                        selectedModel: _selectedModel,
                        models: _availableModels,
                        onSelected: (val) async {
                          if (_embeddingModel != val) {
                            setState(() {
                              _selectedModel = val;
                              _embeddingProvider = _selectedProvider ?? '';
                              _embeddingModel = val;
                              _ragEnabled = false; // Disable RAG on model change
                            });
                            // Update backend to disable RAG
                            await ref.read(configProvider.notifier).updateMemory({
                              'enabled': _standardEnabled,
                              'ragEnabled': false,
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
                      ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Test & Enable button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedProvider == null ||
                      _selectedModel == null ||
                      _testingEmbedding)
                  ? null
                  : _testAndEnableEmbedding,
              icon: _testingEmbedding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.science, size: 18),
              label: Text(
                (_testingEmbedding
                    ? 'settings.memory.embedding_testing'.tr()
                    : 'settings.memory.embedding_test_button'.tr()).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons(BuildContext context) {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onSave: () async {
        await ref.read(configProvider.notifier).updateMemory({
          'enabled': _standardEnabled,
          'ragEnabled': _ragEnabled,
          'embeddingProvider': _embeddingProvider,
          'embeddingModel': _embeddingModel,
        });
      },
      onNext: widget.onNext,
    );
  }
}
