// Ghost — Message router from channels to agents and back.

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../channels/envelope.dart';
import '../sessions/manager.dart';

final _log = Logger('Ghost.Router');

const _uuid = Uuid();

/// Routes messages between channels, sessions, and agents.
class MessageRouter {
  MessageRouter({required this.sessionManager});

  final SessionManager sessionManager;

  /// Registered message handlers by channel type.
  final Map<String, MessageHandler> _handlers = {};

  /// Register a handler for outgoing messages to a channel.
  void registerHandler(String channelType, MessageHandler handler) {
    _handlers[channelType] = handler;
    _log.fine('Registered handler for channel: $channelType');
  }

  /// Unregister a channel handler.
  void unregisterHandler(String channelType) {
    _handlers.remove(channelType);
  }

  /// Route an incoming message from a channel to the agent.
  ///
  /// Returns the session ID used for routing.
  Future<String> routeIncoming(Envelope envelope) async {
    _log.info(
      'Incoming message from ${envelope.channelType}:'
      '${envelope.senderId}',
    );

    // Resolve or create session
    final session = await sessionManager.resolveSession(
      channelType: envelope.channelType,
      peerId: envelope.senderId,
      groupId: envelope.groupId,
    );

    // Store the message in the session
    await sessionManager.addMessage(
      sessionId: session.id,
      role: 'user',
      content: envelope.content,
      metadata: {
        'channelType': envelope.channelType,
        'senderId': envelope.senderId,
        if (envelope.groupId != null) 'groupId': envelope.groupId,
        'envelopeId': envelope.id,
      },
    );

    _log.fine('Routed to session: ${session.id}');
    return session.id;
  }

  /// Route an outgoing message from the agent back to a channel.
  Future<void> routeOutgoing({
    required String channelType,
    required String peerId,
    required String content,
    String? groupId,
  }) async {
    final handler = _handlers[channelType];
    if (handler == null) {
      _log.warning('No handler for channel type: $channelType');
      return;
    }

    final envelope = Envelope(
      id: _uuid.v4(),
      channelType: channelType,
      senderId: 'agent',
      content: content,
      timestamp: DateTime.now(),
      metadata: {'peerId': peerId, 'groupId': ?groupId},
    );

    await handler(envelope);
    _log.fine('Outgoing message sent to $channelType:$peerId');
  }
}

/// Type definition for message handlers.
typedef MessageHandler = Future<void> Function(Envelope envelope);
