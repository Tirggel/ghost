import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../core/models/config_models.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_settings_input.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class ApiKeysTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const ApiKeysTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<ApiKeysTab> createState() => _ApiKeysTabState();
}

class _ApiKeysTabState extends ConsumerState<ApiKeysTab> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _verifyingKey = {};
  String? _visibleKeyProvider;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  TextEditingController _getApiController(String service, AppConfig config) {
    return _controllers.putIfAbsent(
      service,
      () {
        final controller = TextEditingController();
        // Pre-fill with detected URL if it's a local provider
        final detected = config.detectedLocalProviders.firstWhere(
          (dp) => dp['id'] == service,
          orElse: () => <String, String>{},
        );
        if (detected.containsKey('url')) {
          controller.text = detected['url']!;
        }
        return controller;
      },
    );
  }


  Future<void> _verifyAndSaveKey(String service, String label) async {
    final key = _getApiController(service, ref.read(configProvider)).text.trim();
    if (key.isEmpty) return;

    setState(() => _verifyingKey[service] = true);
    final result = await ref
        .read(configProvider.notifier)
        .testKey(service, key);
    setState(() => _verifyingKey[service] = false);

    if (result['status'] == 'ok') {
      try {
        await ref.read(configProvider.notifier).setKey(service, key);
        _getApiController(service, ref.read(configProvider)).clear();
        setState(() => _visibleKeyProvider = null);
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.api_keys.key_saved'.tr(namedArgs: {'label': 'providers.$service'.tr()}),
          );
        }
      } catch (e) {
        if (mounted) {
          final message = e is Map ? e['message']?.toString() ?? e.toString() : e.toString();
          showAppErrorDialog(context, message);
        }
      }
    } else {
      if (mounted) {
        _getApiController(service, ref.read(configProvider)).clear();
        AppSnackBar.showError(
          context,
          'settings.api_keys.verification_failed_content'.tr(
            namedArgs: {'message': result['message'].toString()},
          ),
        );
      }
    }
  }

  Future<void> _deleteApiKey(String service, String label) async {
    final config = ref.read(configProvider);
    
    // Check if provider is used by main agent
    final isUsedByMain = config.agent.provider == service;
    
    // Check if provider is used by any custom agent
    final isUsedByCustom = config.customAgents.any((agent) => 
        (agent as Map<String, dynamic>)['provider'] == service);

    if (isUsedByMain || isUsedByCustom) {
      if (mounted) {
        showAppErrorDialog(
          context, 
          'settings.api_keys.delete_error_used'.tr()
        );
      }
      return;
    }

    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.api_keys.delete_key_title'.tr(namedArgs: {'label': 'providers.$service'.tr()}),
      content: 'settings.api_keys.delete_key_content'.tr(
        namedArgs: {'label': 'providers.$service'.tr()},
      ),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      try {
        await ref.read(configProvider.notifier).setKey(service, '');
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.api_keys.key_removed'.tr(namedArgs: {'label': 'providers.$service'.tr()}),
          );
        }
      } catch (e) {
        if (mounted) {
          final message = e is Map ? e['message']?.toString() ?? e.toString() : e.toString();
          showAppErrorDialog(context, message);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = AppConstants.aiProviders;
    final config = ref.watch(configProvider);
    final vaultKeys = config.vaultKeys.toSet();

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      children: [
        const AppSectionHeader('settings.api_keys.section', large: true),
        Text(
          'settings.api_keys.desc'.tr(),
          style: const TextStyle(
            fontSize: AppConstants.fontSizeBody,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          style: const TextStyle(color: AppColors.white, fontSize: 13),
          decoration: AppInputDecoration.compact(
            hint: 'settings.api_keys.search_placeholder',
            prefixIcon:
                const Icon(Icons.search, size: 18, color: AppColors.textDim),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        size: 18, color: AppColors.textDim),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        ...buildProviderSections(providers, vaultKeys, config),
      ],
    );
  }

  List<Widget> buildProviderSections(
    List<Map<String, String>> providers,
    Set<String> vaultKeys,
    AppConfig config,
  ) {
    final active = <Map<String, String>>[];
    final inactive = <Map<String, String>>[];

    for (final p in providers) {
      final service = p['id']!;
      final label = 'providers.$service'.tr();

      if (_searchQuery.isNotEmpty &&
          !label.toLowerCase().contains(_searchQuery)) {
        continue;
      }

      final isLocalProvider =
          service == 'ollama' || service == 'vllm' || service == 'litellm';

      late String storageKey;
      if (service == 'telegram') {
        storageKey = 'telegram_bot_token';
      } else if (isLocalProvider) {
        storageKey = '${service}_base_url';
      } else {
        storageKey = '${service}_api_key';
      }

      final detected = config.detectedLocalProviders.any((dp) => dp['id'] == service);

      if (vaultKeys.contains(storageKey) || detected) {
        active.add(p);
      } else {
        inactive.add(p);
      }
    }

    // Sort both by label
    active.sort((a, b) => a['label']!.compareTo(b['label']!));
    inactive.sort((a, b) => a['label']!.compareTo(b['label']!));

    final widgets = <Widget>[];

    if (active.isNotEmpty) {
      widgets.addAll(active.map((p) => _buildProviderTile(p, vaultKeys, config)));
    }

    if (inactive.isNotEmpty) {
      if (active.isNotEmpty) {
        widgets.add(const SizedBox(height: 32));
        widgets.add(const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AppSectionLabel('settings.api_keys.other_providers'),
        ));
      }
      widgets.addAll(inactive.map((p) => _buildProviderTile(p, vaultKeys, config)));
    }

    return widgets;
  }

  Widget _buildProviderTile(Map<String, String> p, Set<String> vaultKeys, AppConfig config) {
    final label = p['label']!;
    final service = p['id']!;
    final isLocalProvider =
        service == 'ollama' || service == 'vllm' || service == 'litellm';

    late String storageKey;
    if (service == 'telegram') {
      storageKey = 'telegram_bot_token';
    } else if (isLocalProvider) {
      storageKey = '${service}_base_url';
    } else {
      storageKey = '${service}_api_key';
    }

    final isAlreadySet = vaultKeys.contains(storageKey);
    final isVerifying = _verifyingKey[service] ?? false;
    final isEditing = _visibleKeyProvider == service;

    return AppSettingsInput(
      title: 'providers.$service',
      subtitle: (isLocalProvider && !isEditing)
          ? (isAlreadySet
              ? 'settings.api_keys.custom_url'
              : (config.detectedLocalProviders.any((dp) => dp['id'] == service)
                  ? 'settings.api_keys.detected_url'
                  : 'settings.api_keys.default_url'))
          : null,
      leading: _buildProviderIcon(service),
      controller: _getApiController(service, config),
      isEditing: isEditing || (!isAlreadySet && _visibleKeyProvider == service),
      isAlreadySet: isAlreadySet,
      isVerifying: isVerifying,
      obscureText: !isLocalProvider && !isEditing,
      hint: isLocalProvider
          ? 'settings.api_keys.base_url_hint'
          : 'settings.api_keys.key_hint',
      labelText: isLocalProvider
          ? 'settings.api_keys.base_url_label'
          : null,
      onEdit: () async {
        final key = await ref.read(configProvider.notifier).getKey(service);
        if (mounted) {
          if (key != null) {
            _getApiController(service, config).text = key;
          }
          setState(() => _visibleKeyProvider = service);
        }
      },
      onDelete: () => _deleteApiKey(service, label),
      onSave: () => _verifyAndSaveKey(service, label),
      onCancel: () => setState(() => _visibleKeyProvider = null),
      addTooltip: 'settings.api_keys.add_tooltip',
      deleteTooltip: 'settings.api_keys.delete_tooltip',
      verifySaveTooltip: 'settings.api_keys.verify_save_tooltip',
    );
  }

  Widget _buildProviderIcon(String id) {
    final iconPath = AppConstants.getProviderIcon(id);
    if (iconPath.isEmpty) {
      return const Icon(
        Icons.psychology,
        size: AppConstants.iconSizeMedium,
        color: AppConstants.iconColorPrimary,
      );
    }
    return Image.asset(
      iconPath,
      width: 20,
      height: 20,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.psychology,
        size: AppConstants.iconSizeMedium,
        color: AppConstants.iconColorPrimary,
      ),
    );
  }
}
