import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_settings_input.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class OAuthsTab extends ConsumerStatefulWidget {
  const OAuthsTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<OAuthsTab> createState() => _OAuthsTabState();
}

class _OAuthsTabState extends ConsumerState<OAuthsTab> {
  final Map<String, TextEditingController> _controllers = {};
  String? _visibleKeyProvider;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getApiController(String service) {
    return _controllers.putIfAbsent(service, () => TextEditingController());
  }

  Future<void> _deleteOAuthService(String servicePrefix) async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.external_services.delete_key_title'.tr(
        namedArgs: {'label': servicePrefix},
      ),
      content: 'settings.external_services.delete_key_content'.tr(
        namedArgs: {'label': servicePrefix},
      ),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      try {
        final suffixes = [
          '_CLIENT_ID',
          '_CLIENT_SECRET',
          '_ACCESS_TOKEN',
          '_REFRESH_TOKEN',
        ];
        for (final suffix in suffixes) {
          await ref
              .read(configProvider.notifier)
              .setKey('${servicePrefix}${suffix}', '');
        }
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.external_services.key_removed'.tr(
              namedArgs: {'label': servicePrefix},
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          showAppErrorDialog(context, e.toString());
        }
      }
    }
  }

  Widget _buildAddCustomKeyButton() {
    return AppSettingsInput(
      title: 'settings.oauths.add_button',
      leading: const Icon(
        Icons.add_moderator,
        size: AppConstants.iconSizeMedium,
        color: AppConstants.iconColorSuccess,
      ),
      inputs: [
        AppSettingsInputField(
          controller: _getApiController('__new_name__'),
          label: 'settings.oauths.name_label',
          hint: 'settings.oauths.name_label',
        ),
        AppSettingsInputField(
          controller: _getApiController('__new_client_id__'),
          label: 'settings.oauths.client_id_label',
          hint: 'settings.oauths.client_id_label',
          obscureText: false,
        ),
        AppSettingsInputField(
          controller: _getApiController('__new_client_secret__'),
          label: 'settings.oauths.client_secret_label',
          hint: 'settings.oauths.client_secret_label',
          obscureText: true,
        ),
      ],
      isEditing: _visibleKeyProvider == '__new__',
      isAlreadySet: false,
      onEdit: () {
        _getApiController('__new_name__').clear();
        _getApiController('__new_client_id__').clear();
        _getApiController('__new_client_secret__').clear();
        setState(() => _visibleKeyProvider = '__new__');
      },
      onDelete: () {},
      onSave: () => _saveNewOAuthService(),
      onCancel: () => setState(() => _visibleKeyProvider = null),
      addTooltip: 'settings.oauths.add_button',
    );
  }

  Future<void> _saveNewOAuthService() async {
    final name = _getApiController('__new_name__').text.trim().toUpperCase();
    final clientId = _getApiController('__new_client_id__').text.trim();
    final clientSecret = _getApiController('__new_client_secret__').text.trim();

    if (name.isEmpty) {
      if (mounted)
        showAppErrorDialog(context, 'settings.oauths.name_required'.tr());
      return;
    }

    try {
      await ref
          .read(configProvider.notifier)
          .setKey('${name}_CLIENT_ID', clientId);
      await ref
          .read(configProvider.notifier)
          .setKey('${name}_CLIENT_SECRET', clientSecret);
      setState(() => _visibleKeyProvider = null);
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.oauths.save_success'.tr(namedArgs: {'name': name}),
        );
      }
    } catch (e) {
      if (mounted) showAppErrorDialog(context, e.toString());
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
        const AppSectionHeader('settings.oauths.section', large: true),
        Text(
          'settings.oauths.desc'.tr(),
          style: const TextStyle(
            fontSize: AppConstants.fontSizeBody,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: 16),
        _buildAddCustomKeyButton(),
        const SizedBox(height: 16),
        ..._buildCustomVaultSection(vaultKeys, config),
      ],
    );
  }

  List<Widget> _buildCustomVaultSection(
    Set<String> vaultKeys,
    AppConfig config,
  ) {
    // Filter for OAuth related keys only
    final oauthSuffixes = [
      '_CLIENT_ID',
      '_CLIENT_SECRET',
      '_ACCESS_TOKEN',
      '_REFRESH_TOKEN',
      '_client_id',
      '_client_secret',
      '_access_token',
      '_refresh_token',
    ];

    // Group keys by service prefix
    final groupedOAuths = <String, Set<String>>{};
    for (final key in vaultKeys) {
      for (final suffix in oauthSuffixes) {
        if (key.endsWith(suffix)) {
          final prefix = key
              .substring(0, key.length - suffix.length)
              .toUpperCase();
          if (prefix.isNotEmpty) {
            groupedOAuths.putIfAbsent(prefix, () => <String>{}).add(key);
          }
        }
      }
    }

    final services = groupedOAuths.keys.toList()..sort();

    if (services.isEmpty) return [];

    return [
      const AppSectionHeader('settings.oauths.custom_section', large: false),
      const SizedBox(height: 8),
      ...services.map(
        (service) =>
            _buildOAuthServiceTile(service, groupedOAuths[service]!, config),
      ),
    ];
  }

  Widget _buildOAuthServiceTile(
    String service,
    Set<String> keys,
    AppConfig config,
  ) {
    final isEditing = _visibleKeyProvider == service;
    final hasClientId = keys.any((k) => k.endsWith('_CLIENT_ID'));
    final hasClientSecret = keys.any((k) => k.endsWith('_CLIENT_SECRET'));

    final inputs = <AppSettingsInputField>[];
    if (hasClientId) {
      inputs.add(
        AppSettingsInputField(
          controller: _getApiController('${service}_CLIENT_ID'),
          label: 'settings.oauths.client_id_label',
          hint: 'settings.oauths.client_id_label',
          obscureText: false,
        ),
      );
    }
    if (hasClientSecret) {
      inputs.add(
        AppSettingsInputField(
          controller: _getApiController('${service}_CLIENT_SECRET'),
          label: 'settings.oauths.client_secret_label',
          hint: 'settings.oauths.client_secret_label',
          obscureText: true,
        ),
      );
    }

    // Add others if they exist
    for (final k in keys) {
      if (!k.endsWith('_CLIENT_ID') && !k.endsWith('_CLIENT_SECRET')) {
        inputs.add(
          AppSettingsInputField(
            controller: _getApiController(k),
            label: k.split('_').last.replaceAll('_', ' '),
            hint: k,
            obscureText: true,
          ),
        );
      }
    }

    return AppSettingsInput(
      title: service,
      translateTitle: false,
      leading: const Icon(
        Icons.security_outlined,
        color: AppColors.primary,
        size: 20,
      ),
      inputs: inputs,
      isEditing: isEditing,
      isAlreadySet: true,
      onEdit: () async {
        for (final k in keys) {
          final val = await ref.read(configProvider.notifier).getKey(k);
          _getApiController(k).text = val ?? '';
        }
        if (mounted) {
          setState(() => _visibleKeyProvider = service);
        }
      },
      onDelete: () => _deleteOAuthService(service),
      onSave: () async {
        for (final input in inputs) {
          final k = keys.firstWhere(
            (key) => _controllers[key] == input.controller,
          );
          await ref
              .read(configProvider.notifier)
              .setKey(k, input.controller.text.trim());
        }
        setState(() => _visibleKeyProvider = null);
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.oauths.save_success'.tr(namedArgs: {'name': service}),
          );
        }
      },
      onCancel: () => setState(() => _visibleKeyProvider = null),
    );
  }
}
