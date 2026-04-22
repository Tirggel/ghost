import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../../../providers/setup_wizard_provider.dart';
import '../app_styles.dart';
import 'setup_avatar_picker.dart';
import 'wizard_step_base.dart';
import 'wizard_utils.dart';

class WizardStepIdentity extends ConsumerWidget {

  const WizardStepIdentity({
    super.key,
    required this.state,
    required this.nameController,
    required this.creatureController,
    required this.vibeController,
    required this.emojiController,
    required this.notesController,
    required this.avatarController,
    required this.avatarNonce,
    required this.onPickAvatar,
  });
  final SetupWizardState state;
  final TextEditingController nameController;
  final TextEditingController creatureController;
  final TextEditingController vibeController;
  final TextEditingController emojiController;
  final TextEditingController notesController;
  final TextEditingController avatarController;
  final int avatarNonce;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(setupWizardProvider.notifier);

    return WizardStepBase(
      icon: Icons.auto_awesome,
      title: 'wizard.step_identity'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.selectedProvider != null && state.selectedModel != null)
            WizardSummaryBadge(
              iconPath: AppConstants.getProviderIcon(state.selectedProvider!),
              label: state.selectedModel!.contains('/')
                  ? state.selectedModel!.split('/').last
                  : state.selectedModel!,
            ),
          WizardStepHeader(text: 'wizard.identity_desc'.tr()),
          AppFormField.text(
            controller: nameController,
            label: 'settings.user.name_label',
            hint: 'settings.identity.name_hint',
            onSubmitted: notifier.updateIdentName,
          ),
          AppFormField.text(
            controller: creatureController,
            label: 'settings.identity.creature_label',
            hint: 'settings.identity.creature_hint',
            onSubmitted: notifier.updateIdentCreature,
          ),
          AppFormField.text(
            controller: vibeController,
            label: 'settings.identity.vibe_label',
            hint: 'settings.identity.vibe_hint',
            onSubmitted: notifier.updateIdentVibe,
          ),
          _emojiPicker(context, notifier),
          AppFormField.text(
            controller: notesController,
            label: 'settings.user.notes_label',
            hint: 'settings.identity.notes_hint',
            maxLines: 3,
            onSubmitted: notifier.updateIdentNotes,
          ),
          SetupAvatarPicker(
            controller: avatarController,
            label: 'settings.user.avatar_label',
            type: AvatarType.identity,
            nonce: avatarNonce,
            onPick: onPickAvatar,
          ),
        ],
      ),
    );
  }

  Widget _emojiPicker(BuildContext context, SetupWizardNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppFormLabel('settings.identity.emoji_label'),
          const SizedBox(height: 6),
          Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => showAppEmojiPicker(
                    context,
                    onSelected: (e) {
                      emojiController.text = e;
                      notifier.updateIdentEmoji(e);
                    },
                  ),
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(
                        AppConstants.buttonBorderRadius,
                      ),
                      color: AppColors.surface,
                    ),
                    child: Text(
                      emojiController.text,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => showAppEmojiPicker(
                  context,
                  onSelected: (e) {
                    emojiController.text = e;
                    notifier.updateIdentEmoji(e);
                  },
                ),
                child: Text('settings.identity.pick_emoji'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
