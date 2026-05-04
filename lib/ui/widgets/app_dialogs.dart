import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';

class AppAlertDialog extends StatelessWidget {

  const AppAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });
  final Widget title;
  final Widget content;
  final List<Widget>? actions;

  /// Standard factory for confirmation dialogs
  static Future<bool?> showConfirmation({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(title),
        content: Text(
          content,
          style: const TextStyle(height: 1.4, fontSize: 13, color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel ?? 'common.cancel'.tr(),
              style: const TextStyle(color: AppColors.textDim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel ?? 'common.ok'.tr(),
              style: TextStyle(
                color: isDestructive ? AppColors.errorDark : AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Standard factory for error dialogs
  static Future<void> showError({
    required BuildContext context,
    required String message,
    String? title,
    VoidCallback? onOk,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Text(title ?? 'common.error'.tr()),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(height: 1.4, fontSize: 13, color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onOk?.call();
            },
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  /// Standard factory for text input dialogs
  static Future<String?> showTextInput({
    required BuildContext context,
    required String title,
    String? initialValue,
    String? hintText,
    String? confirmLabel,
    String? cancelLabel,
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: AppColors.textDim),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              cancelLabel ?? 'common.cancel'.tr(),
              style: const TextStyle(color: AppColors.textDim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              confirmLabel ?? 'common.save'.tr(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusDefault),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: DefaultTextStyle.merge(
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.white,
        ),
        child: title,
      ),
      content: content,
      actions: actions,
    );
  }
}
