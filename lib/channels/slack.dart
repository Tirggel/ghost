// Ghost — Slack Channel implementation.
//
// Uses Slack's Events API (Socket Mode recommended for simplicity, but we use
// HTTP webhook mode here since we already have a Shelf HTTP server running).
//
// Setup:
//   1. Create a Slack App at https://api.slack.com/apps
//   2. Enable Event Subscriptions → Request URL: https://your-host/webhooks/slack
//   3. Subscribe to bot events: message.im, message.channels
//   4. Install the app to get Bot OAuth Token (xoxb-...)
//   5. Optionally set Signing Secret for request verification

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.SlackChannel');

/// Slack channel via Incoming Webhooks + Events API.
class SlackChannel extends Channel {
  SlackChannel({
    required this.botToken,
    this.signingSecret,
    this.botName = 'Ghost',
  });

  /// Bot OAuth Token (xoxb-...) — from Slack App settings.
  final String botToken;

  /// Optional signing secret for webhook verification.
  final String? signingSecret;

  final String botName;
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;
  String? _botUserId;

  @override
  String get type => 'slack';

  @override
  String get displayName => 'Slack ($botName)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;
    // Resolve our own bot user ID to filter self-messages
    try {
      final resp = await http.get(
        Uri.parse('https://slack.com/api/auth.test'),
        headers: {'Authorization': 'Bearer $botToken'},
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _botUserId = data['user_id'] as String?;
      _isRunning = true;
      _log.info('Slack connected. Bot user: $_botUserId');
    } catch (e) {
      _log.severe('Slack: Failed to connect: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _isRunning = false;
    _handler = null;
    _log.info('Slack channel disconnected');
  }

  /// Called by the gateway's webhook router when Slack sends an event.
  ///
  /// Register in ghost.dart:
  ///   router.post('/webhooks/slack', slackChannel.handleWebhook);
  Future<String> handleWebhook(Map<String, dynamic> payload) async {
    // Handle URL verification challenge
    if (payload['type'] == 'url_verification') {
      return payload['challenge'] as String? ?? '';
    }

    if (payload['type'] != 'event_callback') return 'ok';

    final event = payload['event'] as Map<String, dynamic>?;
    if (event == null) return 'ok';

    final eventType = event['type'] as String?;
    if (eventType != 'message') return 'ok';

    // Skip bot messages and subtypes (edits, deletes, etc.)
    if (event['subtype'] != null) return 'ok';
    if (event['bot_id'] != null) return 'ok';
    if (event['user'] == _botUserId) return 'ok';

    final text = event['text'] as String? ?? '';
    if (text.isEmpty || _handler == null) return 'ok';

    final senderId = event['user'] as String? ?? 'unknown';
    final channelId = event['channel'] as String? ?? '';
    final isDm = channelId.startsWith('D');

    final envelope = Envelope(
      id: event['client_msg_id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      channelType: 'slack',
      senderId: senderId,
      groupId: isDm ? null : channelId,
      content: text,
      timestamp: DateTime.now(),
      metadata: {
        'channelId': channelId,
        'teamId': payload['team_id'],
      },
    );
    _handler!(envelope);
    return 'ok';
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('Slack channel not connected');

    final channel = groupId ?? peerId;
    final resp = await http.post(
      Uri.parse('https://slack.com/api/chat.postMessage'),
      headers: {
        'Authorization': 'Bearer $botToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'channel': channel, 'text': content}),
    );

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      _log.severe('Slack sendMessage error: ${data['error']}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
