import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/locale_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_snackbar.dart';

class LanguageTab extends ConsumerWidget {
  const LanguageTab({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(localeFlagsProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.settingsPagePadding,
              AppConstants.settingsTopPadding,
              AppConstants.settingsPagePadding,
              AppConstants.settingsPagePadding,
            ),
            children: [
              const AppSectionHeader('settings.language.section', large: true),
              ...context.supportedLocales.map((locale) {
                final langCode = locale.languageCode;
                final label = 'settings.language.$langCode'.tr();
                final sublabel = 'settings.language.${langCode}_native'.tr();
                final flag = flags[langCode] ?? AppConstants.defaultFlags[langCode] ?? '🌐';
                final isSelected = context.locale == locale;

                return AppLanguageTile(
                  label: label,
                  sublabel: sublabel,
                  flag: flag,
                  isSelected: isSelected,
                  onTap: () async {
                    if (!isSelected) {
                      await context.setLocale(locale);
                      if (context.mounted) {
                        await ref.read(configProvider.notifier).updateUser({'language': locale.languageCode});
                        if (context.mounted) {
                          AppSnackBar.showSuccess(context, 'common.saved'.tr());
                        }
                      }
                    }
                  },
                );
              }),
            ],
          ),
        ),
        _buildNavButtons(context, ref),
      ],
    );
  }

  Widget _buildNavButtons(BuildContext context, WidgetRef ref) {
    return AppSettingsNavBar(
      onBack: onBack,
    );
  }
}
