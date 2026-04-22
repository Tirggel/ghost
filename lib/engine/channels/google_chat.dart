// Ghost — Google Chat Channel implementation (via Pub/Sub).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/chat/v1.dart' as chat;
import 'package:googleapis/pubsub/v1.dart' as pubsub;
import 'package:googleapis_auth/auth_io.dart';
import 'package:logging/logging.dart';

import '../channels/channel.dart';
import '../channels/envelope.dart';

final _log = Logger('Ghost.GoogleChatChannel');

/// Integration with Google Chat via Cloud Pub/Sub.
/// Requires a Service Account JSON file.
class GoogleChatChannel extends Channel {
  GoogleChatChannel({
    required this.serviceAccountJsonPath,
    required this.projectId,
    required this.subscriptionId,
  });

  /// Path to the Service Account JSON file.
  final String serviceAccountJsonPath;

  /// Google Cloud Project ID.
  final String projectId;

  /// Pub/Sub Subscription ID.
  final String subscriptionId;

  pubsub.PubsubApi? _pubsubApi;
  chat.HangoutsChatApi? _chatApi;
  AuthClient? _client;
  Timer? _pullTimer;
  void Function(Envelope envelope)? _handler;
  bool _isConnected = false;

  @override
  String get type => 'googleChat';

  @override
  String get displayName => 'Google Chat (Pub/Sub: $subscriptionId)';

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (isConnected) return;

    if (serviceAccountJsonPath.isEmpty) {
      _log.warning(
          'Google Chat: serviceAccountJsonPath is empty. Cannot connect.');
      return;
    }

    final file = File(serviceAccountJsonPath);
    if (!await file.exists()) {
      _log.warning(
          'Google Chat: Service Account JSON file not found at $serviceAccountJsonPath');
      return;
    }

    try {
      final jsonStr = await file.readAsString();
      final credentials = ServiceAccountCredentials.fromJson(jsonStr);
      final scopes = [
        pubsub.PubsubApi.pubsubScope,
        chat.HangoutsChatApi.chatBotScope,
      ];
      _client = await clientViaServiceAccount(credentials, scopes);

      _pubsubApi = pubsub.PubsubApi(_client!);
      _chatApi = chat.HangoutsChatApi(_client!);

      _isConnected = true;
      _log.info(
          'Google Chat connected to Pub/Sub subscription: $subscriptionId');

      // Start pulling messages periodically
      _startPulling();
    } catch (e) {
      _log.severe('Failed to connect to Google Chat: $e');
      _isConnected = false;
    }
  }

  void _startPulling() {
    // Pull every 2 seconds
    _pullTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _pullMessages();
    });
  }

  Future<void> _pullMessages() async {
    if (!_isConnected || _pubsubApi == null) return;

    final subscriptionName =
        'projects/$projectId/subscriptions/$subscriptionId';
    try {
      final request =
          pubsub.PullRequest(maxMessages: 10, returnImmediately: true);
      final response = await _pubsubApi!.projects.subscriptions
          .pull(request, subscriptionName);

      if (response.receivedMessages != null &&
          response.receivedMessages!.isNotEmpty) {
        final ackIds = <String>[];

        for (final msg in response.receivedMessages!) {
          if (msg.message?.data != null) {
            ackIds.add(msg.ackId!);
            final payload = utf8.decode(base64Decode(msg.message!.data!));
            _processPayload(payload);
          }
        }

        if (ackIds.isNotEmpty) {
          final ackReq = pubsub.AcknowledgeRequest(ackIds: ackIds);
          await _pubsubApi!.projects.subscriptions
              .acknowledge(ackReq, subscriptionName);
        }
      }
    } catch (e) {
      _log.warning('Google Chat Pub/Sub pull error: $e');
    }
  }

  void _processPayload(String payloadStr) {
    if (_handler == null) return;

    try {
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final type = payload['type'];

      if (type == 'MESSAGE') {
        final message = payload['message'] as Map<String, dynamic>?;
        if (message == null) return;

        final text = message['argumentText'] ?? message['text'] ?? '';
        if (text.toString().trim().isEmpty) return;

        final space = payload['space'] as Map<String, dynamic>?;
        final user = payload['user'] as Map<String, dynamic>?;

        final spaceName = space?['name'] as String?;
        final userName = user?['name'] as String?; // format: users/XXX

        if (spaceName != null && userName != null && text != null) {
          final envelope = Envelope(
            id: message['name'] as String? ??
                DateTime.now().millisecondsSinceEpoch.toString(),
            channelType: 'googleChat',
            senderId: userName,
            groupId: spaceName, // use space ID as group ID
            content: text.toString().trim(),
            timestamp: DateTime.now(),
            metadata: {
              'displayName': user?['displayName'],
              'spaceType': space?['type'],
            },
          );
          _handler!(envelope);
        }
      } else if (type == 'ADDED_TO_SPACE') {
        _log.info(
            'Google Chat: Bot added to space ${payload['space']?['name']}');
      }
    } catch (e) {
      _log.warning('Google Chat failed to process payload: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _pullTimer?.cancel();
    _pullTimer = null;
    _client?.close();
    _client = null;
    _pubsubApi = null;
    _chatApi = null;
    _isConnected = false;
    _log.info('Google Chat channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isConnected || _chatApi == null) {
      throw Exception('Google Chat channel not connected');
    }

    final spaceName =
        groupId ?? 'spaces/$peerId'; // Wait, Google Chat needs a space name

    final message = chat.Message()..text = content;

    try {
      await _chatApi!.spaces.messages.create(message, spaceName);
    } catch (e) {
      _log.severe('Google Chat sendMessage error: $e');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
