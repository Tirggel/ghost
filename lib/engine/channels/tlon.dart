// Ghost — Tlon / Urbit Channel implementation.
//
// Tlon is the application platform built on Urbit (groups.tlon.io).
// Communication happens via the Urbit Eyre HTTP API using "channels" (SSE).
// https://developers.urbit.org/reference/eyre/external-channel
//
// Setup:
//   1. Have an Urbit ship running (can be a hosted ship on tlon.io)
//   2. Log in to your ship's web interface to get a +code (session key)
//   3. Use that code as the token here
//
// Settings to store in Ghost:
//   - token:    Urbit session code (from |code in dojo/landscape)
//   - apiUrl:   Ship URL (e.g. http://localhost or https://your.tlon.io)
//   - apiUrl2:  Urbit ship name (e.g. ~sampel-palnet)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.TlonChannel');
const _uuid = Uuid();

class TlonChannel extends Channel {
  TlonChannel({
    required this.shipUrl,
    required this.code,
    required this.shipName,
  });

  final String shipUrl;
  final String code;
  final String shipName;

  String? _cookie;
  String? _uid;
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;
  StreamSubscription<dynamic>? _sseSub;

  @override
  String get type => 'tlon';

  @override
  String get displayName => 'Tlon/Urbit ($shipName)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;

    // 1. Log in with the +code
    try {
      final loginResp = await http.post(
        Uri.parse('$shipUrl/~/login'),
        body: {'password': code},
      );
      final setCookie = loginResp.headers['set-cookie'];
      if (setCookie == null || loginResp.statusCode != 204) {
        _log.severe('Tlon: Login failed (status ${loginResp.statusCode})');
        return;
      }
      _cookie = setCookie.split(';').first;
      _uid = _uuid.v4();

      // 2. Open an Eyre channel (SSE)
      final channelUrl = '$shipUrl/~/channel/$_uid';
      final putResp = await http.put(
        Uri.parse(channelUrl),
        headers: {
          'Cookie': _cookie!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode([
          {
            'id': 1,
            'action': 'subscribe',
            'ship': shipName.replaceFirst('~', ''),
            'app': 'chat-store',
            'path': '/mailbox/updates',
          }
        ]),
      );

      if (putResp.statusCode != 200 && putResp.statusCode != 204) {
        _log.warning('Tlon: Channel subscription may have failed: ${putResp.statusCode}');
      }

      _isRunning = true;
      _log.info('Tlon/Urbit connected for $shipName');
      _startSSE(channelUrl);
    } catch (e) {
      _log.severe('Tlon: Failed to connect: $e');
    }
  }

  void _startSSE(String channelUrl) {
    // Dart's http package doesn't support SSE natively.
    // We manually read the SSE stream line by line.
    unawaited(_sseLoop(channelUrl));
  }

  Future<void> _sseLoop(String channelUrl) async {
    try {
      final request = http.Request('GET', Uri.parse(channelUrl));
      request.headers['Cookie'] = _cookie!;
      request.headers['Accept'] = 'text/event-stream';
      final client = http.Client();
      final response = await client.send(request);

      final StringBuffer dataBuffer = StringBuffer();
      _sseSub = response.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            dataBuffer.write(line.substring(6));
          } else if (line.isEmpty && dataBuffer.isNotEmpty) {
            _processSSEData(dataBuffer.toString());
            dataBuffer.clear();
          }
        },
        onDone: () {
          _isRunning = false;
          client.close();
        },
      );
    } catch (e) {
      _log.warning('Tlon SSE error: $e');
    }
  }

  void _processSSEData(String data) {
    if (_handler == null) return;
    try {
      final payload = jsonDecode(data) as Map<String, dynamic>;
      // Process chat messages from the Urbit chat-store
      _log.fine('Tlon SSE event: ${payload['response']}');
      // Full Urbit graph-store/chat-store parsing is complex and version-dependent.
      // This is the hook point where you'd parse the Urbit poke/diff structure.
    } catch (e) {
      _log.warning('Tlon: Error parsing SSE data: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    await _sseSub?.cancel();
    _isRunning = false;
    _log.info('Tlon channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning || _cookie == null) {
      throw Exception('Tlon channel not connected');
    }

    _log.warning('Tlon: Sending messages requires Urbit graph-store poke. '
        'Implement by poking the chat-store with the target path.');
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
