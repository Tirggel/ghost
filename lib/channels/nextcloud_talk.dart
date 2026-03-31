// Ghost — Nextcloud Talk Channel implementation.
//
// Uses the Nextcloud Talk (Spreed) REST API.
// https://nextcloud-talk.readthedocs.io/en/latest/
//
// Setup:
//   1. Create a bot/user account in your Nextcloud instance
//   2. Generate an App Password in Security Settings
//   3. Note the Room Token of the conversation to join
//
// Settings to store in Ghost:
//   - token:      Base64 encoded "username:apppassword" (Basic Auth)
//   - apiUrl:     Nextcloud base URL (e.g. https://cloud.example.com)
//   - apiUrl2:    Room token (optional, for a specific room)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.NextcloudTalkChannel');

class NextcloudTalkChannel extends Channel {
  NextcloudTalkChannel({
    required this.nextcloudUrl,
    required this.basicAuthCredentials,
    this.roomToken,
  });

  /// Nextcloud instance URL (e.g. https://cloud.example.com)
  final String nextcloudUrl;

  /// Basic auth string: base64("username:apppassword")
  final String basicAuthCredentials;

  /// Optional: specific room token to listen in. If null, listens in all rooms.
  final String? roomToken;

  Timer? _pollTimer;
  final Map<String, int> _lastMessageIds = {};
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'nextcloudTalk';

  @override
  String get displayName => 'Nextcloud Talk ($nextcloudUrl)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;
    _isRunning = true;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _log.info('Nextcloud Talk channel connected');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Basic $basicAuthCredentials',
        'OCS-APIRequest': 'true',
        'Accept': 'application/json',
      };

  Future<void> _poll() async {
    if (!_isRunning || _handler == null) return;
    try {
      final rooms = await _getRooms();
      for (final room in rooms) {
        final token = room['token'] as String?;
        if (token == null) continue;
        if (roomToken != null && token != roomToken) continue;
        await _fetchMessages(token, room);
      }
    } catch (e) {
      _log.warning('Nextcloud Talk poll error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _getRooms() async {
    final url = Uri.parse('$nextcloudUrl/ocs/v2.php/apps/spreed/api/v4/room');
    final resp = await http.get(url, headers: _headers);
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((data['ocs']?['data']) as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> _fetchMessages(
      String token, Map<String, dynamic> room) async {
    final lastKnown = _lastMessageIds[token] ?? 0;
    final url = Uri.parse(
        '$nextcloudUrl/ocs/v2.php/apps/spreed/api/v1/chat/$token?lookIntoFuture=0&limit=20&lastKnownMessageId=$lastKnown');
    final resp = await http.get(url, headers: _headers);
    if (resp.statusCode != 200 && resp.statusCode != 304) return;
    if (resp.statusCode == 304) return;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final messages = (data['ocs']?['data']) as List<dynamic>? ?? [];

    for (final raw in messages.reversed) {
      final msg = raw as Map<String, dynamic>;
      final id = (msg['id'] as num?)?.toInt() ?? 0;
      if (id <= lastKnown) continue;

      _lastMessageIds[token] = id;

      final msgType = msg['messageType'] as String? ?? '';
      if (msgType == 'system') continue;

      final content = msg['message'] as String? ?? '';
      if (content.isEmpty) continue;

      final actorId = msg['actorId'] as String? ?? 'unknown';
      final actorType = msg['actorType'] as String? ?? '';
      // Skip messages from ourselves (guests and bots)
      if (actorType == 'bots') continue;

      _handler!(Envelope(
        id: id.toString(),
        channelType: 'nextcloudTalk',
        senderId: actorId,
        groupId: token,
        content: content,
        timestamp: msg['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (msg['timestamp'] as num).toInt() * 1000)
            : DateTime.now(),
        metadata: {
          'actorDisplayName': msg['actorDisplayName'],
          'roomDisplayName': room['displayName'],
        },
      ));
    }
  }

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isRunning = false;
    _log.info('Nextcloud Talk channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('Nextcloud Talk channel not connected');

    final token = groupId ?? peerId;
    final url = Uri.parse(
        '$nextcloudUrl/ocs/v2.php/apps/spreed/api/v1/chat/$token');

    final resp = await http.post(
      url,
      headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'message': content},
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      _log.severe('Nextcloud Talk sendMessage failed: ${resp.body}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
