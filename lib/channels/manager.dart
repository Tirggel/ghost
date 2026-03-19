// Ghost — Channel Manager.

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../agent/manager.dart';
import '../config/config.dart';
import '../config/io.dart';
import '../config/secure_storage.dart';
import '../gateway/server.dart';
import '../sessions/manager.dart';
import 'channel.dart';
import 'envelope.dart';
import 'telegram.dart';

final _log = Logger('Ghost.ChannelManager');

/// Coordinates multiple messaging channels and routes their input to the Agent.
class ChannelManager {
  ChannelManager({
    required this.agentManager,
    required this.sessionManager,
    required this.storage,
    this.configPath,
    this.gateway,
  });

  final AgentManager agentManager;
  final SessionManager sessionManager;
  final SecureStorage storage;
  final String? configPath;
  final GatewayServer? gateway;
  final Map<String, Channel> _channels = {};
  final Map<String, String> _connectionErrors = {};

  Map<String, String> get connectionErrors =>
      Map.unmodifiable(_connectionErrors);

  void clearConnectionErrors([String? channelType]) {
    if (channelType != null) {
      _connectionErrors.remove(channelType);
    } else {
      _connectionErrors.clear();
    }
  }

  /// Update or start the Telegram channel.
  Future<void> updateTelegram(String botName, {String? token}) async {
    final effectiveToken = token ?? await storage.get('telegram_bot_token');
    if (effectiveToken == null || effectiveToken.isEmpty) {
      _log.warning('Attempted to start Telegram without token');
      return;
    }

    await removeChannel('telegram');
    await addChannel(TelegramChannel(
      token: effectiveToken,
      botName: botName,
    ));
    _log.info('Telegram channel updated/started for $botName');
  }

  /// Add and start a channel.
  Future<void> addChannel(Channel channel) async {
    _channels[channel.type] = channel;

    channel.onMessage((envelope) {
      unawaited(_handleIncomingMessage(channel, envelope));
    });

    _connectionErrors.remove(channel.type);
    try {
      await channel.connect();
      _log.info('Channel added: ${channel.displayName}');
    } catch (e, st) {
      _log.severe(
          'Failed to connect channel ${channel.displayName}: $e', e, st);
      _channels.remove(channel.type);

      final errorMsg = 'Failed to connect ${channel.displayName}:\n$e';
      _connectionErrors[channel.type] = errorMsg;

      gateway?.broadcast('gateway.error', {
        'message': errorMsg,
        'channelType': channel.type,
      });
    }
  }

  /// Remove and stop a channel.
  Future<void> removeChannel(String type) async {
    final channel = _channels.remove(type);
    await channel?.disconnect();
  }

  /// Get status of all channels.
  List<Map<String, dynamic>> getStatus() {
    return _channels.values.map((c) => c.getStatus()).toList();
  }

  Future<void> _handleIncomingMessage(
      Channel channel, Envelope envelope) async {
    _log.info('Incoming message from ${channel.type}:${envelope.senderId}');

    // 0. Check DmPolicy (Pairing)
    final channelsConfig = agentManager.config.channels;
    ChannelConfig? cConfig;
    switch (channel.type) {
      case 'telegram':
        cConfig = channelsConfig.telegram;
        break;
      case 'googleChat':
        cConfig = channelsConfig.googleChat;
        break;
      case 'discord':
        cConfig = channelsConfig.discord;
        break;
      case 'whatsapp':
        cConfig = channelsConfig.whatsapp;
        break;
      case 'slack':
        cConfig = channelsConfig.slack;
        break;
      case 'signal':
        cConfig = channelsConfig.signal;
        break;
      case 'webchat':
        cConfig = channelsConfig.webchat;
        break;
    }

    if (cConfig != null && cConfig.dmPolicy == DmPolicy.pairing) {
      if (!cConfig.allowFrom.contains(envelope.senderId)) {
        final expectedCode = cConfig.settings['pairingCode'] as String?;
        if (expectedCode != null && expectedCode.isNotEmpty) {
          if (envelope.content.trim() == expectedCode) {
            // Pairing success! Add senderId to allowFrom.
            final updatedAllowFrom = List<String>.from(cConfig.allowFrom)
              ..add(envelope.senderId);

            // Note: In a fully persistent setup, we should save this new config to disk.
            // For now, we update it in memory via agentManager so they can chat until restart.
            // To persist across restarts, the user will see they are paired but may need to re-pair
            // if we don't save to disk here.

            final updatedConfig = cConfig.copyWith(allowFrom: updatedAllowFrom);

            ChannelsConfig newChannels;
            switch (channel.type) {
              case 'telegram':
                newChannels = channelsConfig.copyWith(telegram: updatedConfig);
                break;
              case 'googleChat':
                newChannels =
                    channelsConfig.copyWith(googleChat: updatedConfig);
                break;
              case 'discord':
                newChannels = channelsConfig.copyWith(discord: updatedConfig);
                break;
              case 'whatsapp':
                newChannels = channelsConfig.copyWith(whatsapp: updatedConfig);
                break;
              case 'slack':
                newChannels = channelsConfig.copyWith(slack: updatedConfig);
                break;
              case 'signal':
                newChannels = channelsConfig.copyWith(signal: updatedConfig);
                break;
              case 'webchat':
                newChannels = channelsConfig.copyWith(webchat: updatedConfig);
                break;
              default:
                newChannels = channelsConfig;
            }
            agentManager.config =
                agentManager.config.copyWith(channels: newChannels);

            if (configPath != null) {
              await saveConfig(agentManager.config, configPath!);
            }

            // Notify user and continue to process the message? Or just notify?
            // Let's notify and then DROP the pairing code message so the LLM doesn't see it.
            await channel.sendMessage(
              peerId: envelope.senderId,
              groupId: envelope.groupId,
              content:
                  '✅ Authenticator verified. You may now chat with the agent.',
            );
            return;
          } else {
            // Wait for proper pairing code
            await channel.sendMessage(
              peerId: envelope.senderId,
              groupId: envelope.groupId,
              content:
                  '🔒 Authentication required. Please enter your pairing code.',
            );
            return;
          }
        }
      }
    }

    // 1. Resolve/Create Session
    final session = await sessionManager.resolveSession(
      channelType: envelope.channelType,
      peerId: envelope.senderId,
      groupId: envelope.groupId,
    );

    // 2. Add user message to session
    await sessionManager.addMessage(
      sessionId: session.id,
      role: 'user',
      content: envelope.content,
      metadata: {
        ...envelope.metadata,
        'channelType': envelope.channelType,
        'senderId': envelope.senderId,
        if (envelope.groupId != null) 'groupId': envelope.groupId,
      },
    );

    // 3. Process with Agent
    try {
      final agent = agentManager.defaultAgent;
      session.agentName = agentManager.config.identity.name;
      await agent.processMessage(
        sessionId: session.id,
        content: envelope.content,
        onPartialResponse: (chunk) {
          gateway?.broadcast('agent.stream', {
            'sessionId': session.id,
            'chunk': chunk,
          });
        },
      );

      // 4. Get Agent's response from history and send back
      final history = await sessionManager.getHistory(session.id);
      if (history.isNotEmpty && history.last.role == 'assistant') {
        final lastMsg = history.last;

        gateway?.broadcast('agent.response', {
          'sessionId': session.id,
          'message': lastMsg.toJson(),
        });

        if (envelope.metadata['isVoice'] == true) {
          await channel.sendMessage(
            peerId: envelope.senderId,
            groupId: envelope.groupId,
            content: lastMsg.content,
          );

          _log.info('Synthesizing voice response...');
          final scriptDir = p.dirname(p.dirname(Platform.script.toFilePath()));
          final ttsScript = p.join(scriptDir, 'scripts', 'tts.py');

          final tempDir = Directory.systemTemp;
          final audioFile = p.join(
              tempDir.path, 'tg_voice_response_${const Uuid().v4()}.ogg');

          final result = await Process.run(
            Platform.isWindows ? 'python' : 'python3',
            [ttsScript, lastMsg.content, audioFile],
          );

          if (result.exitCode == 0 && await File(audioFile).exists()) {
            await channel.sendMessage(
              peerId: envelope.senderId,
              groupId: envelope.groupId,
              content: '',
              media: [MediaAttachment(type: MediaType.audio, url: audioFile)],
            );

            await File(audioFile).delete();
            return;
          } else {
            _log.severe('TTS failed: ${result.stderr}');
            return;
          }
        }

        await channel.sendMessage(
          peerId: envelope.senderId,
          groupId: envelope.groupId,
          content: lastMsg.content,
        );
      }
    } catch (e) {
      _log.severe('Error processing message from ${channel.type}: $e');
      await channel.sendMessage(
        peerId: envelope.senderId,
        groupId: envelope.groupId,
        content: 'Sorry, I encountered an error: $e',
      );
    }
  }
}
