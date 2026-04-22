// Ghost — Microsoft Teams Channel implementation.
//
// Uses the Azure Bot Framework / MS Teams Bot API.
// Teams sends events to a public HTTPS webhook; you reply via the serviceUrl.
//
// Setup:
//   1. Register a Bot in Azure (https://portal.azure.com)
//   2. Connect the bot to Microsoft Teams in Azure Bot Channels
//   3. Set Messaging Endpoint to: https://your-host/webhooks/msteams
//   4. Note your App ID and App Password (Client Secret)
//
// Settings to store in Ghost:
//   - token:    App Password / Client Secret
//   - apiUrl:   App ID (Microsoft App ID / Client ID)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.MsTeamsChannel');

class MsTeamsChannel extends Channel {
  MsTeamsChannel({
    required this.appId,
    required this.appPassword,
  });

  final String appId;
  final String appPassword;

  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;
  String? _accessToken;
  DateTime? _tokenExpiry;

  @override
  String get type => 'msTeams';

  @override
  String get displayName => 'Microsoft Teams (App: $appId)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    _isRunning = true;
    await _refreshToken();
    _log.info('MS Teams channel ready. Waiting for webhook events.');
  }

  Future<void> _refreshToken() async {
    try {
      final resp = await http.post(
        Uri.parse(
            'https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token'),
        body: {
          'grant_type': 'client_credentials',
          'client_id': appId,
          'client_secret': appPassword,
          'scope': 'https://api.botframework.com/.default',
        },
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
        _tokenExpiry =
            DateTime.now().add(Duration(seconds: expiresIn - 60));
        _log.fine('MS Teams: Access token refreshed');
      }
    } catch (e) {
      _log.warning('MS Teams: Token refresh failed: $e');
    }
  }

  Future<String> _getToken() async {
    if (_accessToken == null ||
        _tokenExpiry == null ||
        DateTime.now().isAfter(_tokenExpiry!)) {
      await _refreshToken();
    }
    return _accessToken ?? '';
  }

  /// Called by the gateway webhook router when Teams sends an Activity.
  Future<void> handleWebhook(Map<String, dynamic> activity) async {
    if (_handler == null || !_isRunning) return;

    final activityType = activity['type'] as String?;
    if (activityType != 'message') return;

    final text = activity['text'] as String? ?? '';
    if (text.isEmpty) return;

    final from = activity['from'] as Map<String, dynamic>?;
    final senderId = from?['id'] as String? ?? 'unknown';
    final senderName = from?['name'] as String?;

    final conversation = activity['conversation'] as Map<String, dynamic>?;
    final conversationId = conversation?['id'] as String? ?? senderId;
    final isGroup = conversation?['isGroup'] == true;

    final serviceUrl = activity['serviceUrl'] as String? ?? '';
    final channelId = activity['channelId'] as String? ?? '';
    final activityId = activity['id'] as String? ?? '';

    _handler!(Envelope(
      id: activityId,
      channelType: 'msTeams',
      senderId: senderId,
      groupId: isGroup ? conversationId : null,
      content: text.trim(),
      timestamp: DateTime.now(),
      metadata: {
        'serviceUrl': serviceUrl,
        'conversationId': conversationId,
        'channelId': channelId,
        'senderName': senderName,
        'replyToId': activityId,
      },
    ));
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('MS Teams channel not connected');

    // NOTE: Teams replies require the serviceUrl + conversationId from the
    // original message's metadata. This simple implementation assumes the
    // caller passes the serviceUrl as peerId for reply mode.
    //
    // For production use: store the serviceUrl from handleWebhook in a map
    // keyed by conversationId and look it up here.
    _log.warning(
        'MS Teams sendMessage: Please use reply mode via handleWebhook metadata');
  }

  /// Reply to a specific Teams message using its Activity metadata.
  Future<void> replyToActivity({
    required String serviceUrl,
    required String conversationId,
    required String content,
  }) async {
    final token = await _getToken();
    final url = Uri.parse(
        '$serviceUrl/v3/conversations/$conversationId/activities');

    final resp = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'message',
        'text': content,
      }),
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      _log.severe('MS Teams reply failed: ${resp.body}');
    }
  }

  @override
  Future<void> disconnect() async {
    _isRunning = false;
    _accessToken = null;
    _log.info('MS Teams channel disconnected');
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
