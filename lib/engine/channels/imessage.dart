// Ghost — iMessage Channel implementation (via BlueBubbles server).
//
// iMessage is Apple's proprietary messaging system and traditionally requires
// a physical Mac to send/receive. The recommended approach for Linux/Docker is
// BlueBubbles: a self-hosted Mac server that exposes a REST+WebSocket API.
// https://bluebubbles.app
//
// Setup:
//   1. Install BlueBubbles Server on a Mac
//   2. Configure BlueBubbles → note the server URL and password
//   3. Enable WebSocket in BlueBubbles settings
//
// Settings to store in Ghost:
//   - token:    BlueBubbles server password
//   - apiUrl:   BlueBubbles server URL (e.g. http://192.168.1.10:1234)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.IMessageChannel');

class IMessageChannel extends Channel {
  IMessageChannel({
    required this.serverUrl,
    required this.serverPassword,
  });

  final String serverUrl;
  final String serverPassword;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'imessage';

  @override
  String get displayName => 'iMessage (via BlueBubbles @ $serverUrl)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;

    final wsUrl = serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    _ws = WebSocketChannel.connect(
        Uri.parse('$wsUrl/socket.io/?password=$serverPassword'));
    _isRunning = true;

    _sub = _ws!.stream.listen(
      (raw) {
        try {
          // BlueBubbles uses Socket.IO framing; messages start with "42"
          final data = raw.toString();
          if (!data.startsWith('42')) return;

          final payload = jsonDecode(data.substring(2)) as List<dynamic>;
          if (payload[0] == 'new-message') {
            _processMessage(payload[1] as Map<String, dynamic>);
          }
        } catch (e) {
          _log.warning('iMessage: Error parsing message: $e');
        }
      },
      onError: (Object e) => _log.warning('iMessage WS error: $e'),
      onDone: () {
        _isRunning = false;
        _log.info('iMessage WS connection closed');
      },
    );

    _log.info('iMessage channel connected to BlueBubbles @ $serverUrl');
  }

  void _processMessage(Map<String, dynamic> msg) {
    if (_handler == null) return;

    final isFromMe = msg['isFromMe'] as bool? ?? true;
    if (isFromMe) return;

    final text = msg['text'] as String? ?? '';
    if (text.isEmpty) return;

    final handle = msg['handle'] as Map<String, dynamic>?;
    final senderId = handle?['address'] as String? ?? 'unknown';
    final guid = msg['guid'] as String? ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final chatGuid = msg['chats'] != null
        ? ((msg['chats'] as List).first as Map)['guid'] as String?
        : null;

    _handler!(Envelope(
      id: guid,
      channelType: 'imessage',
      senderId: senderId,
      groupId: chatGuid,
      content: text,
      timestamp: msg['dateCreated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (msg['dateCreated'] as num).toInt())
          : DateTime.now(),
      metadata: {'chatGuid': chatGuid},
    ));
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    _isRunning = false;
    _log.info('iMessage channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('iMessage channel not connected');

    final url = Uri.parse('$serverUrl/api/v1/message/text');
    final resp = await http.post(
      url,
      headers: {
        'Authorization': 'Token $serverPassword',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'chatGuid': groupId ?? 'iMessage;-;$peerId',
        'message': content,
        'method': 'apple-script',
      }),
    );

    if (resp.statusCode != 200) {
      _log.severe('iMessage sendMessage failed: ${resp.body}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
