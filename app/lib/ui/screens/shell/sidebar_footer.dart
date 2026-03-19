import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/avatar_widget.dart';

class SidebarFooter extends ConsumerWidget {
  final VoidCallback onShowSettings;

  const SidebarFooter({super.key, required this.onShowSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final identity = config.identity;
    final name = identity.name;
    final avatarPath = identity.avatar;
    final emoji = identity.emoji ?? '🫥';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          AppIdentityAvatar(
            path: avatarPath,
            emoji: emoji,
            radius: AppConstants.avatarRadius,
            iconSize: AppConstants.avatarIconSize,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text('sidebar.logout_title'.tr()),
                  content: Text('sidebar.logout_content'.tr()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('common.cancel'.tr()),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        'common.logout'.tr(),
                        style: const TextStyle(color: AppColors.errorDark),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(authTokenProvider.notifier).logout();
              }
            },
            tooltip: 'sidebar.logout_title'.tr(),
            icon: const Icon(
              Icons.logout_rounded,
              size: 18,
              color: AppColors.error,
            ),
          ),
          IconButton(
            onPressed: onShowSettings,
            tooltip: 'settings.title'.tr(),
            icon: const Icon(
              Icons.settings_outlined,
              size: 18,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
