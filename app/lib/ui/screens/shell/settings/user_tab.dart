import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/business_card.dart';
import '../../../widgets/app_snackbar.dart';

class UserTab extends ConsumerStatefulWidget {
  final VoidCallback? onNext;
  const UserTab({super.key, this.onNext});

  @override
  ConsumerState<UserTab> createState() => _UserTabState();
}

class _UserTabState extends ConsumerState<UserTab> with SettingsSaveMixin {
  final _controllers = <String, TextEditingController>{};
  int _avatarNonce = 0;

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
      text: (user.avatar?.startsWith('blob:') ?? false)
          ? ''
          : (user.avatar ?? ''),
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
    await handleSave(() async {
      final avatar = _controllers['avatar']!.text;
      final config = {
        'name': _controllers['name']!.text,
        'callSign': _controllers['callSign']!.text,
        'pronouns': _controllers['pronouns']!.text,
        'notes': _controllers['notes']!.text,
        'avatar': avatar.startsWith('blob:') ? '' : avatar,
      };
      await ref.read(configProvider.notifier).updateUser(config);
    }, successMessage: 'settings.user.saved'.tr());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (prev, next) {
      final user = next.user;
      if (user.name.isNotEmpty) {
        if (_controllers['name']!.text.isEmpty) {
          _controllers['name']!.text = user.name;
        }
        if (_controllers['callSign']!.text.isEmpty) {
          _controllers['callSign']!.text = user.callSign ?? '';
        }
        if (_controllers['notes']!.text.isEmpty) {
          _controllers['notes']!.text = user.notes ?? '';
        }
        if (_controllers['avatar']!.text.isEmpty) {
          _controllers['avatar']!.text = user.avatar ?? '';
        }
      }
    });

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppConstants.settingsPagePadding,
              AppConstants.settingsTopPadding,
              AppConstants.settingsPagePadding,
              AppConstants.settingsPagePadding,
            ),
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
                onSave: _save,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  String _getPronounsDisplay(String p) {
    switch (p) {
      case 'he/him':
        return 'settings.user.pronouns_he'.tr();
      case 'she/her':
        return 'settings.user.pronouns_she'.tr();
      case 'they/them':
        return 'settings.user.pronouns_they'.tr();
      case 'ze/hir':
        return 'settings.user.pronouns_ze'.tr();
      case 'Any':
        return 'settings.user.pronouns_any'.tr();
      case 'Ask me':
        return 'settings.user.pronouns_ask'.tr();
      default:
        return p;
    }
  }

  Widget _buildPronounsDropdown() {
    return AppDropdownField<String>(
      value:
          _controllers['pronouns']!.text.isNotEmpty &&
              [
                'he/him',
                'she/her',
                'Ask me',
              ].contains(_controllers['pronouns']!.text)
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

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onSave: _save,
      onNext: widget.onNext,
      isSaveLoading: isSaveLoading,
    );
  }
}
