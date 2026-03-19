import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/setup_wizard_provider.dart';
import '../../core/constants.dart';
import '../widgets/app_styles.dart';

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
          await ref.read(configProvider.notifier).updateUser({'language': langCode});
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

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(localeFlagsProvider);
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
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
              const Text(
                '👻 ${AppConstants.appName}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'auth.subtitle'.tr(),
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 32),
              AppFormField.text(
                controller: _tokenController,
                label: 'auth.token_label',
                hint: 'auth.token_hint',
                obscureText: true,
                onSubmitted: (_) => _handleConnect(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 32),
              AppSaveButton(
                onPressed: _handleConnect,
                label: 'auth.connect',
                isLoading: _isConnecting,
                icon: Icons.login,
                expand: true,
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),
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
                  const SizedBox(height: 8),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
