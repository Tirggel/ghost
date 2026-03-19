import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/app_settings_input.dart';

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
          if (mounted) _showSnackBar('settings.integrations.invalid_client_id'.tr(), isError: true);
          return;
        }
        if (service == 'google_client_id_desktop') {
          setState(() {
            _acceptedDesktopClientId = value;
            _editingOAuthField = 'google_client_secret';
          });
          if (mounted) _showSnackBar('settings.integrations.client_id_accepted'.tr());
          return;
        }
      } else if (service == 'google_client_secret' && _acceptedDesktopClientId != null) {
        final isValid = await _verifyClientSecret(_acceptedDesktopClientId!, value);
        if (!isValid) {
          if (mounted) _showSnackBar('settings.integrations.invalid_client_secret'.tr(), isError: true);
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
      if (mounted) _showSnackBar('settings.integrations.credential_saved'.tr(namedArgs: {'label': label}));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.errorDark : AppColors.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final config = ref.watch(configProvider);
    final vaultKeys = (config.vault['keys'] as List<dynamic>?)?.cast<String>() ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
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
                  onDelete: () async {
                    final label = 'settings.integrations.google_section'.tr();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        title: Text('settings.api_keys.delete_key_title'.tr(namedArgs: {'label': label})),
                        content: Text('settings.api_keys.delete_key_content'.tr(namedArgs: {'label': label})),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('common.cancel'.tr()),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('common.delete'.tr(), style: const TextStyle(color: AppColors.errorDark)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      try {
                        if (kIsWeb) {
                          await ref.read(configProvider.notifier).setKey('google_client_id_web', '');
                        } else {
                          await ref.read(configProvider.notifier).setKey('google_client_id_desktop', '');
                          await ref.read(configProvider.notifier).setKey('google_client_secret', '');
                        }
                        if (mounted) _showSnackBar('settings.integrations.credential_removed'.tr(namedArgs: {'label': label}));
                      } catch (e) {
                        if (mounted) showAppErrorDialog(context, e.toString());
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
                            if (mounted) _showSnackBar('settings.integrations.invalid_client_id'.tr(), isError: true);
                            return;
                          }
                          await ref.read(configProvider.notifier).setKey('google_client_id_desktop', idValue);
                        }
                        
                        if (secretValue.isNotEmpty) {
                          if (idValue.isNotEmpty) {
                             final isValidSecret = await _verifyClientSecret(idValue, secretValue);
                             if (!isValidSecret) {
                               if (mounted) _showSnackBar('settings.integrations.invalid_client_secret'.tr(), isError: true);
                               return;
                             }
                          }
                          await ref.read(configProvider.notifier).setKey('google_client_secret', secretValue);
                        }
                        
                        if (mounted) _showSnackBar('settings.integrations.credential_saved'.tr(namedArgs: {'label': 'settings.integrations.google_section'.tr()}));
                      }
                      setState(() => _editingOAuthField = null);
                    } catch (e) {
                      if (mounted) showAppErrorDialog(context, e.toString());
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
          ),
        ),
        _buildNavButtons(),
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
        _showSnackBar('settings.integrations.client_id_missing'.tr(), isError: true);
        return;
      }
      await ref.read(authStateProvider.notifier).signIn(clientId: clientId, clientSecret: clientSecret ?? '');
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onNext: widget.onNext,
    );
  }
}
