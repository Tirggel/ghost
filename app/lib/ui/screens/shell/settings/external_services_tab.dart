import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_settings_input.dart';
import '../../../widgets/app_dialogs.dart';

class ExternalServicesTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const ExternalServicesTab({super.key, this.onBack, this.onNext});

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
      await ref.read(configProvider.notifier).setKey(serviceId, key);
      _getApiController(serviceId).clear();
      setState(() {
        _visibleKeyProvider = null;
        _isAddingNew = false;
        _verifyingKey[serviceId] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'settings.external_services.key_saved'.tr(namedArgs: {'label': service}),
            ),
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'settings.external_services.key_removed'.tr(namedArgs: {'label': originalName}),
              ),
            ),
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
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
              ..._buildServiceSections(vaultKeys),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  List<Widget> _buildServiceSections(Set<String> vaultKeys) {
    final aiProviderIds = AppConstants.aiProviders.map((p) => p['id']).toSet();
    
    // Find external keys that end in _api_key but are not AI providers
    final externalKeys = vaultKeys.where((k) {
      if (!k.endsWith('_api_key')) return false;
      final sid = k.replaceAll('_api_key', '');
      return !aiProviderIds.contains(sid);
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
        // Create a display-friendly name nicely capitalized
        final displayName = serviceId.split('_').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
        widgets.add(_buildExistingServiceTile(serviceId, displayName));
      }
    }

    // Add Service Tile
    widgets.add(const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: AppColors.border),
    ));
    widgets.add(_buildAddServiceTile());

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
      obscureText: true,
      hint: 'settings.external_services.key_hint',
      onEdit: () {
        setState(() {
          _visibleKeyProvider = serviceId;
          _isAddingNew = false;
        });
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
          obscureText: true,
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

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onNext: widget.onNext,
    );
  }
}
