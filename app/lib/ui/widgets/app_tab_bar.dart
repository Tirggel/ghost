import 'package:flutter/material.dart';
import '../../core/constants.dart';

class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.onTap,
    this.isScrollable = false,
  });

  final TabController controller;
  final List<Widget> tabs;
  final ValueChanged<int>? onTap;
  final bool isScrollable;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        tabAlignment: isScrollable ? TabAlignment.start : null,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textDim,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          border: const Border(
            bottom: BorderSide(color: AppColors.primary, width: 3),
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(alpha: 0.1);
          }
          return null;
        }),
        onTap: onTap,
        tabs: tabs,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(48.0);
}
