import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
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
      footer: _buildFooter(),
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

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.sidebarPaddingHorizontal,
        vertical: AppConstants.sidebarPaddingVertical,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'settings.credits.developed_by'.tr(),
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => launchUrl(Uri.parse('https://github.com/Tirggel/ghost')),
            child: Text(
              'settings.credits.github_project'.tr(),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'settings.credits.built_with'.tr(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildTechIcon('assets/icons/tech/flutter.png', 'Flutter'),
              _buildTechIcon('assets/icons/tech/dart.png', 'Dart'),
              _buildTechIcon('assets/icons/tech/python.png', 'Python'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTechIcon(String assetPath, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          assetPath,
          width: 14,
          height: 14,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textDim,
          ),
        ),
      ],
    );
  }
}
