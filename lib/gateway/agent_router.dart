// Ghost — Agent RPC Router.

import 'dart:async';
import 'package:logging/logging.dart';

import '../infra/errors.dart';
import '../gateway/server.dart';
import '../agent/manager.dart';
import '../agent/agent.dart';
import '../models/message.dart';
import '../sessions/manager.dart';
import '../sessions/session.dart';
import '../config/config.dart';

final _log = Logger('Ghost.AgentRouter');

/// Routes RPC requests from the Gateway to the Agent runtime.
class AgentRouter {
  AgentRouter({
    required this.agentManager,
    required this.gateway,
    required this.sessionManager,
  });

  final AgentManager agentManager;
  final GatewayServer gateway;
  final SessionManager sessionManager;

  /// Register all agent-related RPC methods to the gateway's registry.
  void register() {
    // 1. Send a message to the agent
      gateway.rpcRegistry.register('agent.chat', (params, context) async {
        final content = params?['content'] as String?;
        if (content == null) {
          throw ProtocolError('Missing required parameter: content');
        }
        final rawAttachments = params?['attachments'] as List<dynamic>?;
        final attachments = rawAttachments
                ?.map((a) =>
                    MessageAttachment.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [];

        final channelType = params?['channelType'] as String? ?? 'gateway';
        final String peerId =
            (params?['peerId'] as String?) ?? (context.clientId ?? 'unknown');
        final groupId = params?['groupId'] as String?;
        final model = params?['model'] as String?;
        final provider = params?['provider'] as String?;
        final targetAgentId = params?['agentId'] as String?;

        // Resolve session
        final reqSessionId = params?['sessionId'] as String?;
        late Session session;

        if (reqSessionId != null) {
          session = sessionManager.getSession(reqSessionId) ??
              sessionManager.createSession(
                id: reqSessionId,
                channelType: channelType,
                peerId: peerId,
                groupId: groupId,
              );
        } else {
          session = await sessionManager.resolveSession(
            channelType: channelType,
            peerId: peerId,
            groupId: groupId,
          );
        }

        if (model != null) {
          session.model = model;
        }
        if (provider != null) {
          session.provider = provider;
        }

        // Add user message to history
        await sessionManager.addMessage(
          sessionId: session.id,
          role: 'user',
          content: content,
          attachments: attachments,
          metadata: {
            'channelType': channelType,
            'senderId': peerId,
            if (groupId != null) 'groupId': groupId,
            if (model != null) 'model': model,
            if (provider != null) 'provider': provider,
            if (targetAgentId != null) 'agentId': targetAgentId,
          },
        );

        // Trigger agent processing in the background
        unawaited(_processInAgent(session.id, content, targetAgentId,
            attachments: attachments));

        return {
          'sessionId': session.id,
          'status': 'processing',
        };
      });

    // 2. Query session history
    gateway.rpcRegistry.register('agent.history', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }
      final maxMessages = params?['maxMessages'] as int? ?? 50;

      final history =
          await sessionManager.getHistory(sessionId, maxMessages: maxMessages);
      return {
        'sessionId': sessionId,
        'messages': history.map((m) => m.toJson()).toList(),
      };
    });

    // 3. List active sessions
    gateway.rpcRegistry.register('agent.sessions', (params, context) async {
      return {'sessions': sessionManager.listSessions()};
    });

    // 4. Delete a session
    gateway.rpcRegistry.register('agent.deleteSession',
        (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }
      await sessionManager.deleteSession(sessionId);
      return {'status': 'ok', 'sessionId': sessionId};
    });

    // 5. Set model for a specific session
    gateway.rpcRegistry.register('agent.setSessionModel',
        (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      final model = params?['model'] as String?;
      final provider = params?['provider'] as String?;
      if (sessionId == null || model == null) {
        throw ProtocolError('Missing required parameter: sessionId or model');
      }
      final session = sessionManager.getSession(sessionId);
      if (session != null) {
        session.model = model;
        session.provider = provider;
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'system',
          content: 'session_config_update',
          metadata: {
            'model': model,
            if (provider != null) 'provider': provider,
          },
        );
      }
      return {'status': 'ok', 'sessionId': sessionId, 'model': model};
    });

    // 6. Stop/Interrupt processing for a session
    gateway.rpcRegistry.register('agent.stop', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }
      agentManager.stop(sessionId);
      return {'status': 'ok', 'sessionId': sessionId};
    });

    // 7. Memory backup and restore
    gateway.rpcRegistry.register('memory.backup', (params, context) async {
      return {'status': 'ok', 'data': await agentManager.memoryEngine.backup()};
    });

    gateway.rpcRegistry.register('memory.restore', (params, context) async {
      final data = params?['data'] as String?;
      if (data == null) throw ProtocolError('Missing required parameter: data');
      await agentManager.memoryEngine.restore(data);
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('memory.rag.backup', (params, context) async {
      return {'status': 'ok', 'data': await agentManager.ragMemoryEngine.backup()};
    });

    gateway.rpcRegistry.register('memory.rag.restore', (params, context) async {
      final data = params?['data'] as String?;
      if (data == null) throw ProtocolError('Missing required parameter: data');
      await agentManager.ragMemoryEngine.restore(data);
      return {'status': 'ok'};
    });
  }

  Future<void> _processInAgent(
      String sessionId, String content, String? agentId,
      {List<MessageAttachment> attachments = const []}) async {
    try {
      final session = sessionManager.getSession(sessionId);
      final agent = agentManager.getAgent(agentId ?? session?.agentId);

      session?.agentName = agent.id == 'default-agent'
          ? agentManager.config.identity.name
          : '${agentManager.config.customAgents.firstWhere((a) => a.id == agent.id, orElse: () => const CustomAgentConfig(id: '', name: 'Unknown')).name} Agent';

      await agent.processMessage(
        sessionId: sessionId,
        content: content,
        attachments: attachments,
        model: session?.model,
        providerHint: session?.provider,
        onPartialResponse: (chunk) {
          // Stream partial response to all authenticated gateway clients
          gateway.broadcast('agent.stream', {
            'sessionId': sessionId,
            'chunk': chunk,
          });
        },
        onActivityUpdate: (activity) {
          gateway.broadcast('agent.activity', {
            'sessionId': sessionId,
            'activity': activity,
          });
        },
      );

      // Auto-rename if this is the first interaction (user + assistant)
      if (session != null && session.history.length == 2) {
        unawaited(_autoRenameSession(session, agent));
      }

      // Notify completion
      if (session != null && session.history.isNotEmpty) {
        final lastMsg = session.history.last;
        gateway.broadcast('agent.response', {
          'sessionId': sessionId,
          'message': lastMsg.toJson(),
        });
      }
    } catch (e) {
      _log.severe('Agent routing error: $e');
      gateway.broadcast('agent.error', {
        'sessionId': sessionId,
        'error': e.toString(),
      });
    }
  }

  Future<void> _autoRenameSession(Session session, Agent agent) async {
    try {
      _log.info('Auto-renaming session ${session.id}...');

      // Create a prompt for summarization
      final mainPrompt = agent.systemPrompt;
      final summaryPrompt = '''
As an AI assistant, your task is to create a very short, concise title for this conversation (maximum 5-6 words).
Based on the first user message and your response, provide ONLY the title, no quotes or prefix.
 
Conversation context:
$mainPrompt
''';

      final messages = List<Message>.from(session.history);
      messages.add(Message(
        role: 'user',
        content: summaryPrompt,
        timestamp: DateTime.now(),
      ));

      final response = await agent.provider.chat(
        messages: messages,
        systemPrompt:
            'You are a session titling assistant. Be extremely concise.',
      );

      if (response.content.isNotEmpty) {
        final title = response.content.trim().replaceAll('"', '');
        session.title = title;
        _log.info('Session ${session.id} renamed to: $title');

        // Persist title via a system message
        await sessionManager.addMessage(
          sessionId: session.id,
          role: 'system',
          content: 'session_rename',
          metadata: {'title': title},
        );

        // Broadcast update
        gateway.broadcast('agent.session_updated', {
          'sessionId': session.id,
          'title': title,
        });
      }
    } catch (e) {
      _log.warning('Auto-rename failed for session ${session.id}: $e');
    }
  }
}
