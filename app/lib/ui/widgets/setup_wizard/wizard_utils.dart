import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../app_styles.dart';

class WizardStepHeader extends StatelessWidget {
  final String text;

  const WizardStepHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textDim,
          fontSize: AppConstants.fontSizeBody,
        ),
      ),
    );
  }
}

class WizardInfoCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const WizardInfoCard({
    super.key,
    this.icon = Icons.info_outline,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WizardVerificationField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isVerifying;
  final bool isVerified;
  final String? error;
  final VoidCallback onVerify;
  final ValueChanged<String>? onChanged;
  final bool obscureText;

  const WizardVerificationField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.isVerifying,
    required this.isVerified,
    required this.onVerify,
    this.error,
    this.onChanged,
    this.obscureText = true,
  });

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFormLabel(label),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) {
                    onVerify();
                  }
                },
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  decoration: AppInputDecoration.compact(hint: hint),
                  style: const TextStyle(fontSize: 13),
                  onChanged: onChanged,
                  onSubmitted: (_) => onVerify(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (isVerifying)
              const SizedBox(
                width: 36,
                height: 36,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              ElevatedButton(
                onPressed: onVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isVerified ? AppColors.success : AppColors.primary,
                  foregroundColor: AppColors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.buttonBorderRadius,
                    ),
                  ),
                ),
                child: Text(
                  isVerified
                      ? 'wizard.key_verified'.tr()
                      : 'wizard.verify_key'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(color: AppColors.errorDark, fontSize: 12),
          ),
        ],
        if (isVerified) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 16),
              const SizedBox(width: 6),
              Text(
                'wizard.key_verified_desc'.tr(), // Generic verified text
                style: const TextStyle(color: AppColors.success, fontSize: 13),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class WizardSummaryBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const WizardSummaryBadge({
    super.key,
    required this.label,
    this.icon = Icons.smart_toy,
  });

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class WizardDropdownItem extends StatelessWidget {
  final String label;
  final String? iconPath;
  final IconData? fallbackIcon;
  final bool isSelected;

  const WizardDropdownItem({
    super.key,
    required this.label,
    this.iconPath,
    this.fallbackIcon = Icons.smart_toy,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Row(
      children: [
        if (iconPath != null)
          Image.asset(
            iconPath!,
            width: 24,
            height: 24,
            errorBuilder:
                (context, error, stackTrace) =>
                    Icon(fallbackIcon, size: 20, color: AppColors.white),
          )
        else
          Icon(fallbackIcon, size: 20, color: AppColors.white),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: AppConstants.fontSizeBody,
            color: isSelected ? AppColors.white : AppColors.textMain,
          ),
        ),
      ],
    );
  }
}
