import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/gateway_provider.dart';
import '../../core/constants.dart';
import '../../core/models/chat_message.dart';
import 'avatar_widget.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.isStreaming = false,
    this.metadata,
    this.timestamp,
    this.activity,
    this.attachments,
  });

  final String role;
  final String content;
  final bool isStreaming;
  final Map<String, dynamic>? metadata;
  final String? timestamp;
  final String? activity;
  final List<ChatAttachment>? attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityLocal = activity;
    final isAssistant = role == 'assistant';
    final modelName = metadata?['model'] as String?;
    final config = ref.watch(configProvider);
    final customAgents = config.customAgents;

    // Format timestamp
    String? displayTime;
    final timestampLocal = timestamp;
    if (timestampLocal != null) {
      try {
        final dt = DateTime.parse(timestampLocal).toLocal();
        final now = DateTime.now();
        final isToday =
            dt.year == now.year && dt.month == now.month && dt.day == now.day;
        final dateStr =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
        final timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        displayTime = isToday ? timeStr : '$dateStr $timeStr';
      } catch (_) {}
    } else if (isStreaming) {
      final now = DateTime.now();
      displayTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }

    // User Config
    final user = config.user;
    final userAvatarPath = user.avatar;
    final userName = user.name.isEmpty ? 'settings.tabs.user'.tr() : user.name;

    // Default Identity Config
    final identity = config.identity;
    String identityAvatarPath = identity.avatar ?? '';
    String identityName =
        identity.name.isEmpty ? 'settings.tabs.identity'.tr() : identity.name;
    final identityEmoji = identity.emoji;

    // Check if this is a custom agent message
    final agentId = metadata?['agentId'] as String?;
    if (isAssistant && agentId != null) {
      final agentData = customAgents.firstWhere(
        (a) => a['id'] == agentId,
        orElse: () => null,
      );
      if (agentData != null) {
        identityName = agentData['name'] as String? ?? identityName;
        identityAvatarPath =
            (agentData['avatar'] as String?) ??
            '/assets/images/ghost-mini.png';
      }
    }

    Widget buildAvatar({required bool isAssistant}) {
      if (isAssistant) {
        return AppIdentityAvatar(
          path: identityAvatarPath,
          emoji: identityEmoji,
          radius: AppConstants.avatarRadius,
          iconSize: AppConstants.avatarIconSize,
        );
      } else {
        return AppUserAvatar(
          path: userAvatarPath,
          radius: AppConstants.avatarRadius,
          iconSize: AppConstants.avatarIconSize,
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                buildAvatar(isAssistant: isAssistant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (isAssistant ? identityName : userName).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: AppColors.textMain,
                        ),
                      ),
                      if (isAssistant && modelName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${(metadata?['provider'] as String? ?? modelName.split('/').first).toUpperCase()} • ${modelName.contains('/') ? modelName.split('/').last : modelName}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textDim,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (displayTime != null)
                  Text(
                    displayTime,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textDim,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isAssistant ? 16 : 48,
              right: isAssistant ? 48 : 16,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isAssistant 
                    ? AppColors.transparent 
                    : AppColors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppConstants.borderRadiusDefault),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attachments != null && attachments!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: attachments!.map((a) {
                          final isImage = a.mimeType.startsWith('image/');
                          if (isImage) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 300),
                                child: Image.memory(
                                  base64Decode(a.data),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getFileIcon(a.mimeType), size: 16, color: AppColors.textDim),
                                const SizedBox(width: 8),
                                Text(a.name, style: const TextStyle(fontSize: 11, color: AppColors.textMain)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  MarkdownBody(
                    data: content.isEmpty && isAssistant ? '_${'chat.thinking'.tr()}_' : content,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: role == 'assistant' && content.isEmpty ? AppColors.textDim : AppColors.textMain,
                        height: 1.6,
                        fontSize: 15,
                      ),
                      code: const TextStyle(
                        backgroundColor: AppColors.surface,
                        color: AppColors.primary,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                      ),
                    ),
                  ),
                  if (isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (activityLocal != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      activityLocal.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: AppColors.textDim,
                                        letterSpacing: 1.0,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const ThinkingLine(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType.startsWith('video/')) return Icons.video_library_outlined;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('text/')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class ThinkingLine extends StatefulWidget {
  const ThinkingLine({super.key});

  @override
  State<ThinkingLine> createState() => _ThinkingLineState();
}

class _ThinkingLineState extends State<ThinkingLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.2,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
            color: AppConstants.iconColorPrimary.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: AppConstants.iconColorPrimary.withValues(
                  alpha: _animation.value * 0.4,
                ),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
