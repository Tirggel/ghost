import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';

class SettingsSubNavBar extends StatelessWidget {
  final List<String> items;
  final int currentIndex;
  final Function(int) onTap;

  const SettingsSubNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Row(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isActive = index == currentIndex;

          return _SubNavItem(
            label: label.tr(),
            isActive: isActive,
            onTap: () => onTap(index),
            isLast: index == items.length - 1,
          );
        }).toList(),
      ),
    );
  }
}

class _SubNavItem extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isLast;

  const _SubNavItem({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isLast = false,
  });

  @override
  State<_SubNavItem> createState() => _SubNavItemState();
}

class _SubNavItemState extends State<_SubNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlight = widget.isActive || _isHovered;

    return Padding(
      padding: EdgeInsets.only(right: widget.isLast ? 0 : 40),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: highlight ? AppColors.white : AppColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              fontFamily: 'FiraCode', // Brutalist font if available, fallback to default
            ),
            child: Text(widget.label.toUpperCase()),
          ),
        ),
      ),
    );
  }
}
