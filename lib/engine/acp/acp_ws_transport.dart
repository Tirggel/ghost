// Ghost — ACP WebSocket Transport.
// Enables ACP over WebSockets for Antigravity IDE and remote clients.

import 'dart:async';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../gateway/protocol.dart';
import 'acp_server.dart';

final _log = Logger('Ghost.AcpWs');

/// Handles an ACP connection over a WebSocket channel.
class AcpWebSocketClient {
  AcpWebSocketClient({
    required this.server,
    required this.channel,
    required this.clientId,
  }) {
    _init();
  }

  final AcpServer server;
  final WebSocketChannel channel;
  final String clientId;
  StreamSubscription<dynamic>? _sub;

  void _init() {
    _sub = channel.stream.listen(
      _onMessage,
      onError: (Object error) {
        _log.warning('WebSocket ACP client $clientId error: $error');
        dispose();
      },
      onDone: () {
        _log.info('WebSocket ACP client $clientId disconnected');
        dispose();
      },
    );

    // Forward server notifications to this WebSocket client
    server.onNotification = (RpcRequest notification) {
      send(notification.toJsonString());
    };
  }

  Future<void> _onMessage(dynamic raw) async {
    if (raw is! String) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    try {
      final response = await server.handleRawMessage(trimmed);
      if (response != null) {
        send(response);
      }
    } catch (e) {
      _log.warning('Failed to handle ACP WS message: $e');
    }
  }

  void send(String message) {
    try {
      channel.sink.add(message);
    } catch (e) {
      _log.warning('Failed to send message to ACP WS client $clientId: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    try {
      channel.sink.close();
    } catch (_) {}
  }
}
