import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../../providers/shell_provider.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/settings_side_nav_tile.dart';

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
    final showKanban = ref.watch(shellProvider.select((s) => s.showKanban));
    final showEmail = ref.watch(shellProvider.select((s) => s.showEmail));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: const BoxDecoration(color: AppColors.pureBlack),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSideNavTile(
            label: 'common.chat'.tr(),
            icon: Icons.chat_bubble_outline,
            isActive: !showKanban && !showEmail,
            onTap: () {
              ref.read(shellProvider.notifier).setShowKanban(false);
              ref.read(shellProvider.notifier).setShowEmail(false);
            },
          ),
          const SizedBox(height: 4),
          SettingsSideNavTile(
            label: 'kanban.title_board'.tr(),
            icon: Icons.dashboard,
            isActive: showKanban,
            onTap: () => ref.read(shellProvider.notifier).setShowKanban(true),
          ),
          const SizedBox(height: 4),
          SettingsSideNavTile(
            label: 'email.title'.tr(),
            icon: Icons.mail_outline,
            isActive: showEmail,
            onTap: () => ref.read(shellProvider.notifier).setShowEmail(true),
          ),
          const SizedBox(height: 4),
          SettingsSideNavTile(
            label: 'settings.title'.tr(),
            icon: Icons.settings,
            isActive: false,
            onTap: onShowSettings,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}


