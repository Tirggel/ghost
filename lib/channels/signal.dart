// Ghost — Signal Channel implementation.
//
// Uses the signal-cli REST API (self-hosted):
//   https://github.com/bbernhard/signal-cli-rest-api
//
// Quick setup with Docker:
//   docker run -p 8080:8080 -v /your/path:/home/.local/share/signal-cli \
//     -e MODE=normal bbernhard/signal-cli-rest-api
//
// Then register your phone number and configure here.
//
// Settings to store in Ghost:
//   - token:       The phone number registered with signal-cli (e.g. +4912345678)
//   - apiUrl:      The REST API base URL (e.g. http://localhost:8080)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.SignalChannel');

class SignalChannel extends Channel {
  SignalChannel({
    required this.phoneNumber,
    required this.apiUrl,
  });

  final String phoneNumber;
  final String apiUrl;

  Timer? _pollTimer;
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'signal';

  @override
  String get displayName => 'Signal ($phoneNumber)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;
    _isRunning = true;
    // Poll for new messages every 3 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _log.info('Signal channel connected. Polling $apiUrl for $phoneNumber');
  }

  Future<void> _poll() async {
    if (!_isRunning || _handler == null) return;
    try {
      final url = Uri.parse('$apiUrl/v1/receive/$phoneNumber');
      final resp = await http.get(url);
      if (resp.statusCode != 200) return;

      final messages = jsonDecode(resp.body) as List<dynamic>;
      for (final raw in messages) {
        final msg = raw as Map<String, dynamic>;
        final envelope = msg['envelope'] as Map<String, dynamic>?;
        if (envelope == null) continue;

        final dataMessage = envelope['dataMessage'] as Map<String, dynamic>?;
        if (dataMessage == null) continue;

        final text = dataMessage['message'] as String? ?? '';
        if (text.isEmpty) continue;

        final source = envelope['source'] as String? ?? 'unknown';
        final timestamp = envelope['timestamp'] as int?;

        _handler!(Envelope(
          id: timestamp?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          channelType: 'signal',
          senderId: source,
          content: text,
          timestamp: timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              : DateTime.now(),
          metadata: {
            'sourceName': envelope['sourceName'],
          },
        ));
      }
    } catch (e) {
      _log.warning('Signal poll error: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isRunning = false;
    _log.info('Signal channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('Signal channel not connected');

    final url = Uri.parse('$apiUrl/v2/send');
    final body = <String, dynamic>{
      'number': phoneNumber,
      'recipients': [peerId],
      'message': content,
    };

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) {
      _log.severe('Signal sendMessage failed: ${resp.body}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
