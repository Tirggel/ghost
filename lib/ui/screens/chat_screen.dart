import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/gateway_provider.dart';
import '../../core/constants.dart';
import '../../providers/chat_provider.dart';
import '../../providers/hitl_provider.dart';
import '../widgets/connection_status.dart';
import '../widgets/model_info_badge.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_field.dart';
import '../widgets/app_dialogs.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/chat_session.dart';


class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isIconHovered = false;

  bool _isSearchVisible = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  int _currentSearchIndex = 0;
  final Map<int, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    // Initialize session state and listeners
    Future.microtask(() {
      ref.read(configProvider.notifier).refresh();
      ref.read(chatProvider.notifier).initSession(widget.sessionId);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToActiveMatch(Map<int, int> messageMatchOffsets, int totalMessages) {
    if (messageMatchOffsets.isEmpty) return;

    // Find which message contains _currentSearchIndex.
    // messageMatchOffsets[i] = start offset of matches for message i.
    // Message i owns match indices [offset, nextOffset).
    int targetMessageIndex = -1;
    final sortedEntries = messageMatchOffsets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (int e = 0; e < sortedEntries.length; e++) {
      final startOffset = sortedEntries[e].value;
      final int endOffset = (e + 1 < sortedEntries.length)
          ? sortedEntries[e + 1].value
          : 999999;
      if (_currentSearchIndex >= startOffset && _currentSearchIndex < endOffset) {
        targetMessageIndex = sortedEntries[e].key;
        break;
      }
    }

    if (targetMessageIndex == -1) return;

    final key = _messageKeys[targetMessageIndex];
    void ensureVisible() {
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    }

    if (key != null && key.currentContext != null) {
      ensureVisible();
    } else {
      if (_scrollController.hasClients) {
        final fraction = targetMessageIndex / (totalMessages == 0 ? 1 : totalMessages);
        final targetOffset = _scrollController.position.maxScrollExtent * fraction;
        _scrollController.jumpTo(targetOffset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ensureVisible();
        });
      }
    }
  }

  Future<void> _sendMessage(String text, List<PlatformFile> attachments) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;

    final hitlNotifier = ref.read(hitlProvider.notifier);
    final hitlStatus = hitlNotifier.getStatus(widget.sessionId);

    // --- HITL DECLINED: block any confirmation attempt ---
    if (hitlStatus == HitlStatus.declined && isHitlConfirmation(text)) {
      // Show local security message, do NOT send to agent
      ref.read(chatProvider.notifier).addMessageEntry(widget.sessionId, {
        'role': 'error',
        'content':
            '🔒 **Nicht erlaubt aufgrund der Sicherheitseinstellungen.**\n\n'
            'Diese Aktion wurde von dir abgelehnt. Um sie erneut anzufordern, '
            'stelle die Frage neu und bestätige mit **JA**.',
        'timestamp': DateTime.now().toIso8601String(),
        'attachments': <dynamic>[],
      });
      _textController.clear();
      return;
    }

    // --- Normal send ---
    // If a new (non-confirmation) message is sent after decline, reset HITL state
    if (hitlStatus == HitlStatus.declined && !isHitlConfirmation(text)) {
      hitlNotifier.reset(widget.sessionId);
    }

    _textController.clear();
    final notifier = ref.read(chatProvider.notifier);
    
    final List<ChatAttachment> chatAttachments = [];
    for (final file in attachments) {
      if (file.bytes != null) {
        chatAttachments.add(ChatAttachment(
          name: file.name,
          mimeType: _getMimeType(file.extension),
          data: base64Encode(file.bytes!),
        ));
      }
    }

    notifier.addMessageEntry(widget.sessionId, {
      'role': 'user',
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
      'attachments': chatAttachments.map((a) => a.toJson()).toList(),
    });
    notifier.setProcessing(widget.sessionId, true);
    _scrollToBottom();

    try {
      // Prefer session-specific model over global config
      final sessions = ref.read(sessionsProvider);
      final ChatSession? currentSession = sessions.where(
        (s) => s.id == widget.sessionId,
      ).firstOrNull;
      
      final AppConfig config = ref.read(configProvider);
      final agentModel =
          currentSession?.model ??
          config.agent.model;
      final agentProvider =
          currentSession?.provider ??
          config.agent.provider;
      final sessionAgentId = currentSession?.agentId;

      await ref.read(gatewayClientProvider).call('agent.chat', {
        'content': text,
        'sessionId': widget.sessionId,
        'model': agentModel,
        'provider': agentProvider,
        if (sessionAgentId != null) 'agentId': sessionAgentId,
        'attachments': chatAttachments.map((a) => a.toJson()).toList(),
      });
    } catch (_) {}
  }

  String _getMimeType(String? extension) {
    if (extension == null) return 'application/octet-stream';
    switch (extension.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'm4a': return 'audio/mp4';
      case 'txt': return 'text/plain';
      case 'md': return 'text/markdown';
      default: return 'application/octet-stream';
    }
  }

  void _stopProcessing() {
    ref.read(chatProvider.notifier).stop(widget.sessionId);
  }

  Future<void> _editTitle(String currentTitle) async {
    final newTitle = await AppAlertDialog.showTextInput(
      context: context,
      title: 'chat.edit_title'.tr(),
      initialValue: currentTitle,
      hintText: 'chat.edit_title_hint'.tr(),
    );

    if (newTitle != null &&
        newTitle.trim().isNotEmpty &&
        newTitle != currentTitle) {
      await ref
          .read(sessionsProvider.notifier)
          .setSessionTitle(widget.sessionId, newTitle.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final allChatStates = ref.watch(chatProvider);
    final chatState = allChatStates[widget.sessionId] ?? ChatState.initial();
    final visibleMessages =
        chatState.messages.where((m) => !m.isSystem && !m.isHidden).toList();

    int totalSearchMatches = 0;
    final Map<int, int> messageMatchOffsets = {};

    if (_searchQuery.isNotEmpty) {
      final queryRegex = RegExp(RegExp.escape(_searchQuery), caseSensitive: false);
      for (int i = 0; i < visibleMessages.length; i++) {
        // Strip markdown syntax before counting so count matches what the user sees.
        final rawText = visibleMessages[i].content
            .replaceAll(RegExp(r'[*_`#~>\[\]()!]'), '');
        final count = queryRegex.allMatches(rawText).length;
        if (count > 0) {
          messageMatchOffsets[i] = totalSearchMatches;
          totalSearchMatches += count;
        }
      }
      
      if (chatState.isProcessing && chatState.streamedContent.isNotEmpty) {
        final rawText = chatState.streamedContent
            .replaceAll(RegExp(r'[*_`#~>\[\]()!]'), '');
        final count = queryRegex.allMatches(rawText).length;
        if (count > 0) {
          messageMatchOffsets[visibleMessages.length] = totalSearchMatches;
          totalSearchMatches += count;
        }
      }
    }

    if (_currentSearchIndex >= totalSearchMatches && totalSearchMatches > 0) {
      _currentSearchIndex = totalSearchMatches - 1;
    } else if (totalSearchMatches == 0) {
      _currentSearchIndex = 0;
    }

    final sessions = ref.watch(sessionsProvider);
    final ChatSession? currentSession = sessions.where(
      (s) => s.id == widget.sessionId,
    ).firstOrNull;

    // Auto-scroll on new content
    ref.listen(chatProvider, (prev, next) {
      final prevState = prev?[widget.sessionId];
      final nextState = next[widget.sessionId];
      if (nextState == null) return;

      if (nextState.messages.length > (prevState?.messages.length ?? 0) ||
          nextState.streamedContent.length >
              (prevState?.streamedContent.length ?? 0)) {
        _scrollToBottom();
      }
    });

    final contentColumn = Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isIconHovered = true),
                  onExit: (_) => setState(() => _isIconHovered = false),
                  cursor: SystemMouseCursors.click,
                  child: InkWell(
                    onTap: () => _editTitle(currentSession?.title ?? ''),
                    borderRadius: BorderRadius.circular(4),
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ), // Added padding for better hit target
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            color: _isIconHovered
                                ? AppColors.primary
                                : AppColors.textDim,
                            size: AppConstants.settingsIconSize,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              currentSession?.title ??
                                  '${'chat.session_label'.tr()} ${widget.sessionId.substring(0, 8)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ModelInfoBadge(sessionId: widget.sessionId),
                  const SizedBox(height: 4),
                  if (currentSession != null &&
                      (currentSession.inputTokens > 0 ||
                          currentSession.outputTokens > 0)) ...[
                    Text(
                      'In: ${currentSession.inputTokens} | Out: ${currentSession.outputTokens}',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  const ConnectionStatusWidget(),
                ],
              ),
            ],
          ),
        ),

        // Search Bar
        if (_isSearchVisible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: AppColors.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'chat.search_hint'.tr(),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _currentSearchIndex = 0;
                      });
                      // Scroll to first match when query changes
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToActiveMatch(messageMatchOffsets, visibleMessages.length + 1);
                      });
                    },
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  Text(
                    totalSearchMatches > 0 ? '${_currentSearchIndex + 1} / $totalSearchMatches' : '0 / 0',
                    style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: totalSearchMatches > 0 ? () {
                      setState(() {
                        _currentSearchIndex = (_currentSearchIndex - 1 + totalSearchMatches) % totalSearchMatches;
                      });
                      _scrollToActiveMatch(messageMatchOffsets, visibleMessages.length + 1);
                    } : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: totalSearchMatches > 0 ? () {
                      setState(() {
                        _currentSearchIndex = (_currentSearchIndex + 1) % totalSearchMatches;
                      });
                      _scrollToActiveMatch(messageMatchOffsets, visibleMessages.length + 1);
                    } : null,
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _isSearchVisible = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    _scrollToBottom();
                  },
                ),
              ],
            ),
          ),

        // Messages
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              itemCount:
                  visibleMessages.length + (chatState.isProcessing ? 1 : 0),
              itemBuilder: (context, index) {
                _messageKeys[index] ??= GlobalKey();
                final key = _messageKeys[index];

                if (index == visibleMessages.length) {
                  final agentId = currentSession?.agentId;

                  return Container(
                    key: key,
                    child: MessageBubble(
                      role: 'assistant',
                      content: chatState.streamedContent,
                      isStreaming: true,
                      metadata: {
                        'agentId': agentId,
                        'model': currentSession?.model ??
                            ref.read(configProvider).agent.model,
                        'provider': currentSession?.provider ??
                            ref.read(configProvider).agent.provider,
                      },
                      activity: chatState.activity,
                      sessionId: widget.sessionId,
                      searchQuery: _searchQuery,
                      matchStartIndex: messageMatchOffsets[index] ?? 0,
                      activeMatchIndex: _currentSearchIndex,
                    ),
                  );
                }
                final m = visibleMessages[index];
                return Container(
                  key: key,
                  child: MessageBubble(
                    role: m.role,
                    content: m.content,
                    metadata: m.metadata,
                    timestamp: m.timestamp,
                    attachments: m.attachments,
                    sessionId: widget.sessionId,
                    searchQuery: _searchQuery,
                    matchStartIndex: messageMatchOffsets[index] ?? 0,
                    activeMatchIndex: _currentSearchIndex,
                  ),
                );
              },
              ),
            ),
          ),

        // Input
        ChatInputField(
          controller: _textController,
          onSend: _sendMessage,
          onStop: _stopProcessing,
          isProcessing: chatState.isProcessing,
        ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() => _isSearchVisible = true);
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          setState(() => _isSearchVisible = true);
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isSearchVisible) {
            setState(() {
              _isSearchVisible = false;
              _searchQuery = '';
              _searchController.clear();
            });
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: contentColumn,
      ),
    );
  }

}
