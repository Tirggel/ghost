import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_provider.dart';
import '../core/models/chat_message.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isProcessing;
  final String streamedContent;
  final String? activity;

  ChatState({
    required this.messages,
    required this.isProcessing,
    required this.streamedContent,
    this.activity,
  });

  factory ChatState.initial() =>
      ChatState(messages: [], isProcessing: false, streamedContent: '');

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    String? streamedContent,
    String? activity,
    bool clearActivity = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isProcessing: isProcessing ?? this.isProcessing,
      streamedContent: streamedContent ?? this.streamedContent,
      activity: clearActivity ? null : (activity ?? this.activity),
    );
  }
}

final chatProvider = NotifierProvider<ChatNotifier, Map<String, ChatState>>(() {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<Map<String, ChatState>> {
  final Map<String, StreamSubscription> _subs = {};

  @override
  Map<String, ChatState> build() {
    ref.onDispose(() {
      for (final sub in _subs.values) {
        sub.cancel();
      }
    });
    return {};
  }

  ChatState _getState(String sessionId) {
    return state[sessionId] ?? ChatState.initial();
  }

  void initSession(String sessionId) {
    if (state.containsKey(sessionId)) return;

    state = {...state, sessionId: ChatState.initial()};

    _listenToStreams(sessionId);
    _loadHistory(sessionId);
  }

  void _listenToStreams(String sessionId) {
    _subs[sessionId]?.cancel();
    _subs[sessionId] = ref.read(gatewayClientProvider).messages.listen((msg) {
      if (msg['method'] == 'agent.stream' &&
          msg['params']['sessionId'] == sessionId) {
        final current = _getState(sessionId);
        state = {
          ...state,
          sessionId: current.copyWith(
            isProcessing: true,
            streamedContent:
                current.streamedContent + (msg['params']['chunk'] as String),
          ),
        };
      } else if (msg['method'] == 'agent.activity' &&
          msg['params']['sessionId'] == sessionId) {
        final current = _getState(sessionId);
        final activity = msg['params']['activity'] as String?;
        state = {
          ...state,
          sessionId: current.copyWith(
            activity: activity?.isEmpty ?? false ? null : activity,
            clearActivity: activity?.isEmpty ?? true,
          ),
        };
      } else if (msg['method'] == 'agent.response' &&
          msg['params']['sessionId'] == sessionId) {
        final current = _getState(sessionId);
        final messageData = msg['params']['message'] as Map<String, dynamic>;
        final message = ChatMessage.fromJson(messageData);
        state = {
          ...state,
          sessionId: current.copyWith(
            isProcessing: false,
            streamedContent: '',
            clearActivity: true,
            messages: [...current.messages, message],
          ),
        };
        // Refresh sessions list
        ref.read(sessionsProvider.notifier).refresh();
      } else if (msg['method'] == 'agent.session_updated' &&
          msg['params']['sessionId'] == sessionId) {
        // Refresh history to get the system message for rename
        _loadHistory(sessionId);
      }
    });
  }

  Future<void> _loadHistory(String sessionId) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('agent.history', {
        'sessionId': sessionId,
      });
      final msgsData = result['messages'] as List<dynamic>;
      final msgs = msgsData
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList();
      final current = _getState(sessionId);
      state = {
        ...state,
        sessionId: current.copyWith(
          messages: msgs,
        ),
      };
    } catch (_) {}
  }

  void addMessageEntry(String sessionId, Map<String, dynamic> messageData) {
    final message = ChatMessage.fromJson(messageData);
    final current = _getState(sessionId);
    state = {
      ...state,
      sessionId: current.copyWith(messages: [...current.messages, message]),
    };
  }

  void setProcessing(String sessionId, bool processing) {
    final current = _getState(sessionId);
    state = {...state, sessionId: current.copyWith(isProcessing: processing)};
  }

  void stop(String sessionId) async {
    try {
      await ref.read(gatewayClientProvider).call('agent.stop', {
        'sessionId': sessionId,
      });
      final current = _getState(sessionId);
      state = {
        ...state,
        sessionId: current.copyWith(isProcessing: false, clearActivity: true),
      };
    } catch (_) {}
  }
}
