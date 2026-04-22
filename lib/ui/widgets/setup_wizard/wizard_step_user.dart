import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import 'setup_avatar_picker.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepUser extends ConsumerWidget {

  const WizardStepUser({
    super.key,
    required this.state,
    required this.nameController,
    required this.callSignController,
    required this.notesController,
    required this.avatarController,
    required this.avatarNonce,
    required this.onPickAvatar,
  });
  final SetupWizardState state;
  final TextEditingController nameController;
  final TextEditingController callSignController;
  final TextEditingController notesController;
  final TextEditingController avatarController;
  final int avatarNonce;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(setupWizardProvider.notifier);
    return WizardStepBase(
      icon: Icons.person,
      title: 'wizard.step_user'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardStepHeader(text: 'wizard.workspace_desc'.tr()),
          AppFormField.text(
            controller: nameController,
            label: 'settings.user.name_label',
            hint: 'settings.user.name_hint',
            onChanged: notifier.updateUserName,
            onSubmitted: notifier.updateUserName,
          ),
          AppFormField.text(
            controller: callSignController,
            label: 'settings.user.call_sign_label',
            hint: 'settings.user.call_sign_hint',
            onChanged: notifier.updateUserCallSign,
            onSubmitted: notifier.updateUserCallSign,
          ),
          AppDropdownField<String>(
            label: 'settings.user.pronouns_label',
            value: ['he/him', 'she/her', 'Ask me'].contains(state.userPronouns)
                ? state.userPronouns
                : 'Ask me',
            hint: 'settings.user.pronouns_hint',
            items: const ['he/him', 'she/her', 'Ask me'],
            displayValue: (p) {
              switch (p) {
                case 'he/him':
                  return 'settings.user.pronouns_he'.tr();
                case 'she/her':
                  return 'settings.user.pronouns_she'.tr();
                case 'Ask me':
                  return 'settings.user.pronouns_ask'.tr();
                default:
                  return p;
              }
            },
            onChanged: (val) {
              if (val != null) notifier.updateUserPronouns(val);
            },
          ),
          const SizedBox(height: 12),
          AppFormField.text(
            controller: notesController,
            label: 'settings.user.notes_label',
            hint: 'settings.user.notes_hint',
            maxLines: 3,
            onChanged: notifier.updateUserNotes,
            onSubmitted: notifier.updateUserNotes,
          ),
          SetupAvatarPicker(
            controller: avatarController,
            label: 'settings.user.avatar_label',
            type: AvatarType.user,
            nonce: avatarNonce,
            onPick: onPickAvatar,
          ),
        ],
      ),
    );
  }
}
