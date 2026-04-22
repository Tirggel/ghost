import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';

class BrowserTab extends ConsumerStatefulWidget {
  const BrowserTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<BrowserTab> with SettingsSaveMixin {
  late bool _browserHeadless;

  @override
  void initState() {
    super.initState();
    _browserHeadless = ref.read(configProvider).tools.browserHeadless;
  }

  Future<void> _save() async {
    await handleSave(() async {
      await ref.read(configProvider.notifier).updateTools({
        'browserHeadless': _browserHeadless,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
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
              const AppSectionHeader('settings.browser.section', large: true),
              Text(
                'settings.browser.headless_desc'.tr(),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: AppConstants.fontSizeBody,
                ),
              ),
              const SizedBox(height: 24),
              AppSettingsTile(
                title: 'settings.browser.headless_label'.tr(),
                subtitle: _browserHeadless 
                    ? 'settings.browser.headless'.tr() 
                    : 'settings.browser.headful'.tr(),
                leading: const Icon(
                  Icons.open_in_browser,
                  color: AppConstants.iconColorPrimary,
                  size: AppConstants.iconSizeLarge,
                ),
                trailing: Switch(
                  value: _browserHeadless,
                  onChanged: (val) async {
                    setState(() => _browserHeadless = val);
                    await _save();
                  },
                  activeThumbColor: AppColors.primary,
                ),
                onTap: () async {
                  setState(() => _browserHeadless = !_browserHeadless);
                  await _save();
                },
              ),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onSave: _save,
      onNext: widget.onNext,
      isSaveLoading: isSaveLoading,
    );
  }
}
