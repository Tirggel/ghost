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
import '../../providers/hitl_provider.dart';
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
    this.searchQuery = '',
    this.matchStartIndex = 0,
    this.activeMatchIndex = -1,
  });

  final String role;
  final String content;
  final bool isStreaming;
  final Map<String, dynamic>? metadata;
  final String? timestamp;
  final String? activity;
  final List<ChatAttachment>? attachments;
  final String? sessionId;
  final String searchQuery;
  final int matchStartIndex;
  final int activeMatchIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityLocal = activity;
    final isAssistant = role == 'assistant';
    final isSystem = role == 'system' || role == 'error';

    // Friendly display content for system messages
    String displayContent = content;
    if (isSystem) {
      if (content.contains('validation errors for Validator') ||
          content.contains('Input should be a valid string') ||
          content.contains('BadRequestError')) {
        displayContent = '⚠️ **Sicherheits-Fehler**\n\nDie Tool-Ausführung wurde wegen eines Protokollfehlers abgebrochen. Dies kann passieren, wenn der Chat-Verlauf eine blockierte Tool-Anfrage enthält.\n\n_Bitte starte einen neuen Chat oder bestätige mit "JA" im vorherigen Gespräch._';
      } else if (content.contains('validation error') || (content.contains('error') && content.contains('type='))) {
        displayContent = '⚠️ **Technischer Fehler**\n\nEin interner Fehler ist aufgetreten. Bitte versuche es erneut.';
      }
    }

    // For non-user messages (assistant/markdown), inject search markers into raw text.
    // For user messages we render highlights via RichText directly (see below).
    if (searchQuery.isNotEmpty && !isSystem && role != 'user') {
      int localMatchCount = 0;
      // dotAll:false avoids multiline matches, which would insert \n inside markers
      // and break the Markdown inline parser.
      final queryRegex = RegExp(RegExp.escape(searchQuery), caseSensitive: false);
      displayContent = displayContent.replaceAllMapped(queryRegex, (match) {
        final idx = matchStartIndex + localMatchCount;
        localMatchCount++;
        return '\x02sm$idx\x03${match[0]}\x02em\x03';
      });
    }

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
    bool isCustomAgent = false;
    if (isAssistant && agentId != null) {
      final agentData = customAgents.where((a) => a.id == agentId).firstOrNull;
      if (agentData != null) {
        isCustomAgent = true;
        identityName = agentData.name;
        // Only override avatar if the custom agent has one set
        if (agentData.avatar != null && agentData.avatar!.isNotEmpty) {
          identityAvatarPath = agentData.avatar!;
        } else {
          // No avatar: use robot icon (clear path so fallback icon shows)
          identityAvatarPath = '';
        }
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
        // Custom agent without avatar → show robot icon
        if (isCustomAgent && identityAvatarPath.isEmpty) {
          return const AppAssistantAvatar(
            icon: Icons.smart_toy_outlined,
            radius: AppConstants.avatarRadius,
            iconSize: AppConstants.avatarIconSize,
          );
        }
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
                  if (role == 'user' && searchQuery.isNotEmpty)
                    _buildHighlightedText(
                      displayContent,
                      searchQuery,
                      matchStartIndex,
                      activeMatchIndex,
                    )
                  else
                    MarkdownBody(
                      data: content.isEmpty && isAssistant ? '_${'chat.thinking'.tr()}_' : displayContent,
                      inlineSyntaxes: [
                        if (searchQuery.isNotEmpty && role != 'user') SearchMatchSyntax(),
                      ],
                      builders: {
                        'pre': CodeElementBuilder(),
                        if (searchQuery.isNotEmpty && role != 'user')
                          'search_match': SearchMatchBuilder(activeMatchIndex: activeMatchIndex),
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
                          final tcMap = tc as Map<String, dynamic>;
                          final name = (tcMap['label'] as String?) ?? (tcMap['name'] as String?) ?? '';
                          final summary = (tcMap['summary'] as String?) ?? '';
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
                  if (_isHitlActive(ref))
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _sendConfirmation(ref, 'ja'),
                              icon: const Icon(Icons.check, size: 18),
                              label: Text('settings.security.hitl_yes'.tr()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _sendConfirmation(ref, 'no'),
                              icon: const Icon(Icons.close, size: 18),
                              label: Text('settings.security.hitl_no'.tr()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error.withValues(alpha: 0.2),
                                foregroundColor: AppColors.error,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
                                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
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

  bool _isHitlPending() {
    if (role != 'assistant') return false;
    final toolCalls = metadata?['tool_calls'] as List<dynamic>?;
    if (toolCalls == null || toolCalls.isEmpty) return false;

    // Show buttons if hitl_blocked flag is set
    if (metadata?['hitl_blocked'] == true) return true;

    // Also show if any sensitive tool name is in the tool calls list
    const sensitiveTools = {
      'write_file', 'edit_file', 'delete_file', 'apply_patch',
      'bash', 'terminal', 'exec', 'process',
      'github', 'github_pr', 'github_commit',
      'browser_open', 'browser_click', 'browser_type',
    };
    for (final tc in toolCalls) {
      final name = (tc as Map<String, dynamic>)['name'] as String? ?? '';
      if (sensitiveTools.contains(name)) return true;
    }
    return false;
  }

  /// Returns true only if THIS message has a sensitive tool call
  /// AND the session HITL state is explicitly [HitlStatus.pending].
  /// This prevents old messages from re-showing buttons after a reset.
  bool _isHitlActive(WidgetRef ref) {
    if (!_isHitlPending()) return false;
    if (sessionId == null) return false;
    final stateMap = ref.watch(hitlProvider);
    return (stateMap[sessionId!] ?? HitlStatus.none) == HitlStatus.pending;
  }

  Future<void> _sendConfirmation(WidgetRef ref, String answer) async {
    if (sessionId == null) return;
    final hitlNotifier = ref.read(hitlProvider.notifier);

    if (answer == 'no') {
      // NEIN pressed: mark as declined in UI, hide buttons
      hitlNotifier.setDeclined(sessionId!);
      // Also record the decline in backend history silently,
      // so the sanitizer removes the blocked turn on the next chat load.
      try {
        final sessions = ref.read(sessionsProvider);
        final currentSession =
            sessions.where((s) => s.id == sessionId).firstOrNull;
        final config = ref.read(configProvider);
        final agentModel = currentSession?.model ?? config.agent.model;
        final agentProvider =
            currentSession?.provider ?? config.agent.provider;
        await ref.read(gatewayClientProvider).call('agent.chat', {
          'content': '__HITL_DECLINED__',
          'sessionId': sessionId!,
          'model': agentModel,
          'provider': agentProvider,
          'attachments': <dynamic>[],
        });
      } catch (_) {}
      return;
    }

    // JA pressed: reset hitl state, then send confirmation to agent
    hitlNotifier.reset(sessionId!);

    final notifier = ref.read(chatProvider.notifier);
    notifier.addMessageEntry(sessionId!, {
      'role': 'user',
      'content': answer,
      'timestamp': DateTime.now().toIso8601String(),
      'attachments': [],
    });
    notifier.setProcessing(sessionId!, true);
    
    final sessions = ref.read(sessionsProvider);
    final currentSession = sessions.where((s) => s.id == sessionId).firstOrNull;
    final config = ref.read(configProvider);
    final agentModel = currentSession?.model ?? config.agent.model;
    final agentProvider = currentSession?.provider ?? config.agent.provider;

    try {
      await ref.read(gatewayClientProvider).call('agent.chat', {
        'content': answer,
        'sessionId': sessionId!,
        'model': agentModel,
        'provider': agentProvider,
        'attachments': [],
      });
    } catch (_) {}
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
                    showDialog<void>(
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
                    const text = 'continue';
                    final notifier = ref.read(chatProvider.notifier);
                    
                    notifier.addMessageEntry(sessionId!, {
                      'role': 'user',
                      'content': text,
                      'timestamp': DateTime.now().toIso8601String(),
                      'attachments': <dynamic>[],
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
                        'attachments': <dynamic>[],
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

  /// Renders plain text with inline search-match highlights via [RichText].
  /// Used for user messages (no Markdown) to avoid the marker-injection fragility.
  Widget _buildHighlightedText(
    String text,
    String query,
    int startIndex,
    int active,
  ) {
    final queryRegex = RegExp(RegExp.escape(query), caseSensitive: false);
    final spans = <TextSpan>[];
    int cursor = 0;
    int localIdx = 0;
    for (final m in queryRegex.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, m.start),
          style: const TextStyle(color: AppColors.textMain, fontSize: 15, height: 1.6),
        ));
      }
      final globalIdx = startIndex + localIdx;
      final isActive = globalIdx == active;
      spans.add(TextSpan(
        text: m[0],
        style: TextStyle(
          backgroundColor: isActive ? Colors.green : Colors.green.withValues(alpha: 0.3),
          color: isActive ? Colors.white : AppColors.textMain,
          fontSize: 15,
          height: 1.6,
        ),
      ));
      localIdx++;
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: const TextStyle(color: AppColors.textMain, fontSize: 15, height: 1.6),
      ));
    }
    return RichText(text: TextSpan(children: spans));
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

    String cleanText = element.textContent;
    // Strip search markers (using both old @@ and new \x02/\x03 style)
    cleanText = cleanText
        .replaceAll(RegExp(r'\x02sm\d+\x03'), '')
        .replaceAll(RegExp(r'\x02em\x03'), '')
        .replaceAll(RegExp(r'@@sm\d+@@'), '')
        .replaceAll('@@em@@', '');

    return CodeBlockWidget(
      code: cleanText,
      language: language.isEmpty ? null : language,
    );
  }
}

class SearchMatchSyntax extends md.InlineSyntax {
  // \x02sm<idx>\x03 ... \x02em\x03 — using STX/ETX control chars as safe delimiters.
  // These are never valid Markdown and won't be touched by any Markdown syntax.
  SearchMatchSyntax() : super('\x02sm(\\d+)\x03([^\x02]*)\x02em\x03');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final searchElement = md.Element('search_match', [md.Text(match[2]!)]);
    searchElement.attributes['index'] = match[1]!;
    parser.addNode(searchElement);
    return true;
  }
}

class SearchMatchBuilder extends MarkdownElementBuilder {
  SearchMatchBuilder({required this.activeMatchIndex});
  final int activeMatchIndex;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final idx = int.tryParse(element.attributes['index'] ?? '-1') ?? -1;
    final isMatchActive = idx == activeMatchIndex;
    final baseStyle = preferredStyle ?? const TextStyle(
      color: AppColors.textMain,
      fontSize: 15,
      height: 1.6,
    );
    return RichText(
      text: TextSpan(
        text: element.textContent,
        style: baseStyle.copyWith(
          backgroundColor: isMatchActive ? Colors.green : Colors.green.withValues(alpha: 0.3),
          color: isMatchActive ? Colors.white : AppColors.textMain,
        ),
      ),
    );
  }
}
