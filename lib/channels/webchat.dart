// Ghost — WebChat Channel implementation.
// WebSocket-based channel for the built-in browser/app chat widget.
// The Gateway already runs a WebSocket server; this channel bridges
// direct /chat WebSocket connections into the channel pipeline.

import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.WebChatChannel');

/// A simple WebSocket-based channel.
/// Clients connect to ws://host:port/webchat and exchange JSON messages.
///
/// Incoming: { "senderId": "user123", "content": "Hello!" }
/// Outgoing: { "type": "message", "content": "Hi there!" }
class WebChatChannel extends Channel {
  WebChatChannel({
    required this.host,
    required this.port,
  });

  final String host;
  final int port;

  final Map<String, WebSocketChannel> _connections = {};
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'webchat';

  @override
  String get displayName => 'WebChat (ws://$host:$port/webchat)';

  @override
  bool get isConnected => _isRunning;

  /// Called by the gateway's HTTP server to register this channel's handler.
  Handler get handler => webSocketHandler(_handleWebSocket);

  void _handleWebSocket(WebSocketChannel ws) {
    String? clientId;

    ws.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data.toString()) as Map<String, dynamic>;
          clientId ??= msg['senderId'] as String? ??
              DateTime.now().millisecondsSinceEpoch.toString();
          _connections[clientId!] = ws;

          final content = msg['content'] as String? ?? '';
          if (content.isEmpty || _handler == null) return;

          final envelope = Envelope(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            channelType: 'webchat',
            senderId: clientId!,
            content: content,
            timestamp: DateTime.now(),
            metadata: {'sessionId': msg['sessionId']},
          );
          _handler!(envelope);
        } catch (e) {
          _log.warning('WebChat: Failed to parse message: $e');
        }
      },
      onDone: () {
        if (clientId != null) _connections.remove(clientId);
        _log.fine('WebChat: Client $clientId disconnected');
      },
      onError: (Object e) {
        _log.warning('WebChat: WS error for $clientId: $e');
      },
    );
  }

  @override
  Future<void> connect() async {
    _isRunning = true;
    _log.info('WebChat channel ready — connections handled via gateway');
  }

  @override
  Future<void> disconnect() async {
    for (final ws in _connections.values) {
      await ws.sink.close();
    }
    _connections.clear();
    _isRunning = false;
    _log.info('WebChat channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    final ws = _connections[peerId];
    if (ws == null) {
      _log.warning('WebChat: No active connection for $peerId');
      return;
    }
    ws.sink.add(jsonEncode({'type': 'message', 'content': content}));
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
