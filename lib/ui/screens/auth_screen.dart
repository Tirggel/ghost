import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/setup_wizard_provider.dart';
import '../../core/constants.dart';
import '../widgets/app_styles.dart';

import '../widgets/app_dialogs.dart';
import '../widgets/app_snackbar.dart';
import 'package:logging/logging.dart';

final _log = Logger('AuthScreen');

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _tokenController = TextEditingController();
  bool _isConnecting = false;
  String? _error;

  Future<void> _handleConnect() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'auth.error_empty'.tr());
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final client = ref.read(gatewayClientProvider);
    try {
      await client.connect();
      final success = await client.login(token);

      if (success) {
        await ref.read(authTokenProvider.notifier).setToken(token);
        // Sync language to backend settings
        if (mounted) {
          final langCode = context.locale.languageCode;
          await ref.read(configProvider.notifier).updateUser({
            'language': langCode,
          });
        }
        // Navigation is handled by the main screen listener
      } else {
        if (mounted) setState(() => _error = 'auth.error_invalid'.tr());
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _onFactoryReset() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.maintenance.factory_reset_confirm_title'.tr(),
      content: 'settings.maintenance.factory_reset_confirm_content'.tr(),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      setState(() => _isConnecting = true);
      try {
        final client = ref.read(gatewayClientProvider);

        // Try to reach the gateway to trigger a full server-side wipe
        try {
          await client.connect().timeout(const Duration(seconds: 3));
          await client.call('config.factoryReset', {});
        } catch (e) {
          _log.warning('Gateway unreachable for factory reset, proceeding with local wipe: $e');
        }

        // Always clear local state (Token & Gateway URL)
        await ref.read(authTokenProvider.notifier).logout();
        await ref
            .read(gatewayUrlProvider.notifier)
            .setUrl(AppConstants.defaultGatewayUrl);

        if (mounted) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AppAlertDialog(
              title: Text('settings.maintenance.reset_success_title'.tr()),
              content: Text('settings.maintenance.reset_success_content'.tr()),
              actions: [
                TextButton(
                  onPressed: () => exit(0),
                  child: Text(
                    'settings.maintenance.restart_button'.tr(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(context, 'Reset: $e');
        }
      } finally {
        if (mounted) setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(localeFlagsProvider);
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(AppConstants.spacingLarge),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.overlayBackground,
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(AppConstants.logoGhost, height: 55, width: 55),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppConstants.appName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'auth.tagline'.tr(),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: AppConstants.fontSizeCaption,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingTiny),
              Text(
                'auth.subtitle'.tr(),
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: AppConstants.spacingMedium),
              AppFormField.text(
                controller: _tokenController,
                label: 'auth.token_label',
                hint: 'auth.token_hint',
                obscureText: true,
                onSubmitted: (_) => _handleConnect(),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppConstants.spacingMedium),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppConstants.spacingMedium),
              AppSaveButton(
                onPressed: _handleConnect,
                label: 'auth.connect',
                isLoading: _isConnecting,
                icon: Icons.login,
                expand: true,
              ),
              const SizedBox(height: AppConstants.spacingMedium),

              const SizedBox(height: AppConstants.spacingSmall),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppLanguageTile(
                    label: 'settings.language.en'.tr(),
                    sublabel: 'English',
                    flag: flags['en'] ?? AppConstants.defaultFlags['en']!,
                    isSelected: context.locale == const Locale('en'),
                    onTap: () {
                      context.setLocale(const Locale('en'));
                      ref
                          .read(setupWizardProvider.notifier)
                          .updateLanguage('en');
                    },
                    onFlagTap: () => showAppEmojiPicker(
                      context,
                      onSelected: (e) => ref
                          .read(localeFlagsProvider.notifier)
                          .setFlag('en', e),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingTiny),
                  AppLanguageTile(
                    label: 'settings.language.de'.tr(),
                    sublabel: 'Deutsch',
                    flag: flags['de'] ?? AppConstants.defaultFlags['de']!,
                    isSelected: context.locale == const Locale('de'),
                    onTap: () {
                      context.setLocale(const Locale('de'));
                      ref
                          .read(setupWizardProvider.notifier)
                          .updateLanguage('de');
                    },
                    onFlagTap: () => showAppEmojiPicker(
                      context,
                      onSelected: (e) => ref
                          .read(localeFlagsProvider.notifier)
                          .setFlag('de', e),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingMedium),
                  TextButton.icon(
                    onPressed: _onFactoryReset,
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.textDim, size: 16),
                    label: Text(
                      'settings.maintenance.factory_reset_button'.tr(),
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

  }
}
