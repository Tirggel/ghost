// Ghost — Zalo Channel implementation.
//
// Zalo is Vietnam's most popular messaging platform.
// Uses the Official Account (OA) Open API.
// https://developers.zalo.me/docs
//
// Setup:
//   1. Register at https://oa.zalo.me to create an Official Account
//   2. Create an app at https://developers.zalo.me
//   3. Get an Access Token (OA Access Token, long-lived)
//   4. Configure webhook: https://your-host/webhooks/zalo
//   5. Note your OA ID
//
// Settings to store in Ghost:
//   - token:    Zalo OA Access Token
//   - apiUrl:   Zalo OA ID (optional)

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.ZaloChannel');

class ZaloChannel extends Channel {
  ZaloChannel({required this.oaAccessToken, this.oaId});

  final String oaAccessToken;
  final String? oaId;

  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'zalo';

  @override
  String get displayName => 'Zalo OA (${oaId ?? 'Unknown OA'})';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    _isRunning = true;
    _log.info('Zalo channel ready. Waiting for webhook events.');
  }

  @override
  Future<void> disconnect() async {
    _isRunning = false;
    _log.info('Zalo channel disconnected');
  }

  /// Called by the gateway webhook router for Zalo events.
  void handleWebhook(Map<String, dynamic> payload) {
    if (_handler == null || !_isRunning) return;

    try {
      final eventName = payload['event_name'] as String? ?? '';
      if (eventName != 'user_send_text') return;

      final sender = payload['sender'] as Map<String, dynamic>?;
      final message = payload['message'] as Map<String, dynamic>?;

      if (sender == null || message == null) return;

      final senderId = sender['id'] as String? ?? 'unknown';
      final text = message['text'] as String? ?? '';
      final msgId = message['msg_id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString();

      if (text.isEmpty) return;

      _handler!(Envelope(
        id: msgId,
        channelType: 'zalo',
        senderId: senderId,
        content: text,
        timestamp: DateTime.now(),
        metadata: {
          'senderId': senderId,
          'oaId': oaId,
        },
      ));
    } catch (e) {
      _log.warning('Zalo: Error processing webhook: $e');
    }
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('Zalo channel not connected');

    final resp = await http.post(
      Uri.parse('https://openapi.zalo.me/v3.0/oa/message/cs'),
      headers: {
        'access_token': oaAccessToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'recipient': {'user_id': peerId},
        'message': {'text': content},
      }),
    );

    if (resp.statusCode != 200) {
      _log.severe('Zalo sendMessage failed: ${resp.body}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
