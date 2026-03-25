import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/app_styles.dart';
import '../../widgets/searchable_model_picker.dart';
import '../../widgets/app_dialogs.dart';

class SessionModelDialog extends ConsumerStatefulWidget {
  final String sessionId;
  final String? currentModel;
  final String? currentProvider;

  const SessionModelDialog({
    super.key,
    required this.sessionId,
    this.currentModel,
    this.currentProvider,
  });

  @override
  ConsumerState<SessionModelDialog> createState() => _SessionModelDialogState();
}

class _SessionModelDialogState extends ConsumerState<SessionModelDialog> {
  String? _selectedProvider;
  String? _selectedModel;
  List<String> _availableModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.currentProvider;
    _selectedModel = widget.currentModel;
    if (_selectedProvider != null) {
      _fetchModels();
    }
  }

  Future<void> _fetchModels() async {
    if (_selectedProvider == null) return;
    setState(() {
      _isLoadingModels = true;
      _availableModels = [];
    });

    try {
      final models = await ref
          .read(configProvider.notifier)
          .listModels(_selectedProvider!, null);
      if (mounted) {
        setState(() {
          _availableModels = models;
          _isLoadingModels = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingModels = false);
      }
    }
  }

  void _apply() {
    if (_selectedProvider != null && _selectedModel != null) {
      ref
          .read(sessionsProvider.notifier)
          .setSessionModel(
            widget.sessionId,
            _selectedModel!,
            _selectedProvider,
          );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final vaultKeys = config.vaultKeys;

    final activeProviders = AppConstants.aiProviders.where((p) {
      if (p['id'] == 'ollama' || p['id'] == 'vllm' || p['id'] == 'litellm') {
        // For simplicity in this dialog, we show them all,
        // but real list might be filtered by backend.
        return true;
      }
      final keyName = '${p['id']}_api_key';
      return vaultKeys.contains(keyName);
    }).toList();

    return AppAlertDialog(
      title: Text('chat.change_model_title'.tr()),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('chat.provider_label'.tr()),
            const SizedBox(height: 8),
            AppDropdownField<Map<String, String>>(
              value: activeProviders.firstWhere(
                (p) => p['id'] == _selectedProvider,
                orElse: () => activeProviders.first,
              ),
              items: activeProviders.toList(),
              displayValue: (p) => p['label'] ?? '',
              itemBuilder: (p) => Row(
                children: [
                  Image.asset(
                    AppConstants.getProviderIcon(p['id']!),
                    width: 16,
                    height: 16,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.psychology, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(p['label']!, style: const TextStyle(fontSize: 13)),
                ],
              ),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedProvider = val['id'];
                    _selectedModel = null;
                  });
                  _fetchModels();
                }
              },
            ),
            const SizedBox(height: 20),
            if (_selectedProvider != null) ...[
              _sectionTitle('chat.model_label'.tr()),
              const SizedBox(height: 8),
              SearchableModelPicker(
                selectedModel: _selectedModel,
                models: _availableModels,
                loading: _isLoadingModels,
                label: 'chat.model_label',
                hint: 'chat.model_label',
                onSelected: (val) => setState(() => _selectedModel = val),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'common.cancel'.tr(),
            style: const TextStyle(color: AppColors.textDim),
          ),
        ),
        ElevatedButton(
          onPressed: (_selectedProvider != null && _selectedModel != null)
              ? _apply
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.black,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          child: Text('common.apply'.tr()),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 1.1,
      ),
    );
  }
}
