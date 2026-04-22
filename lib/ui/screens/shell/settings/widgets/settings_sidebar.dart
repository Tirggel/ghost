import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../../core/constants.dart';
import '../../../../widgets/app_sidebar.dart';
import '../../../../widgets/settings_side_nav_tile.dart';

class SettingsSidebar extends StatelessWidget {

  const SettingsSidebar({
    super.key,
    required this.selectedIndex,
    required this.navItems,
    required this.onAction,
  });
  final int selectedIndex;
  final List<Map<String, dynamic>> navItems;
  final void Function(int) onAction;

  @override
  Widget build(BuildContext context) {
    return AppSidebar(
      header: _buildHeader(),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.sidebarPaddingHorizontal,
        ),
        child: ListView.builder(
          itemCount: navItems.length,
          itemBuilder: (context, index) {
            final item = navItems[index];
            return SettingsSideNavTile(
              label: item['label'].toString().tr(),
              icon: item['icon'] as IconData,
              isActive: selectedIndex == index,
              onTap: () => onAction(index),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.sidebarPaddingHorizontal,
        vertical: AppConstants.sidebarPaddingVertical,
      ),
      child: Text(
        'settings.title'.tr().toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 4.0,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
