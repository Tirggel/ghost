import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_provider.dart';
import 'hitl_provider.dart';
import 'usage_provider.dart';
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

        // --- Deep Token Usage Extraction ---
        try {
          int input = 0;
          int output = 0;

          // 1. Direct extraction from metadata
          final metadata = messageData['metadata'] as Map<String, dynamic>?;
          if (metadata != null && metadata['usage'] is Map) {
            final usage = metadata['usage'] as Map;
            input = (usage['input'] as num?)?.toInt() ?? 0;
            output = (usage['output'] as num?)?.toInt() ?? 0;
          }

          // 2. Fallback: Deep extraction
          if (input == 0 && output == 0) {
            void findTokens(dynamic obj, [String parentKey = '']) {
              if (obj is Map) {
                for (final entry in obj.entries) {
                  final key = entry.key.toString().toLowerCase();
                  final val = entry.value;

                  if (val is num || val is String && int.tryParse(val) != null) {
                    final number = (val is num) ? val.toInt() : int.tryParse(val.toString()) ?? 0;
                    if (number > 0) {
                      final hasUsageContext = key.contains('token') || key.contains('usage') || parentKey.contains('usage');
                      final isInput = key.contains('input') || key.contains('prompt') || key.contains('context');
                      final isOutput = key.contains('output') || key.contains('completion') || key.contains('generated');

                      if (hasUsageContext) {
                        if (isInput && number > input) input = number;
                        if (isOutput && number > output) output = number;
                      }
                    }
                  } else if (val is Map || val is List) {
                    findTokens(val, key);
                  }
                }
              } else if (obj is List) {
                for (final item in obj) {
                  findTokens(item, parentKey);
                }
              }
            }
            findTokens(msg);
          }

          if (input > 0 || output > 0) {
            ref.read(tokenUsageProvider.notifier).addUsage(input, output);
            ref
                .read(sessionsProvider.notifier)
                .updateTokenUsage(sessionId, input, output);
          }
        } catch (_) {}

        // Auto-set HITL pending ONLY when backend explicitly flags it
        final isHitlPending =
            messageData['metadata']?['hitl_pending'] == true;
        if (isHitlPending) {
          ref.read(hitlProvider.notifier).setPending(sessionId);
        } else {
          ref.read(hitlProvider.notifier).reset(sessionId);
        }


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
      } else if (msg['method'] == 'agent.error' &&
          msg['params']['sessionId'] == sessionId) {
        final current = _getState(sessionId);
        final rawError = msg['params']['error'] as String?;
        String displayError = rawError ?? 'Unknown error';

        // Cleanup provider errors (e.g. OpenAI/OpenRouter rate limits)
        // Cleanup provider errors (e.g. OpenAI/OpenRouter rate limits)
        if (displayError.contains('OpenAI API error') ||
            displayError.contains('ProviderError')) {
          try {
            // Extract the JSON part if it exists
            final startIdx = displayError.indexOf('{');
            final endIdx = displayError.lastIndexOf('}');
            if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
              final jsonStr = displayError.substring(startIdx, endIdx + 1);
              final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
              
              bool isRateLimit = false;

              // Check for status 429 in various formats
              if (decoded['status'] == 429 || 
                  decoded['error']?['code'] == '429' ||
                  displayError.contains('(429)')) {
                isRateLimit = true;
              }

              if (decoded['error'] != null &&
                  decoded['error']['message'] != null) {
                displayError = decoded['error']['message'] as String;
              } else if (decoded['title'] != null) {
                displayError = decoded['title'] as String;
              }

              if (isRateLimit || 
                  displayError.toLowerCase().contains('rate limit') ||
                  displayError.contains('429')) {
                displayError = 'Rate limit exceeded: $displayError';
                displayError +=
                    '\n\n💡 Tipp: Versuche einen anderen Provider oder ein anderes Modell zu wählen.';
                
                // If this is a cron job session, pause the agent to prevent repeated failures
                if (sessionId.startsWith('cron_')) {
                  final agentId = sessionId.replaceFirst('cron_', '');
                  final config = ref.read(configProvider);
                  final agent = config.customAgents.firstWhere(
                    (a) => a['id'] == agentId,
                    orElse: () => null,
                  );
                  
                  if (agent != null && (agent['enabled'] ?? true)) {
                    // Update server-side to pause the agent
                    ref.read(configProvider.notifier).updateCustomAgent({
                      'id': agentId,
                      'enabled': false,
                    });
                    
                    displayError += '\n\n🚦 Agent wurde automatisch pausiert, um wiederholte Fehler zu vermeiden.';
                  }
                }
              }
            }
          } catch (e) {
            // Fallback to raw if parsing fails
          }
        }

        state = {
          ...state,
          sessionId: current.copyWith(
            isProcessing: false,
            clearActivity: true,
            messages: [
              ...current.messages,
              ChatMessage(
                role: 'error',
                content: '⚠️ $displayError',
                timestamp: DateTime.now().toIso8601String(),
              ),
            ],
          ),
        };
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
