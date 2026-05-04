import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_settings_input.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class ExternalServicesTab extends ConsumerStatefulWidget {
  const ExternalServicesTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<ExternalServicesTab> createState() => _ExternalServicesTabState();
}

class _ExternalServicesTabState extends ConsumerState<ExternalServicesTab> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _verifyingKey = {};
  String? _visibleKeyProvider;
  bool _isAddingNew = false;
  
  final _newNameController = TextEditingController();
  final _newKeyController = TextEditingController();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _newNameController.dispose();
    _newKeyController.dispose();
    super.dispose();
  }

  TextEditingController _getApiController(String service) {
    return _controllers.putIfAbsent(service, () => TextEditingController());
  }

  Future<void> _verifyAndSaveKey(String service, String key) async {
    if (key.isEmpty || service.isEmpty) return;

    // Convert service to a safe storage format (lowercase, underscores) if needed
    // But since users can type anything, let's keep it mostly as is, just trim. Let's use lowercase for consistency with ids.
    final serviceId = service.trim().toLowerCase().replaceAll(' ', '_');

    setState(() => _verifyingKey[serviceId] = true);
    
    // We can "test" the key, but for external generic services we don't have a specific test.
    // The gateway allows config.setKey for any service.
    // We will just save it.
    try {
      // Standard for external services is to have _api_key suffix in vault
      final vaultKey = serviceId.endsWith('_api_key') ? serviceId : '${serviceId}_api_key';
      await ref.read(configProvider.notifier).setKey(vaultKey, key);
      _getApiController(serviceId).clear();
      setState(() {
        _visibleKeyProvider = null;
        _isAddingNew = false;
        _verifyingKey[serviceId] = false;
      });
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.external_services.key_saved'.tr(namedArgs: {'label': service}),
        );
      }
    } catch (e) {
      setState(() => _verifyingKey[serviceId] = false);
      if (mounted) {
        final message = e is Map ? e['message']?.toString() ?? e.toString() : e.toString();
        showAppErrorDialog(context, message);
      }
    }
  }

  Future<void> _deleteApiKey(String serviceId, String originalName) async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.external_services.delete_key_title'.tr(namedArgs: {'label': originalName}),
      content: 'settings.external_services.delete_key_content'.tr(namedArgs: {'label': originalName}),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      try {
        await ref.read(configProvider.notifier).setKey(serviceId, '');
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.external_services.key_removed'.tr(namedArgs: {'label': originalName}),
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
    final config = ref.watch(configProvider);
    final vaultKeys = config.vaultKeys.toSet();

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      children: [
        const AppSectionHeader('settings.external_services.section', large: true),
        Text(
          'settings.external_services.desc'.tr(),
          style: const TextStyle(
            fontSize: AppConstants.fontSizeBody,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: 16),
        _buildAddServiceTile(),
        const SizedBox(height: 16),
        ..._buildServiceSections(vaultKeys),
      ],
    );
  }

  List<Widget> _buildServiceSections(Set<String> vaultKeys) {
    final aiProviderIds = AppConstants.aiProviders.map((p) => p['id']).toSet();

    // Find external keys that end in _api_key but are not AI providers,
    // not internal integration keys, and not OAuth-related
    final externalKeys = vaultKeys.where((k) {
      // Must end with _api_key
      if (!k.endsWith('_api_key')) return false;
      final sid = k.replaceAll('_api_key', '');

      // Exclude known AI providers
      if (aiProviderIds.contains(sid)) return false;

      // Exclude internal integration keys
      if (sid == 'ms_client_id' ||
          sid == 'google_client_id_web' ||
          sid == 'google_client_id_desktop' ||
          sid == 'google_client_secret') {
        return false;
      }

      // Exclude keys that contain OAuth data (e.g. 'spotify_api_key' storing combined client credentials)
      // Detect by checking whether any matching OAuth key exists for the same service prefix
      final prefix = sid.toUpperCase();
      final hasOAuthSibling = vaultKeys.any((other) =>
          other.toUpperCase() == '${prefix}_CLIENT_ID' ||
          other.toUpperCase() == '${prefix}_CLIENT_SECRET');
      if (hasOAuthSibling) return false;

      return true;
    }).toList()
      ..sort();

    final widgets = <Widget>[];

    if (externalKeys.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Text(
            'settings.external_services.no_keys'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontStyle: FontStyle.italic),
          ),
        ),
      );
    } else {
      for (final keyName in externalKeys) {
        final serviceId = keyName.replaceAll('_api_key', '');
        final displayName = serviceId.split('_').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
        widgets.add(_buildExistingServiceTile(serviceId, displayName));
      }
    }

    return widgets;
  }

  Widget _buildExistingServiceTile(String serviceId, String displayName) {
    final isEditing = _visibleKeyProvider == serviceId && !_isAddingNew;
    final isVerifying = _verifyingKey[serviceId] ?? false;

    return AppSettingsInput(
      title: displayName,
      translateTitle: false,
      leading: const Icon(Icons.vpn_key_outlined, size: AppConstants.iconSizeMedium, color: AppConstants.iconColorPrimary),
      controller: _getApiController(serviceId),
      isEditing: isEditing,
      isAlreadySet: true,
      isVerifying: isVerifying,
      obscureText: false,
      hint: 'settings.external_services.key_hint',
      onEdit: () async {
        final vaultKey = serviceId.endsWith('_api_key') ? serviceId : '${serviceId}_api_key';
        final key = await ref.read(configProvider.notifier).getKey(vaultKey);
        if (mounted) {
          _getApiController(serviceId).text = key ?? '';
          setState(() {
            _visibleKeyProvider = serviceId;
            _isAddingNew = false;
          });
        }
      },
      onDelete: () => _deleteApiKey(serviceId, displayName),
      onSave: () => _verifyAndSaveKey(serviceId, _getApiController(serviceId).text),
      onCancel: () => setState(() => _visibleKeyProvider = null),
      verifySaveTooltip: 'settings.api_keys.verify_save_tooltip',
      deleteTooltip: 'settings.api_keys.delete_tooltip',
    );
  }

  Widget _buildAddServiceTile() {
    return AppSettingsInput(
      title: 'settings.external_services.add_title',
      leading: const Icon(Icons.add_circle_outline, size: AppConstants.iconSizeMedium, color: AppConstants.iconColorSuccess),
      inputs: [
        AppSettingsInputField(
          controller: _newNameController,
          label: 'settings.external_services.service_name_label',
          hint: 'settings.external_services.service_name_hint',
        ),
        AppSettingsInputField(
          controller: _newKeyController,
          label: 'settings.external_services.key_label',
          hint: 'settings.external_services.key_hint',
          obscureText: false,
        ),
      ],
      isEditing: _isAddingNew,
      isAlreadySet: false,
      isVerifying: false,
      onEdit: () {
        setState(() {
          _isAddingNew = true;
          _visibleKeyProvider = null;
          _newNameController.clear();
          _newKeyController.clear();
        });
      },
      onDelete: () {},
      onSave: () {
        if (_newNameController.text.trim().isEmpty) {
          showAppErrorDialog(context, 'settings.external_services.error_empty_name'.tr());
          return;
        }
        _verifyAndSaveKey(_newNameController.text, _newKeyController.text);
      },
      onCancel: () => setState(() => _isAddingNew = false),
      addTooltip: 'settings.external_services.add_service',
    );
  }

}
