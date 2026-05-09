import 'package:flutter/material.dart';
import '../../core/constants.dart';

/// A reusable selectable card component used for list items in the settings UI.
/// Follows the "Ghost Minimalist Noir" design system with square corners.
class AppSelectableCard extends StatelessWidget {
  const AppSelectableCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.isSelected = false,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.padding = const EdgeInsets.all(AppConstants.cardPadding),
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool isSelected;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          // Active items are slightly lighter (Surface) than the background
          color: isSelected ? AppColors.surface : AppColors.background,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            // Active items have a white border, inactive have a subtle border
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: 40, child: Center(child: leading!)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    subtitle!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
