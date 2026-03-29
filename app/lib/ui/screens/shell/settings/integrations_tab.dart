import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/app_settings_input.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class IntegrationsTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const IntegrationsTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<IntegrationsTab> createState() => _IntegrationsTabState();
}

class _IntegrationsTabState extends ConsumerState<IntegrationsTab> {
  final Map<String, TextEditingController> _oauthEditControllers = {};
  String? _editingOAuthField;
  String? _acceptedDesktopClientId;
  bool _signingIn = false;

  @override
  void dispose() {
    for (final c in _oauthEditControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getOAuthEditController(String key) {
    return _oauthEditControllers.putIfAbsent(
      key,
      () => TextEditingController(),
    );
  }


  Future<bool> _verifyClientId(String clientId) async {
    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': 'dummy_auth_code_for_validation',
          'redirect_uri': 'http://localhost',
        },
      );
      final data = jsonDecode(response.body);
      if (data['error'] == 'invalid_client') {
        final desc = data['error_description'] as String? ?? '';
        if (desc.toLowerCase().contains('not found')) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyClientSecret(String clientId, String clientSecret) async {
    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'authorization_code',
          'code': 'dummy_auth_code_for_validation',
          'redirect_uri': 'http://localhost',
        },
      );
      final data = jsonDecode(response.body);
      if (data['error'] == 'invalid_client') {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveGoogleCredential(String service, String label) async {
    final value = _getOAuthEditController(service).text.trim();
    if (value.isEmpty) return;

    setState(() => _signingIn = true);
    try {
      if (service == 'google_client_id_web' || service == 'google_client_id_desktop') {
        final isValid = await _verifyClientId(value);
        if (!isValid) {
          if (mounted) {
            _getOAuthEditController(service).clear();
            AppSnackBar.showError(context, 'settings.integrations.invalid_client_id'.tr());
          }
          return;
        }
        if (service == 'google_client_id_desktop') {
          setState(() {
            _acceptedDesktopClientId = value;
            _editingOAuthField = 'google_client_secret';
          });
          if (mounted) AppSnackBar.showSuccess(context, 'settings.integrations.client_id_accepted'.tr());
          return;
        }
      } else if (service == 'google_client_secret' && _acceptedDesktopClientId != null) {
        final isValid = await _verifyClientSecret(_acceptedDesktopClientId!, value);
        if (!isValid) {
          if (mounted) {
            _getOAuthEditController(service).clear();
            AppSnackBar.showError(context, 'settings.integrations.invalid_client_secret'.tr());
          }
          return;
        }
        await ref.read(configProvider.notifier).setKey('google_client_id_desktop', _acceptedDesktopClientId!);
      }

      await ref.read(configProvider.notifier).setKey(service, value);
      _getOAuthEditController(service).clear();
      setState(() {
        _editingOAuthField = null;
        if (service == 'google_client_secret') _acceptedDesktopClientId = null;
      });
      if (mounted) AppSnackBar.showSuccess(context, 'settings.integrations.credential_saved'.tr(namedArgs: {'label': label}));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _importGoogleJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) return;
      final filePart = result.files.single;
      String content;
      if (kIsWeb) {
        content = utf8.decode(filePart.bytes!);
      } else {
        final file = File(filePart.path!);
        content = await file.readAsString();
      }
      final data = jsonDecode(content);

      String? clientId;
      String? clientSecret;

      if (kIsWeb) {
        // On Web, prioritize 'web' entry and only use client_id
        if (data.containsKey('web')) {
          clientId = data['web']['client_id'];
        } else if (data.containsKey('client_id')) {
          clientId = data['client_id'];
        }
      } else {
        // On Desktop, prioritize 'installed' entry and use client_id + secret
        if (data.containsKey('installed')) {
          clientId = data['installed']['client_id'];
          clientSecret = data['installed']['client_secret'];
        } else if (data.containsKey('web')) {
          // Fallback for some desktop-configured web IDs
          clientId = data['web']['client_id'];
          clientSecret = data['web']['client_secret'];
        } else if (data.containsKey('client_id')) {
          clientId = data['client_id'];
          clientSecret = data['client_secret'];
        }
      }

      if (clientId != null) {
        if (kIsWeb) {
          _getOAuthEditController('google_client_id_web').text = clientId;
        } else {
          _getOAuthEditController('google_client_id_desktop').text = clientId;
          if (clientSecret != null) {
            _getOAuthEditController('google_client_secret').text = clientSecret;
          }
        }
        if (mounted) {
          setState(() => _editingOAuthField = 'google_workspace');
          AppSnackBar.showSuccess(context, 'settings.integrations.credential_saved'.tr(namedArgs: {'label': 'JSON'}));
        }
      } else {
        if (mounted) AppSnackBar.showError(context, 'settings.integrations.import_json_error'.tr());
      }
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, 'settings.integrations.import_json_error'.tr());
    }
  }


  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final config = ref.watch(configProvider);
    final vaultKeys = (config.vault['keys'] as List<dynamic>?)?.cast<String>() ?? [];

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      children: [
        const AppSectionHeader('settings.integrations.google_section', large: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            authState != null
                ? 'settings.integrations.google_connected'.tr()
                : kIsWeb
                    ? 'settings.integrations.google_desc_web'.tr()
                    : 'settings.integrations.google_desc_desktop'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: AppConstants.fontSizeBody),
          ),
        ),
        if (authState != null) ...[
          AppSettingsTile(
            title: authState.displayName ?? authState.email,
            subtitle: authState.displayName != null ? authState.email : null,
            leading: AppUserAvatar(
              path: authState.photoUrl,
              radius: AppConstants.avatarRadius,
              iconSize: AppConstants.avatarIconSize,
            ),
            trailing: TextButton.icon(
              onPressed: () => ref.read(authStateProvider.notifier).signOut(),
              icon: const Icon(Icons.logout, size: AppConstants.settingsIconSize, color: AppColors.error),
              label: Text('common.sign_out'.tr(), style: const TextStyle(color: AppColors.error)),
            ),
          ),
        ],
        if (authState == null) ...[
          AppSettingsInput(
            title: 'settings.integrations.google_section',
            leading: Image.asset(AppConstants.getProviderIcon('google'), width: 24, height: 24),
            isEditing: _editingOAuthField == 'google_workspace',
            isAlreadySet: kIsWeb 
                ? vaultKeys.contains('google_client_id_web')
                : (vaultKeys.contains('google_client_id_desktop') || vaultKeys.contains('google_client_secret')),
            isVerifying: _signingIn && _editingOAuthField == 'google_workspace',
            inputs: kIsWeb
                ? [
                    AppSettingsInputField(
                      controller: _getOAuthEditController('google_client_id_web'),
                      label: 'settings.integrations.client_id_web_label',
                      hint: 'settings.integrations.client_id_missing_web',
                      obscureText: true,
                    ),
                  ]
                : [
                    AppSettingsInputField(
                      controller: _getOAuthEditController('google_client_id_desktop'),
                      label: 'settings.integrations.client_id_desktop_label',
                      hint: 'settings.integrations.client_id_missing_desktop',
                      obscureText: true,
                    ),
                    AppSettingsInputField(
                      controller: _getOAuthEditController('google_client_secret'),
                      label: 'settings.integrations.client_secret_label',
                      hint: 'settings.integrations.secret_missing',
                      obscureText: true,
                    ),
                  ],
            onEdit: () => setState(() => _editingOAuthField = 'google_workspace'),
            onImport: _importGoogleJson,
            importTooltip: 'settings.integrations.import_json_tooltip',
            onDelete: () async {
              final label = 'settings.integrations.google_section'.tr();
              final confirmed = await AppAlertDialog.showConfirmation(
                context: context,
                title: 'settings.api_keys.delete_key_title'.tr(namedArgs: {'label': label}),
                content: 'settings.api_keys.delete_key_content'.tr(namedArgs: {'label': label}),
                confirmLabel: 'common.delete'.tr(),
                isDestructive: true,
              );
              if (confirmed == true) {
                try {
                  if (kIsWeb) {
                    await ref.read(configProvider.notifier).setKey('google_client_id_web', '');
                  } else {
                    await ref.read(configProvider.notifier).setKey('google_client_id_desktop', '');
                    await ref.read(configProvider.notifier).setKey('google_client_secret', '');
                  }
                  if (!mounted) return;
                  AppSnackBar.showSuccess(context, 'settings.integrations.credential_removed'.tr(namedArgs: {'label': label}));
                } catch (e) {
                  if (!context.mounted) return;
                  showAppErrorDialog(context, e.toString());
                }
              }
            },
            onSave: () async {
              setState(() => _signingIn = true);
              try {
                if (kIsWeb) {
                  await _saveGoogleCredential('google_client_id_web', 'settings.integrations.client_id_web_label'.tr());
                } else {
                  // For desktop, we check ID first, then secret
                  final idValue = _getOAuthEditController('google_client_id_desktop').text.trim();
                  final secretValue = _getOAuthEditController('google_client_secret').text.trim();
                  
                  // Simple validation check before saving
                  if (idValue.isNotEmpty) {
                    final isValidId = await _verifyClientId(idValue);
                    if (!isValidId) {
                      if (mounted) {
                        _getOAuthEditController('google_client_id_desktop').clear();
                        AppSnackBar.showError(context, 'settings.integrations.invalid_client_id'.tr());
                      }
                      return;
                    }
                    await ref.read(configProvider.notifier).setKey('google_client_id_desktop', idValue);
                  }
                  
                  if (secretValue.isNotEmpty) {
                    if (idValue.isNotEmpty) {
                       final isValidSecret = await _verifyClientSecret(idValue, secretValue);
                       if (!isValidSecret) {
                         if (mounted) {
                           _getOAuthEditController('google_client_secret').clear();
                           AppSnackBar.showError(context, 'settings.integrations.invalid_client_secret'.tr());
                         }
                         return;
                       }
                    }
                    await ref.read(configProvider.notifier).setKey('google_client_secret', secretValue);
                  }
                  
                  if (!mounted) return;
                  AppSnackBar.showSuccess(context, 'settings.integrations.credential_saved'.tr(namedArgs: {'label': 'settings.integrations.google_section'.tr()}));
                }
                setState(() => _editingOAuthField = null);
              } catch (e) {
                if (!context.mounted) return;
                showAppErrorDialog(context, e.toString());
              } finally {
                setState(() => _signingIn = false);
              }
            },
            onCancel: () => setState(() => _editingOAuthField = null),
            verifySaveTooltip: 'settings.api_keys.verify_save_tooltip',
          ),
        ],
        const SizedBox(height: 12),
        if (_signingIn)
          const Center(child: CircularProgressIndicator())
        else if ((kIsWeb && vaultKeys.contains('google_client_id_web')) ||
            (!kIsWeb && vaultKeys.contains('google_client_id_desktop') && vaultKeys.contains('google_client_secret')))
          ElevatedButton.icon(
            onPressed: _handleGoogleSignIn,
            icon: const Icon(Icons.login, size: AppConstants.settingsIconSize),
            label: Text('settings.integrations.sign_in_google'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.black,
            ),
          ),
      ],
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _signingIn = true);
    try {
      final creds = await ref.read(configProvider.notifier).getGoogleCredentials();
      final clientId = kIsWeb ? creds['clientIdWeb'] : creds['clientIdDesktop'];
      final clientSecret = creds['clientSecret'];
      if (clientId == null || clientId.isEmpty) {
        AppSnackBar.showError(context, 'settings.integrations.client_id_missing'.tr());
        return;
      }
      await ref.read(authStateProvider.notifier).signIn(clientId: clientId, clientSecret: clientSecret ?? '');
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }
}
