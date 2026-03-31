// Ghost — Discord Channel implementation.
// Uses the 'nyxx' package (already in pubspec.yaml).

import 'dart:async';
import 'package:logging/logging.dart';
import 'package:nyxx/nyxx.dart' hide Channel;

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.DiscordChannel');

/// Integration with Discord via a Bot Token using the nyxx library.
class DiscordChannel extends Channel {
  DiscordChannel({
    required this.botToken,
    this.botName = 'Ghost',
  });

  final String botToken;
  final String botName;

  NyxxGateway? _client;
  StreamSubscription<MessageCreateEvent>? _subscription;
  void Function(Envelope envelope)? _handler;

  @override
  String get type => 'discord';

  @override
  String get displayName => 'Discord ($botName)';

  @override
  bool get isConnected => _client != null;

  @override
  Future<void> connect() async {
    if (isConnected) return;

    _client = await Nyxx.connectGateway(
      botToken,
      GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
    );

    _subscription = _client!.onMessageCreate.listen((event) {
      final message = event.message;

      // Ignore the bot's own messages
      if (message.author.id == _client!.user.id) return;
      if (message.content.isEmpty) return;
      if (_handler == null) return;

      final isGroupMessage = message.channelId != message.author.id;

      final envelope = Envelope(
        id: message.id.toString(),
        channelType: 'discord',
        senderId: message.author.id.toString(),
        groupId: isGroupMessage ? message.channelId.toString() : null,
        content: message.content,
        timestamp: message.timestamp,
        metadata: {
          'username': message.author.username,
          'channelId': message.channelId.toString(),
        },
      );
      _handler!(envelope);
    });

    _log.info('Discord bot connected: $botName');
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _client?.close();
    _client = null;
    _subscription = null;
    _log.info('Discord bot disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!isConnected) throw Exception('Discord channel not connected');

    final targetId = groupId ?? peerId;
    final channelId = Snowflake.parse(targetId);

    // Fetch the channel and send the message
    final channel = await _client!.channels.get(channelId);
    if (channel is GuildTextChannel) {
      await channel.sendMessage(MessageBuilder(content: content));
    } else if (channel is DmChannel) {
      await channel.sendMessage(MessageBuilder(content: content));
    } else {
      _log.warning('Discord: Cannot send to channel type ${channel.runtimeType}');
    }
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
