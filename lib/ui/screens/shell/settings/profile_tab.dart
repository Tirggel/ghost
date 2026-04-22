import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/locale_provider.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/business_card.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> 
    with SingleTickerProviderStateMixin, SettingsSaveMixin {
  final _controllers = <String, TextEditingController>{};
  int _avatarNonce = 0;

  final List<String> _subTabLabels = [
    'settings.user.tab',
    'settings.language.tab',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  void _loadInitialValues() {
    final config = ref.read(configProvider);
    final user = config.user;

    final nameText = user.name;
    final callSignText = user.callSign ?? '';
    final pronounsText = user.pronouns ?? '';
    final notesText = user.notes ?? '';
    final avatarText = (user.avatar?.startsWith('blob:') ?? false) ? '' : (user.avatar ?? '');

    if (_controllers.isEmpty) {
      _controllers['name'] = TextEditingController(text: nameText);
      _controllers['callSign'] = TextEditingController(text: callSignText);
      _controllers['pronouns'] = TextEditingController(text: pronounsText);
      _controllers['notes'] = TextEditingController(text: notesText);
      _controllers['avatar'] = TextEditingController(text: avatarText);
    } else {
      _controllers['name']!.text = nameText;
      _controllers['callSign']!.text = callSignText;
      _controllers['pronouns']!.text = pronounsText;
      _controllers['notes']!.text = notesText;
      _controllers['avatar']!.text = avatarText;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await handleSave(() async {
      final avatar = _controllers['avatar']!.text;
      final langCode = context.locale.languageCode;

      final config = {
        'name': _controllers['name']!.text,
        'callSign': _controllers['callSign']!.text,
        'pronouns': _controllers['pronouns']!.text,
        'notes': _controllers['notes']!.text,
        'avatar': avatar.startsWith('blob:') ? '' : avatar,
        'language': langCode,
      };

      await ref.read(configProvider.notifier).updateUser(config);
    }, successMessage: 'settings.user.saved'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(localeFlagsProvider);
    final currentIndex = ref.watch(shellProvider.select((s) => s.settingsSubTabIndices[0] ?? 0));
    
    ref.listen(configProvider, (prev, next) {
      if (!isSaveLoading && prev != null && prev.user != next.user) {
        // If the configuration changed significantly (e.g. after restore), 
        // we force-refresh the controllers. 
        _loadInitialValues();
      }
    });


    return AppSettingsPage(
      subTabLabels: _subTabLabels,
      currentSubTabIndex: currentIndex,
      onSubTabChanged: (index) => ref.read(shellProvider.notifier).setSettingsSubTabIndex(0, index),
      onBack: currentIndex == 0 ? widget.onBack : () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(0, 0),
      onNext: currentIndex == 0 ? () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(0, 1) : widget.onNext,
      body: IndexedStack(
        index: currentIndex,
        children: [
          _buildUserTabContent(),
          _buildLanguageTabContent(flags),
        ],
      ),
    );
  }

  Widget _buildUserTabContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.settingsPagePadding,
        0,
        AppConstants.settingsPagePadding,
        AppConstants.settingsPagePadding,
      ),
      children: [
        BusinessCard(
          title: 'settings.user.section',
          avatarBuilder: (context, isEditing) => ListenableBuilder(
            listenable: _controllers['avatar']!,
            builder: (context, _) => GestureDetector(
              onTap: isEditing ? _onPickAvatar : null,
              child: Stack(
                children: [
                  AppUserAvatar(
                    path: _controllers['avatar']!.text,
                    radius: 46,
                    iconSize: 32,
                    extraVersion: _avatarNonce,
                  ),
                  if (isEditing)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 14,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          fields: [
            BusinessCardField(
              label: 'settings.user.name_label',
              hint: 'settings.user.name_hint',
              controller: _controllers['name']!,
            ),
            BusinessCardField(
              label: 'settings.user.call_sign_label',
              hint: 'settings.user.call_sign_hint',
              controller: _controllers['callSign']!,
            ),
            BusinessCardField(
              label: 'settings.user.pronouns_label',
              hint: 'settings.user.pronouns_hint',
              controller: _controllers['pronouns']!,
              value: _getPronounsDisplay(_controllers['pronouns']!.text),
              customEditWidget: _buildPronounsDropdown(),
            ),
            BusinessCardField(
              label: 'settings.user.notes_label',
              hint: 'settings.user.notes_hint',
              controller: _controllers['notes']!,
              maxLines: 3,
            ),
          ],
          maxViewFields: 3,
          onSave: _save,
        ),
      ],
    );
  }

  Widget _buildLanguageTabContent(Map<String, String> flags) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.settingsPagePadding,
        0,
        AppConstants.settingsPagePadding,
        AppConstants.settingsPagePadding,
      ),
      children: [
        const AppSectionHeader('settings.language.section', large: true),
        const SizedBox(height: 12),
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
    );
  }

  String _getPronounsDisplay(String p) {
    switch (p) {
      case 'he/him': return 'settings.user.pronouns_he'.tr();
      case 'she/her': return 'settings.user.pronouns_she'.tr();
      case 'they/them': return 'settings.user.pronouns_they'.tr();
      case 'ze/hir': return 'settings.user.pronouns_ze'.tr();
      case 'Any': return 'settings.user.pronouns_any'.tr();
      case 'Ask me': return 'settings.user.pronouns_ask'.tr();
      default: return p;
    }
  }

  Widget _buildPronounsDropdown() {
    return AppDropdownField<String>(
      value: _controllers['pronouns']!.text.isNotEmpty &&
              ['he/him', 'she/her', 'Ask me'].contains(_controllers['pronouns']!.text)
          ? _controllers['pronouns']!.text
          : null,
      label: 'settings.user.pronouns_label',
      hint: 'settings.user.pronouns_hint',
      items: const ['he/him', 'she/her', 'Ask me'],
      displayValue: _getPronounsDisplay,
      onChanged: (val) {
        if (val != null) {
          setState(() => _controllers['pronouns']!.text = val);
        }
      },
    );
  }

  Future<void> _onPickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final name = result.files.single.name;
        final wsUrl = await ref.read(gatewayUrlProvider.future);

        final notifier = ref.read(configProvider.notifier);
        final String? path = await notifier.uploadAvatar(name, bytes, wsUrl);
        if (path != null) {
          setState(() {
            _controllers['avatar']!.text = path;
            _avatarNonce++;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}),
        );
      }
    }
  }

}
