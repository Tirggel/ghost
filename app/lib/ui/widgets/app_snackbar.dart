import 'package:flutter/material.dart';
import '../../core/constants.dart';

class AppSnackBar {
  const AppSnackBar._();

  static void show(BuildContext context, String message, {IconData? icon, Color? iconColor}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor ?? AppColors.white, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void showError(BuildContext context, String message) {
    show(
      context, 
      message, 
      icon: Icons.error_outline, 
      iconColor: AppColors.white, // White icon on red background
    );
  }

  static void showSuccess(BuildContext context, String message) {
    show(
      context, 
      message, 
      icon: Icons.check_circle_outline, 
      iconColor: AppColors.success,
    );
  }

  static void showGlobal(String message, {bool isError = false}) {
    final state = AppConstants.snackbarKey.currentState;
    if (state == null) return;
    
    state.hideCurrentSnackBar();
    state.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? AppColors.white : AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.errorDark : null,
      ),
    );
  }
}
