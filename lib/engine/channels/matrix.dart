// Ghost — Matrix Channel implementation.
//
// Uses the Matrix Client-Server API directly via HTTP.
// Supports any Matrix homeserver (matrix.org, your own Synapse, etc.)
//
// Setup:
//   1. Register a bot account on your homeserver (e.g. @ghost:matrix.org)
//   2. Log in via the Matrix API to get an access token:
//      curl -XPOST 'https://matrix.org/_matrix/client/v3/login' \
//        -d '{"type":"m.login.password","user":"ghost","password":"yourpw"}'
//
// Settings to store in Ghost:
//   - token:       Access token for the Matrix bot account
//   - apiUrl:      Homeserver URL (e.g. https://matrix.org)
//   - userId:      Full bot user ID (e.g. @ghost:matrix.org)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.MatrixChannel');

class MatrixChannel extends Channel {
  MatrixChannel({
    required this.accessToken,
    required this.homeserverUrl,
    required this.userId,
  });

  final String accessToken;
  final String homeserverUrl;
  final String userId;

  String? _nextBatch;
  bool _isRunning = false;
  void Function(Envelope envelope)? _handler;

  @override
  String get type => 'matrix';

  @override
  String get displayName => 'Matrix ($userId)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;
    _isRunning = true;
    _log.info('Matrix channel connected for $userId');
    unawaited(_syncLoop());
  }

  Future<void> _syncLoop() async {
    while (_isRunning) {
      try {
        await _sync();
      } catch (e) {
        _log.warning('Matrix sync error: $e');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  Future<void> _sync() async {
    final params = <String, String>{
      'access_token': accessToken,
      'timeout': '30000',
    };
    if (_nextBatch != null) params['since'] = _nextBatch!;

    final url = Uri.parse(
      '$homeserverUrl/_matrix/client/v3/sync',
    ).replace(queryParameters: params);

    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      _log.warning('Matrix sync failed: ${resp.statusCode}');
      return;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    _nextBatch = data['next_batch'] as String?;

    final rooms = (data['rooms'] as Map<String, dynamic>?)?['join']
        as Map<String, dynamic>?;
    if (rooms == null || _handler == null) return;

    for (final roomEntry in rooms.entries) {
      final roomId = roomEntry.key;
      final timeline =
          (roomEntry.value as Map)['timeline'] as Map<String, dynamic>?;
      final events = timeline?['events'] as List<dynamic>? ?? [];

      for (final event in events) {
        final e = event as Map<String, dynamic>;
        if (e['type'] != 'm.room.message') continue;
        if (e['sender'] == userId) continue; // Skip own messages

        final content = e['content'] as Map<String, dynamic>?;
        if (content?['msgtype'] != 'm.text') continue;

        final body = content?['body'] as String? ?? '';
        if (body.isEmpty) continue;

        _handler!(Envelope(
          id: e['event_id'] as String,
          channelType: 'matrix',
          senderId: e['sender'] as String,
          groupId: roomId,
          content: body,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (e['origin_server_ts'] as int?) ?? 0),
          metadata: {'roomId': roomId},
        ));
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _isRunning = false;
    _log.info('Matrix channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning) throw Exception('Matrix channel not connected');

    final roomId = groupId ?? peerId;
    final txnId = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse(
      '$homeserverUrl/_matrix/client/v3/rooms/$roomId/send/m.room.message/$txnId',
    );

    final resp = await http.put(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'msgtype': 'm.text', 'body': content}),
    );

    if (resp.statusCode != 200) {
      _log.severe('Matrix sendMessage failed: ${resp.body}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
