import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/gateway_provider.dart';
import '../../core/constants.dart';
import '../../providers/chat_provider.dart';
import '../widgets/connection_status.dart';
import '../widgets/model_info_badge.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_field.dart';
import '../widgets/app_dialogs.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/chat_session.dart';
import '../../core/models/config_models.dart';

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

  Future<void> _sendMessage(String text, List<PlatformFile> attachments) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;

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

      await ref.read(gatewayClientProvider).call('agent.chat', {
        'content': text,
        'sessionId': widget.sessionId,
        'model': agentModel,
        'provider': agentProvider,
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

  void _stopProcessing() async {
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
        chatState.messages.where((m) => !m.isSystem).toList();

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

    return Column(
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
                  const ConnectionStatusWidget(),
                ],
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
                if (index == visibleMessages.length) {
                  final agentId = currentSession?.agentId;

                    return MessageBubble(
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
                    );
                  }
                  final m = visibleMessages[index];
                  return MessageBubble(
                    role: m.role,
                    content: m.content,
                    metadata: m.metadata,
                    timestamp: m.timestamp,
                    attachments: m.attachments,
                    sessionId: widget.sessionId,
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
  }

}
