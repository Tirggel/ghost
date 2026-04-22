import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/settings_side_nav_tile.dart';
import '../../widgets/app_dialogs.dart';

class SidebarFooter extends ConsumerWidget {

  const SidebarFooter({super.key, required this.onShowSettings});
  final VoidCallback onShowSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final identity = config.identity;
    final name = identity.name;
    final avatarPath = identity.avatar;
    final emoji = identity.emoji ?? '🫥';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: const BoxDecoration(color: AppColors.pureBlack),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.sidebarPaddingHorizontal,
            ),
            child: SettingsSideNavTile(
              label: 'settings.title'.tr(),
              icon: Icons.settings,
              isActive: false,
              onTap: onShowSettings,
            ),
          ),
          const SizedBox(height: 24),
          // IDENTITY SECTION
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.sidebarPaddingHorizontal,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: AppIdentityAvatar(
                    path: avatarPath,
                    emoji: emoji,
                    borderRadius: BorderRadius.circular(4),
                    radius: 16,
                    iconSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: AppColors.textMain,
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Haupt-Agent',
                        style: TextStyle(
                          fontSize: AppConstants.fontSizeLabelTiny,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                _HoverLogoutButton(
                  onTap: () async {
                    final confirmed = await AppAlertDialog.showConfirmation(
                      context: context,
                      title: 'sidebar.logout_title'.tr(),
                      content: 'sidebar.logout_content'.tr(),
                      confirmLabel: 'common.logout'.tr(),
                      isDestructive: true,
                    );
                    if (confirmed == true) {
                      await ref.read(authTokenProvider.notifier).logout();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverLogoutButton extends StatefulWidget {
  const _HoverLogoutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_HoverLogoutButton> createState() => _HoverLogoutButtonState();
}

class _HoverLogoutButtonState extends State<_HoverLogoutButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: IconButton(
        icon: Icon(
          Icons.logout_rounded,
          size: 18,
          color: _isHovered ? AppColors.error : AppColors.white,
        ),
        onPressed: widget.onTap,
        tooltip: 'sidebar.logout_title'.tr(),
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}
