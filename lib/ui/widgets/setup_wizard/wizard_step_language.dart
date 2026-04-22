import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepLanguage extends ConsumerWidget {
  const WizardStepLanguage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch locale for immediate updates
    context.locale;
    final flags = ref.watch(localeFlagsProvider);

    return WizardStepBase(
      icon: Icons.language,
      title: 'wizard.step_language'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardStepHeader(text: 'settings.language.select'.tr()),
          _languageTile(
            context,
            ref,
            const Locale('en'),
            'settings.language.en'.tr(),
            'English',
            flags['en'] ?? AppConstants.defaultFlags['en']!,
          ),
          _languageTile(
            context,
            ref,
            const Locale('de'),
            'settings.language.de'.tr(),
            'Deutsch',
            flags['de'] ?? AppConstants.defaultFlags['de']!,
          ),
        ],
      ),
    );
  }

  Widget _languageTile(
    BuildContext context,
    WidgetRef ref,
    Locale locale,
    String label,
    String sublabel,
    String flag,
  ) {
    return AppLanguageTile(
      flag: flag,
      label: label,
      sublabel: sublabel,
      isSelected: context.locale == locale,
      onTap: () {
        context.setLocale(locale);
        ref.read(setupWizardProvider.notifier).updateLanguage(locale.languageCode);
      },
      onFlagTap: () {
        showAppEmojiPicker(
          context,
          onSelected: (e) {
            ref
                .read(localeFlagsProvider.notifier)
                .setFlag(locale.languageCode, e);
          },
        );
      },
    );
  }
}
