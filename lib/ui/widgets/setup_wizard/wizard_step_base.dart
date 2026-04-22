import 'package:flutter/material.dart';
import '../app_styles.dart';
import '../../../core/constants.dart';

class WizardStepBase extends StatelessWidget {

  const WizardStepBase({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconBox(icon: icon, color: iconColor),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppConstants.fontSizeLead,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}
