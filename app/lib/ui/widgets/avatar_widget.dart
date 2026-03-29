// Removed unused imports
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../providers/gateway_provider.dart';

class AvatarWidget extends ConsumerWidget {
  final String? path;
  final String? emoji;
  final IconData? icon;
  final double radius;
  final double iconSize;
  final bool isAssistant;
  final BorderRadius? borderRadius;
  final int
  extraVersion; // Extra cache-buster; increment after upload to force refresh

  const AvatarWidget({
    super.key,
    this.path,
    this.emoji,
    this.icon,
    this.radius = AppConstants.avatarRadius,
    this.iconSize = AppConstants.avatarIconSize,
    this.isAssistant = false,
    this.borderRadius,
    this.extraVersion = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path != null && path!.isNotEmpty) {
      // We always fetch avatars from the gateway now, since they are stored in the server's Hive database.
      // E.g. path could be 'user_avatar', 'identity_avatar', or 'agent_avatar_xyz'.

      String url;
      if (path!.startsWith('http://') || path!.startsWith('https://')) {
        url = path!;
      } else {
        // kIsWeb with local server path
        final wsUrl =
            ref.watch(gatewayUrlProvider).value ?? 'ws://127.0.0.1:18789';
        final baseUrl = wsUrl
            .replaceFirst('wss://', 'https://')
            .replaceFirst('ws://', 'http://');
        final config = ref.watch(configProvider);
        final version = path.hashCode ^ config.hashCode ^ extraVersion;
        url = '$baseUrl/file?path=${Uri.encodeComponent(path!)}&v=$version';
      }

      if (borderRadius != null) {
        return ClipRRect(
          borderRadius: borderRadius!,
          child: Image.network(
            url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) {
              return _buildFallback();
            },
          ),
        );
      }

      return ClipOval(
        child: Image.network(
          url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return _buildFallback();
          },
        ),
      );
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    final effectiveIcon = icon ?? (isAssistant ? Icons.auto_awesome : Icons.person);
    final iconColor = isAssistant
        ? AppConstants.iconColorPrimary
        : AppConstants.iconColorWhite;

    if (icon != null) {
      if (borderRadius != null) {
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: borderRadius,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor,
          ),
        );
      }
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.border,
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor,
        ),
      );
    }

    if (emoji != null && emoji!.isNotEmpty) {
      if (borderRadius != null) {
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: borderRadius,
          ),
          alignment: Alignment.center,
          child: Text(
            emoji!,
            style: TextStyle(
              fontSize: iconSize,
              fontFamilyFallback: const [
                'Apple Color Emoji',
                'Segoe UI Emoji',
                'Noto Color Emoji',
                'Android Emoji',
                'EmojiSymbols',
              ],
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.border,
        child: Text(
          emoji!,
          style: TextStyle(
            fontSize: iconSize,
            fontFamilyFallback: const [
              'Apple Color Emoji',
              'Segoe UI Emoji',
              'Noto Color Emoji',
              'Android Emoji',
              'EmojiSymbols',
            ],
          ),
        ),
      );
    }

    if (borderRadius != null) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: Icon(
          effectiveIcon,
          size: iconSize,
          color: iconColor,
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.border,
      child: Icon(
        effectiveIcon,
        size: iconSize,
        color: iconColor,
      ),
    );
  }
}

enum AvatarType { user, identity, agent }

class AppUserAvatar extends ConsumerWidget {
  final String? path;
  final double radius;
  final double iconSize;
  final BorderRadius? borderRadius;
  final int extraVersion;

  const AppUserAvatar({
    super.key,
    this.path,
    this.radius = AppConstants.avatarRadius,
    this.iconSize = AppConstants.avatarIconSize,
    this.borderRadius,
    this.extraVersion = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAvatar = ref.watch(configProvider.select((c) => c.user.avatar));
    final resolvedPath = (path == null || path!.isEmpty) ? userAvatar : path;
    return AvatarWidget(
      path: resolvedPath,
      radius: radius,
      iconSize: iconSize,
      isAssistant: false,
      borderRadius: borderRadius,
      extraVersion: extraVersion,
    );
  }
}

class AppIdentityAvatar extends ConsumerWidget {
  final String? path;
  final String? emoji;
  final double radius;
  final double iconSize;
  final BorderRadius? borderRadius;
  final int extraVersion;

  const AppIdentityAvatar({
    super.key,
    this.path,
    this.emoji,
    this.radius = AppConstants.avatarRadius,
    this.iconSize = AppConstants.avatarIconSize,
    this.borderRadius,
    this.extraVersion = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(configProvider.select((c) => c.identity));
    final resolvedPath = (path == null || path!.isEmpty) ? identity.avatar : path;
    final resolvedEmoji = (emoji == null || emoji!.isEmpty) ? identity.emoji : emoji;
    return AvatarWidget(
      path: resolvedPath,
      emoji: resolvedEmoji,
      radius: radius,
      iconSize: iconSize,
      isAssistant: true,
      borderRadius: borderRadius,
      extraVersion: extraVersion,
    );
  }
}

class AppAssistantAvatar extends StatelessWidget {
  final String? path;
  final String? emoji;
  final IconData? icon;
  final double radius;
  final double iconSize;
  final BorderRadius? borderRadius;
  final int extraVersion;

  const AppAssistantAvatar({
    super.key,
    this.path,
    this.emoji,
    this.icon,
    this.radius = AppConstants.avatarRadius,
    this.iconSize = AppConstants.avatarIconSize,
    this.borderRadius,
    this.extraVersion = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AvatarWidget(
      path: path,
      emoji: emoji,
      icon: icon,
      radius: radius,
      iconSize: iconSize,
      isAssistant: true,
      borderRadius: borderRadius,
      extraVersion: extraVersion,
    );
  }
}
