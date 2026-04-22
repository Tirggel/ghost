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
import '../infra/env.dart';
import '../sessions/manager.dart';
import 'channel.dart';
import 'envelope.dart';
import 'telegram.dart';
import 'discord.dart';
import 'slack.dart';
import 'whatsapp.dart';
import 'google_chat.dart';
import 'matrix.dart';

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
  final Set<String> _updatingChannels = {};

  /// Initialize all enabled channels from the config.
  Future<void> initialize() async {
    _log.info('Initializing channels...');
    final channels = agentManager.config.channels;

    // Start each supported channel if enabled
    await updateChannel('telegram', channels.telegram.enabled,
        settings: channels.telegram.settings);
    await updateChannel('discord', channels.discord.enabled,
        settings: channels.discord.settings);
    await updateChannel('slack', channels.slack.enabled,
        settings: channels.slack.settings);
    await updateChannel('whatsapp', channels.whatsapp.enabled,
        settings: channels.whatsapp.settings);
    await updateChannel('googleChat', channels.googleChat.enabled,
        settings: channels.googleChat.settings);
    await updateChannel('matrix', channels.matrix.enabled,
        settings: channels.matrix.settings);
    
    // Webchat is internal and usually handled by the UI connecting to gateway,
    // but if it has any background logic, it would go here.
  }

  Map<String, String> get connectionErrors =>
      Map.unmodifiable(_connectionErrors);

  void clearConnectionErrors([String? channelType]) {
    if (channelType != null) {
      _connectionErrors.remove(channelType);
    } else {
      _connectionErrors.clear();
    }
  }

  /// Update or start a channel generic handler.
  Future<void> updateChannel(String type, bool enabled,
      {Map<String, dynamic>? settings}) async {
    if (!enabled) {
      if (_channels.containsKey(type)) {
        _log.info('Channel $type disabled, removing...');
        await removeChannel(type);
      }
      return;
    }

    final storageKey =
        type == 'telegram' ? 'telegram_bot_token' : '${type}_token';
    final token = await storage.get(storageKey);

    if (token == null || token.isEmpty) {
      if (_channels.containsKey(type)) {
        _log.warning('Channel $type: Token cleared in vault, disconnecting.');
        await removeChannel(type);
      }
      return;
    }

    if (_updatingChannels.contains(type)) return;
    _updatingChannels.add(type);

    try {
      // Check if instance is already running
      if (_channels.containsKey(type)) {
        _log.info(
            'Channel $type is already running. Disconnecting before re-connecting...');
        await removeChannel(type);

        // Telegram is particularly sensitive to "409 Conflict" (multiple instances).
        // It needs more time for the server to recognize the old connection as closed.
        final delayMs = type == 'telegram' ? 2000 : 800;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }

      Channel? channel;
      final s = settings ?? {};

      switch (type) {
        case 'telegram':
          channel = TelegramChannel(
            token: token,
            botName: s['botName'] as String? ?? 'GhostBot',
          );
          break;
        case 'discord':
          channel = DiscordChannel(
            botToken: token,
            botName: s['botName'] as String? ?? 'Ghost',
          );
          break;
        case 'slack':
          channel = SlackChannel(
            botToken: token,
            signingSecret: s['signingSecret'] as String?,
            botName: s['botName'] as String? ?? 'Ghost',
          );
          break;
        case 'whatsapp':
          channel = WhatsAppChannel(
            apiToken: token,
            phoneNumberId: s['phoneNumberId'] as String? ?? '',
            verifyToken: s['verifyToken'] as String? ?? 'ghost_verify',
          );
          break;
        case 'googleChat':
          channel = GoogleChatChannel(
            serviceAccountJsonPath: token,
            projectId: s['projectId'] as String? ?? '',
            subscriptionId: s['subscriptionId'] as String? ?? '',
          );
          break;
        case 'matrix':
          channel = MatrixChannel(
            accessToken: token,
            homeserverUrl: s['homeserverUrl'] as String? ?? 'https://matrix.org',
            userId: s['userId'] as String? ?? '',
          );
          break;
        case 'signal':
        case 'webchat':
        case 'imessage':
        case 'msTeams':
        case 'nextcloudTalk':
        case 'tlon':
        case 'zalo':
          _log.warning('Channel type $type placeholder in manager');
          break;
        default:
          _log.warning('Channel type $type update not fully implemented yet');
      }

      if (channel != null) {
        await addChannel(channel);
        _log.info('Channel $type updated/started');
      }
    } finally {
      _updatingChannels.remove(type);
    }
  }

  /// Update or start the Telegram channel.
  Future<void> updateTelegram(String botName, {String? token}) async {
    // Forward to generic update
    await updateChannel('telegram', true, settings: {'botName': botName});
  }

  /// Add and start a channel.
  Future<void> addChannel(Channel channel) async {
    _channels[channel.type] = channel;

    channel.onMessage((envelope) {
      unawaited(_handleIncomingMessage(channel, envelope));
    });

    channel.onError((message) {
      _log.severe('Terminal error from channel ${channel.displayName}: $message');
      _connectionErrors[channel.type] = message;
      unawaited(removeChannel(channel.type));
      gateway?.broadcast('gateway.error', {
        'message': message,
        'channelType': channel.type,
      });
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
    _log.info('Incoming message from ${channel.type} user id:${envelope.senderId} content: ${envelope.content}');

    // 0. Check DmPolicy
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
      case 'imessage':
        cConfig = channelsConfig.imessage;
        break;
      case 'msTeams':
        cConfig = channelsConfig.msTeams;
        break;
      case 'nextcloudTalk':
        cConfig = channelsConfig.nextcloudTalk;
        break;
      case 'matrix':
        cConfig = channelsConfig.matrix;
        break;
      case 'tlon':
        cConfig = channelsConfig.tlon;
        break;
      case 'zalo':
        cConfig = channelsConfig.zalo;
        break;
    }

    if (cConfig == null || cConfig.dmPolicy == DmPolicy.disabled) {
      final logMsg =
          'Message ignored: Channel disabled or no config for ${channel.type}';
      _log.info(logMsg);

      if (cConfig?.dmPolicy == DmPolicy.disabled) {
        await channel.sendMessage(
          peerId: envelope.senderId,
          groupId: envelope.groupId,
          content: _tr('message_ignored', args: {'channel': channel.type}),
        );
      }
      return;
    }

    if (cConfig.dmPolicy == DmPolicy.allowlist) {
      if (!cConfig.allowFrom.contains(envelope.senderId)) {
        _log.warning(
            'Message ignored: User ${envelope.senderId} not in allowlist for ${channel.type}');
        await channel.sendMessage(
          peerId: envelope.senderId,
          groupId: envelope.groupId,
          content: _tr('access_denied', args: {'id': envelope.senderId}),
        );
        return;
      }
    }

    if (cConfig.dmPolicy == DmPolicy.pairing) {
      if (!cConfig.allowFrom.contains(envelope.senderId)) {
        final expectedCode = cConfig.settings['pairingCode'] as String?;
        if (expectedCode != null && expectedCode.isNotEmpty) {
          if (envelope.content.trim() == expectedCode) {
            // Pairing success! Add senderId to allowFrom.
            final updatedAllowFrom = List<String>.from(cConfig.allowFrom)
              ..add(envelope.senderId);

            final updatedConfig = cConfig.copyWith(allowFrom: updatedAllowFrom);

            // Update only the specific channel that matched
            final newChannels = channelsConfig.copyWith(
              telegram: channel.type == 'telegram' ? updatedConfig : null,
              discord: channel.type == 'discord' ? updatedConfig : null,
              whatsapp: channel.type == 'whatsapp' ? updatedConfig : null,
              slack: channel.type == 'slack' ? updatedConfig : null,
              signal: channel.type == 'signal' ? updatedConfig : null,
              webchat: channel.type == 'webchat' ? updatedConfig : null,
              imessage: channel.type == 'imessage' ? updatedConfig : null,
              msTeams: channel.type == 'msTeams' ? updatedConfig : null,
              nextcloudTalk:
                  channel.type == 'nextcloudTalk' ? updatedConfig : null,
              matrix: channel.type == 'matrix' ? updatedConfig : null,
              tlon: channel.type == 'tlon' ? updatedConfig : null,
              zalo: channel.type == 'zalo' ? updatedConfig : null,
              googleChat: channel.type == 'googleChat' ? updatedConfig : null,
            );

            await agentManager.updateConfig(
                agentManager.config.copyWith(channels: newChannels));

            if (configPath != null) {
              await saveConfig(agentManager.config, configPath!);
            }

            _log.info(
                'Pairing success for ${channel.type} sender: ${envelope.senderId}');

            await channel.sendMessage(
              peerId: envelope.senderId,
              groupId: envelope.groupId,
              content: _tr('auth_verified'),
            );
            return;
          } else {
            // Wait for proper pairing code
            await channel.sendMessage(
              peerId: envelope.senderId,
              groupId: envelope.groupId,
              content: _tr('auth_required', args: {'id': envelope.senderId}),
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

    // Set title for Telegram sessions
    if (envelope.channelType == 'telegram') {
      final agentName = agentManager.config.identity.name;
      final expectedTitle = '$agentName und Telegram';
      if (session.title != expectedTitle) {
        session.title = expectedTitle;
        // Persist via system message
        await sessionManager.addMessage(
          sessionId: session.id,
          role: 'system',
          content: 'session_rename',
          metadata: {'title': expectedTitle},
        );
        // Broadcast update to UI
        gateway?.broadcast('agent.session_updated', {
          'sessionId': session.id,
          'title': expectedTitle,
        });
      }
    }

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
          final ttsScript = p.join(Env.scriptsDir, 'tts.py');
          _log.info('Using TTS script: $ttsScript');

          if (!await File(ttsScript).exists()) {
            _log.severe('TTS script NOT FOUND at: $ttsScript');
            return;
          }

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

  String _tr(String key, {Map<String, String>? args}) {
    final language = agentManager.config.user.language;

    final enStrings = {
      'message_ignored':
          'Message ignored: Channel disabled or no config for {channel}',
      'access_denied':
          '🔒 Access denied. Your ID: `{id}` is not on the allowlist.',
      'auth_verified':
          '✅ Authenticator verified. You may now chat with the agent.',
      'auth_required':
          '🔒 Authentication required. Please enter your pairing code.\n(Your ID: `{id}`)'
    };

    final deStrings = {
      'message_ignored':
          'Nachricht ignoriert: Kanal deaktiviert oder keine Konfiguration für {channel}',
      'access_denied':
          '🔒 Zugriff verweigert. Ihre ID: `{id}` steht nicht auf der Erlaubnisliste.',
      'auth_verified':
          '✅ Authentifizierung erfolgreich. Sie können nun mit dem Agenten sprechen.',
      'auth_required':
          '🔒 Authentifizierung erforderlich. Bitte geben Sie Ihren Koppelungscode ein.\n(Ihre ID: `{id}`)'
    };

    final strings = (language == 'de') ? deStrings : enStrings;
    var message = strings[key] ?? key;

    if (args != null) {
      for (final entry in args.entries) {
        message = message.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return message;
  }

  /// Shutdown all channels.
  Future<void> shutdown() async {
    final types = _channels.keys.toList();
    for (final type in types) {
      await removeChannel(type);
    }
    _log.info('Channel manager shutdown complete');
  }
}
