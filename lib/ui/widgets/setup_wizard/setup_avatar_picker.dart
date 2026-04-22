import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../app_styles.dart';
export '../avatar_widget.dart';
import '../avatar_widget.dart';

class SetupAvatarPicker extends StatelessWidget {

  const SetupAvatarPicker({
    super.key,
    required this.controller,
    required this.label,
    required this.nonce,
    required this.onPick,
    required this.type,
    this.fallbackEmoji,
  });
  final TextEditingController controller;
  final String label;
  final int nonce;
  final String? fallbackEmoji;
  final AvatarType type;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppFormLabel(label),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (type == AvatarType.user)
                    AppUserAvatar(
                      path: controller.text,
                      radius: AppConstants.avatarRadius,
                      iconSize: AppConstants.iconSizeLarge,
                      extraVersion: nonce,
                    )
                  else
                    AppIdentityAvatar(
                      path: controller.text,
                      emoji: fallbackEmoji,
                      radius: AppConstants.avatarRadius,
                      iconSize: AppConstants.iconSizeLarge,
                      extraVersion: nonce,
                    ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.upload_file, size: AppConstants.iconSizeTiny),
                    label: Text('wizard.pick_avatar'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.buttonBorderRadius,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
