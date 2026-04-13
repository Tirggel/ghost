import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';
import 'app_styles.dart';

/// Helper class for defining multiple inputs in [AppSettingsInput]
class AppSettingsInputField {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;

  const AppSettingsInputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
  });
}

/// A reusable settings input widget for credentials (API keys, client IDs, etc.)
class AppSettingsInput extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final TextEditingController? controller;
  final List<AppSettingsInputField>? inputs;
  final bool isEditing;
  final bool isAlreadySet;
  final bool isVerifying;
  final bool obscureText;
  final String? hint;
  final String? labelText;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? deleteTooltip;
  final String? editTooltip;
  final String? addTooltip;
  final String? verifySaveTooltip;
  final String? importTooltip;
  final Map<String, String>? hintArgs;
  final Map<String, String>? labelTextArgs;
  final VoidCallback? onImport;
  final bool translateTitle;
  final bool translateSubtitle;
  final Widget? extraChild;

  const AppSettingsInput({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.controller,
    this.inputs,
    required this.isEditing,
    required this.isAlreadySet,
    this.isVerifying = false,
    this.obscureText = false,
    this.hint,
    this.labelText,
    required this.onEdit,
    required this.onDelete,
    required this.onSave,
    required this.onCancel,
    this.deleteTooltip,
    this.editTooltip,
    this.addTooltip,
    this.verifySaveTooltip,
    this.importTooltip,
    this.hintArgs,
    this.labelTextArgs,
    this.onImport,
    this.translateTitle = true,
    this.translateSubtitle = true,
    this.extraChild,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingsTile(
      title: translateTitle ? title.tr() : title,
      subtitle: translateSubtitle ? subtitle?.tr() : subtitle,
      leading: leading,
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isAlreadySet && !isEditing)
            IconButton(
              icon: const Icon(Icons.add, size: AppConstants.settingsIconSize),
              onPressed: onEdit,
              tooltip: addTooltip?.tr(),
            ),
          if (isAlreadySet && !isEditing) ...[
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: AppConstants.settingsIconSize,
              ),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.white,
              ).copyWith(
                foregroundColor:
                    WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.hovered)) {
                        return AppColors.error;
                      }
                      return AppColors.white;
                    }),
              ),
              onPressed: onDelete,
              tooltip: deleteTooltip?.tr(),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: AppConstants.settingsIconSize,
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: AppConstants.settingsIconSize),
              onPressed: onEdit,
              tooltip: (editTooltip ?? verifySaveTooltip)?.tr(),
            ),
          ],
          if (onImport != null && !isEditing)
            IconButton(
              icon: const Icon(Icons.file_upload_outlined,
                  size: AppConstants.settingsIconSize),
              onPressed: onImport,
              tooltip: importTooltip?.tr(),
            ),
        ],
      ),
      child: isEditing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (inputs != null)
                  ...inputs!.map((input) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextField(
                          controller: input.controller,
                          obscureText: input.obscureText,
                          decoration: AppInputDecoration.compact(
                            hint: input.hint.tr(),
                          ).copyWith(
                            labelText: input.label.tr(),
                          ),
                          style: const TextStyle(fontSize: AppConstants.fontSizeBody),
                          onSubmitted: (_) => onSave(),
                        ),
                      ))
                else if (controller != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: controller!,
                      obscureText: obscureText,
                      decoration: AppInputDecoration.compact(
                        hint: hint?.tr(namedArgs: hintArgs),
                      ).copyWith(
                        labelText: labelText?.tr(namedArgs: labelTextArgs),
                      ),
                      style: const TextStyle(fontSize: AppConstants.fontSizeBody),
                      onSubmitted: (_) => onSave(),
                    ),
                  ),
                if (extraChild != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: extraChild!,
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isVerifying)
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      AppSaveButton(
                        onPressed: onSave,
                        label: 'common.save',
                        icon: Icons.save,
                      ),
                    const SizedBox(width: 4),
                    AppCloseButton(
                      onPressed: onCancel,
                    ),
                  ],
                ),
              ],
            )
          : null,
    );
  }
}
