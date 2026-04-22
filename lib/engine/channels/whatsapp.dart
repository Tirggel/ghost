// Ghost — WhatsApp Channel implementation.
//
// Uses the Meta WhatsApp Business Cloud API.
// https://developers.facebook.com/docs/whatsapp/cloud-api/
//
// Setup:
//   1. Create a Meta Developer App at https://developers.facebook.com
//   2. Add "WhatsApp" product → get a Phone Number ID
//   3. Generate a permanent System User access token
//   4. Configure Webhooks → Callback URL: https://your-host/webhooks/whatsapp
//   5. Verify token: a string YOU define (e.g. "my_verify_token_123")
//   6. Subscribe to "messages" events
//
// Settings to store in Ghost:
//   - token:          WhatsApp API Token (permanent access token)
//   - phoneNumberId:  Your WhatsApp Phone Number ID

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.WhatsAppChannel');

class WhatsAppChannel extends Channel {
  WhatsAppChannel({
    required this.apiToken,
    required this.phoneNumberId,
    this.verifyToken = 'ghost_verify',
  });

  final String apiToken;
  final String phoneNumberId;
  final String verifyToken;

  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'whatsapp';

  @override
  String get displayName => 'WhatsApp (Phone: $phoneNumberId)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    _isRunning = true;
    _log.info('WhatsApp channel ready. Waiting for webhook events.');
  }

  @override
  Future<void> disconnect() async {
    _isRunning = false;
    _handler = null;
    _log.info('WhatsApp channel disconnected');
  }

  /// Called by the gateway's webhook router for GET (verification) requests.
  /// Returns the challenge string if verifyToken matches, else throws.
  String handleVerification(Map<String, String> queryParams) {
    final mode = queryParams['hub.mode'];
    final token = queryParams['hub.verify_token'];
    final challenge = queryParams['hub.challenge'];

    if (mode == 'subscribe' && token == verifyToken && challenge != null) {
      _log.info('WhatsApp webhook verified successfully');
      return challenge;
    }
    throw Exception('WhatsApp: Webhook verification failed');
  }

  /// Called by the gateway's webhook router for POST (events) requests.
  void handleWebhook(Map<String, dynamic> payload) {
    if (_handler == null || !_isRunning) return;

    try {
      final entries = payload['entry'] as List<dynamic>? ?? [];
      for (final entry in entries) {
        final changes = (entry as Map)['changes'] as List<dynamic>? ?? [];
        for (final change in changes) {
          final value = (change as Map)['value'] as Map<String, dynamic>?;
          if (value == null) continue;

          final messages = value['messages'] as List<dynamic>? ?? [];
          for (final msg in messages) {
            final msgMap = msg as Map<String, dynamic>;
            final msgType = msgMap['type'] as String;
            if (msgType != 'text') continue; // Skip non-text for now

            final from = msgMap['from'] as String;
            final text =
                (msgMap['text'] as Map<String, dynamic>)['body'] as String;
            final msgId = msgMap['id'] as String;

            final envelope = Envelope(
              id: msgId,
              channelType: 'whatsapp',
              senderId: from,
              content: text,
              timestamp: DateTime.now(),
              metadata: {
                'phoneNumberId': phoneNumberId,
                'displayPhone': value['metadata']?['display_phone_number'],
              },
            );
            _handler!(envelope);
          }
        }
      }
    } catch (e) {
      _log.warning('WhatsApp: Error processing webhook: $e');
    }
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('WhatsApp channel not connected');

    final url = Uri.parse(
      'https://graph.facebook.com/v19.0/$phoneNumberId/messages',
    );

    final resp = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messaging_product': 'whatsapp',
        'to': peerId,
        'type': 'text',
        'text': {'body': content},
      }),
    );

    if (resp.statusCode != 200) {
      _log.severe('WhatsApp sendMessage failed: ${resp.body}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
