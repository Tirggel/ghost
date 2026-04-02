import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/searchable_model_picker.dart';
import '../../../widgets/app_dialogs.dart';

class NewChatDialog extends ConsumerStatefulWidget {
  const NewChatDialog({super.key});

  @override
  ConsumerState<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends ConsumerState<NewChatDialog> {
  String? _selectedProvider;
  String? _selectedModel;
  List<String> _availableModels = [];
  bool _isLoadingModels = false;
  final Set<String> _activeLocalProviders = {};

  @override
  void initState() {
    super.initState();
    _checkLocalProviders();
    final config = ref.read(configProvider);
    _selectedProvider = config.agent.provider;
    if (_selectedProvider != null) {
      _fetchModels();
    }
  }

  Future<void> _checkLocalProviders() async {
    for (final p in AppConstants.aiProviders) {
      if (p['id'] == 'ollama' || p['id'] == 'vllm' || p['id'] == 'litellm' || p['id'] == 'lmstudio') {
        try {
          final models = await ref.read(configProvider.notifier).listModels(p['id']!, null);
          if (models.isNotEmpty && mounted) {
            setState(() => _activeLocalProviders.add(p['id']!));
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _fetchModels() async {
    if (_selectedProvider == null) return;
    setState(() {
      _isLoadingModels = true;
      _selectedModel = null;
      _availableModels = [];
    });

    final models = await ref.read(configProvider.notifier).listModels(_selectedProvider!, null);

    if (mounted) {
      setState(() {
        _availableModels = models;
        final config = ref.read(configProvider);
        final defaultModel = config.agent.model;
        if (defaultModel != null && models.contains(defaultModel)) {
          _selectedModel = defaultModel;
        } else if (models.isNotEmpty) {
          _selectedModel = models.first;
        }
        _isLoadingModels = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final vaultKeys = config.vaultKeys;

    final activeProviders = AppConstants.aiProviders.where((p) {
      final id = p['id']!;
      if (id == 'ollama' || id == 'vllm' || id == 'litellm' || id == 'lmstudio') {
        return _activeLocalProviders.contains(id);
      }
      final keyName = id == 'google' ? 'google_api_key' : '${id}_api_key';
      return vaultKeys.contains(keyName);
    }).toList();

    return AppAlertDialog(
      title: Text('settings.new_chat.title'.tr()),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.new_chat.desc'.tr(),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (activeProviders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'settings.new_chat.no_keys'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.errorDark,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else ...[
              AppDropdownField<String>(
                value: _selectedProvider,
                hint: 'settings.new_chat.choose_provider',
                items: activeProviders.map((p) => p['id']!).toList(),
                displayValue: (v) => activeProviders.firstWhere((p) => p['id'] == v)['label']!,
                itemBuilder: (id) {
                  final p = activeProviders.firstWhere((p) => p['id'] == id);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        AppConstants.getProviderIcon(p['id']!),
                        width: 18,
                        height: 18,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.psychology, size: AppConstants.iconSizeSmall, color: AppColors.primary),
                      ),
                      const SizedBox(width: 8),
                      Text(p['label']!, style: const TextStyle(fontSize: 13)),
                    ],
                  );
                },
                onChanged: (val) {
                  setState(() => _selectedProvider = val);
                  _fetchModels();
                },
              ),
              const SizedBox(height: 16),
              if (_selectedProvider != null)
                SearchableModelPicker(
                  selectedModel: _selectedModel,
                  models: _availableModels,
                  loading: _isLoadingModels,
                  label: 'settings.new_chat.choose_model',
                  hint: 'settings.new_chat.choose_model',
                  onSelected: (val) => setState(() => _selectedModel = val),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr(), style: const TextStyle(color: AppColors.textDim)),
        ),
        ElevatedButton(
          onPressed: (_selectedProvider != null && _selectedModel != null)
              ? () => Navigator.pop(context, {
                    'provider': _selectedProvider!,
                    'model': _selectedModel!,
                  })
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.black,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          child: Text('settings.new_chat.start_chat'.tr()),
        ),
      ],
    );
  }
}
