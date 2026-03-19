import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/locale_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/business_card.dart';

class ProfileTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const ProfileTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> with SingleTickerProviderStateMixin {
  final _controllers = <String, TextEditingController>{};
  int _avatarNonce = 0;
  int _currentIndex = 0;

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

    _controllers['name'] = TextEditingController(text: user.name);
    _controllers['callSign'] = TextEditingController(text: user.callSign);
    _controllers['pronouns'] = TextEditingController(text: user.pronouns);
    _controllers['notes'] = TextEditingController(text: user.notes);
    _controllers['avatar'] = TextEditingController(
      text: (user.avatar?.startsWith('blob:') ?? false) ? '' : (user.avatar ?? ''),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.user.saved'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(localeFlagsProvider);
    
    ref.listen(configProvider, (prev, next) {
      final user = next.user;
      if (user.name.isNotEmpty) {
        if (_controllers['name']!.text.isEmpty) _controllers['name']!.text = user.name;
        if (_controllers['callSign']!.text.isEmpty) _controllers['callSign']!.text = user.callSign ?? '';
        if (_controllers['notes']!.text.isEmpty) _controllers['notes']!.text = user.notes ?? '';
        if (_controllers['avatar']!.text.isEmpty) _controllers['avatar']!.text = user.avatar ?? '';
      }
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: AppDropdownField<int>(
            value: _currentIndex,
            items: List.generate(_subTabLabels.length, (index) => index),
            onChanged: (index) {
              if (index != null) {
                setState(() => _currentIndex = index);
              }
            },
            displayValue: (index) => _subTabLabels[index].tr(),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildUserTab(),
              _buildLanguageTab(flags),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserTab() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BusinessCard(
                title: 'settings.user.section',
                avatar: ListenableBuilder(
                  listenable: _controllers['avatar']!,
                  builder: (context, _) => GestureDetector(
                    onTap: _onPickAvatar,
                    child: Stack(
                      children: [
                        AppUserAvatar(
                          path: _controllers['avatar']!.text,
                          radius: 46,
                          iconSize: 32,
                          extraVersion: _avatarNonce,
                        ),
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
          ),
        ),
        _buildNavButtons(
          onBack: widget.onBack,
          onNext: () => setState(() => _currentIndex = 1),
        ),
      ],
    );
  }

  Widget _buildLanguageTab(Map<String, String> flags) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
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
                    }
                  },
                );
              }),
            ],
          ),
        ),
        _buildNavButtons(
          onBack: () => setState(() => _currentIndex = 0),
          onNext: widget.onNext,
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('file_picker.pick_error'.tr(namedArgs: {'error': e.toString()})),
            backgroundColor: AppColors.errorDark,
          ),
        );
      }
    }
  }

  Widget _buildNavButtons({VoidCallback? onBack, VoidCallback? onNext}) {
    return AppSettingsNavBar(
      onBack: onBack,
      onSave: _save,
      onNext: onNext,
    );
  }
}
