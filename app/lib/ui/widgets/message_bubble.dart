import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:easy_localization/easy_localization.dart';
import 'code_block_widget.dart';
import '../../providers/gateway_provider.dart';
import '../../core/constants.dart';
import '../../core/models/chat_message.dart';
import '../../providers/chat_provider.dart';
import 'avatar_widget.dart';
import '../screens/shell/session_model_dialog.dart';

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
    this.sessionId,
  });

  final String role;
  final String content;
  final bool isStreaming;
  final Map<String, dynamic>? metadata;
  final String? timestamp;
  final String? activity;
  final List<ChatAttachment>? attachments;
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityLocal = activity;
    final isAssistant = role == 'assistant';
    final isSystem = role == 'system' || role == 'error';
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
        identityAvatarPath = (agentData['avatar'] as String?) ?? identity.avatar ?? '';
      }
    }

    Widget buildAvatar({required bool isAssistant, bool isSystem = false}) {
      if (isSystem) {
        return const AppAssistantAvatar(
          icon: Icons.settings,
          radius: AppConstants.avatarRadius,
        );
      }
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
                buildAvatar(isAssistant: isAssistant, isSystem: isSystem),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (isSystem
                                ? 'SYSTEM'
                                : (isAssistant ? identityName : userName))
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: isSystem ? AppColors.warning : AppColors.textMain,
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSystem
                    ? AppColors.warning.withValues(alpha: 0.1)
                    : (isAssistant
                        ? AppColors.surface.withValues(alpha: 0.3)
                        : AppColors.surface.withValues(alpha: 0.6)),
                borderRadius:
                    BorderRadius.circular(AppConstants.borderRadiusDefault),
                border: isSystem ? Border.all(color: AppColors.warning.withValues(alpha: 0.2)) : null,
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
                    builders: {
                      'pre': CodeElementBuilder(),
                    },
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
                      codeblockDecoration: const BoxDecoration(), // New widget handles decoration
                    ),
                  ),
                  _buildErrorRecoveryButton(context, ref),
                  if (isAssistant && metadata?['tool_calls'] != null) ...[
                    const SizedBox(height: 16),
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          '${'common.agent'.tr()} used ${(metadata?['tool_calls'] as List).length} tools',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDim,
                            letterSpacing: 0.5,
                          ),
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        collapsedIconColor: AppColors.textDim,
                        iconColor: AppColors.primary,
                        children: (metadata?['tool_calls'] as List).map((tc) {
                          final name = tc['label'] ?? tc['name'];
                          final summary = tc['summary'] ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, size: 14, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$name${summary.isNotEmpty ? ': $summary' : ''}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMain),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  if (isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (activityLocal != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        activityLocal.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.primary,
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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

  Widget _buildErrorRecoveryButton(BuildContext context, WidgetRef ref) {
    if (sessionId == null) return const SizedBox.shrink();

    final hasError = content.contains('⚠️ Provider returned error') ||
        content.contains('⚠️ Rate limit exceeded') ||
        content.contains('💡 Tipp');

    if (!hasError) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: AppColors.warning.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => SessionModelDialog(
                        sessionId: sessionId!,
                        currentModel: metadata?['model'] as String?,
                        currentProvider: metadata?['provider'] as String?,
                        alsoUpdateMainAgent: true,
                      ),
                    );
                  },
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text('settings.identity.choose_model'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning.withValues(alpha: 0.2),
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.borderRadiusSmall),
                      side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final text = 'continue';
                    final notifier = ref.read(chatProvider.notifier);
                    
                    notifier.addMessageEntry(sessionId!, {
                      'role': 'user',
                      'content': text,
                      'timestamp': DateTime.now().toIso8601String(),
                      'attachments': [],
                    });
                    notifier.setProcessing(sessionId!, true);
                    
                    final sessions = ref.read(sessionsProvider);
                    final currentSession = sessions.where(
                      (s) => s.id == sessionId,
                    ).firstOrNull;
                    
                    final config = ref.read(configProvider);
                    final agentModel = currentSession?.model ?? config.agent.model;
                    final agentProvider = currentSession?.provider ?? config.agent.provider;

                    try {
                      await ref.read(gatewayClientProvider).call('agent.chat', {
                        'content': text,
                        'sessionId': sessionId!,
                        'model': agentModel,
                        'provider': agentProvider,
                        'attachments': [],
                      });
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.play_arrow_outlined, size: 18),
                  label: const Text('Weiter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.borderRadiusSmall),
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
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

class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    
    // The 'pre' element usually contains a 'code' element as its first child
    if (element.children != null && element.children!.isNotEmpty) {
      final child = element.children![0];
      if (child is md.Element && child.tag == 'code') {
        if (child.attributes['class'] != null) {
          final lg = child.attributes['class']!;
          if (lg.startsWith('language-')) {
            language = lg.substring('language-'.length);
          }
        }
      }
    }

    return CodeBlockWidget(
      code: element.textContent,
      language: language.isEmpty ? null : language,
    );
  }
}

