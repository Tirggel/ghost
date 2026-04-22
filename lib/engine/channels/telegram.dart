// Ghost — Telegram Channel implementation.

import 'dart:async';
import 'package:teledart/teledart.dart';
import 'package:teledart/telegram.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import '../channels/channel.dart';
import '../channels/envelope.dart';
import '../infra/env.dart';

final _log = Logger('Ghost.TelegramChannel');

/// Integration with Telegram via teledart.
class TelegramChannel extends Channel {
  TelegramChannel({
    required this.token,
    required this.botName,
  });

  final String token;
  final String botName;

  TeleDart? _teledart;
  StreamSubscription<dynamic>? _subscription;
  void Function(Envelope envelope)? _handler;
  void Function(String message)? _errorHandler;

  @override
  String get type => 'telegram';
  @override
  String get displayName => 'Telegram (@$botName)';
  @override
  bool get isConnected => _teledart != null;

  /// Test if a token is valid by calling getMe().
  static Future<bool> testToken(String token) async {
    try {
      final telegram = Telegram(token);
      await telegram.getMe();
      return true;
    } catch (e) {
      _log.warning('Telegram token validation failed: $e');
      return false;
    }
  }

  @override
  Future<void> connect() async {
    _log.info('Connecting to Telegram...');
    await _connectWithRetry();
  }

  Future<void> _connectWithRetry([int attempt = 1]) async {
    try {
      if (_teledart != null) {
        await disconnect();
      }

      final user = await Telegram(token).getMe();
      _teledart = TeleDart(token, Event(user.username!));

      // Use runZonedGuarded to catch unhandled async errors from teledart's polling loop
      runZonedGuarded(() {
        _teledart!.start();
      }, (Object error, StackTrace stack) {
        final errorStr = error.toString();
        if (errorStr.contains('409') || errorStr.contains('Conflict')) {
          _log.warning(
              'Telegram background 409 Conflict caught for @${user.username}.');
          if (attempt < 3) {
            _log.info(
                'Attempting automatic reconnect in 4 seconds (Attempt $attempt/3)...');
            Future<void>.delayed(
                const Duration(seconds: 4), () => _connectWithRetry(attempt + 1));
          } else {
            _log.severe(
                'Telegram 409 Conflict persisted after 3 attempts. Terminating channel instance...');
            disconnect();
            _errorHandler?.call(
                'Telegram 409 Conflict: Mehrere Bot-Instanzen laufen mit demselben Token. Diese Instanz wurde getrennt.');
          }
        } else {
          _log.severe('Telegram background error: $error', error, stack);
        }
      });

      _subscription = _teledart!.onMessage().listen((msg) {
        if (_handler != null && (msg.text != null || msg.voice != null)) {
          if (msg.voice != null) {
            _handleVoiceMessage(msg);
          } else {
            final envelope = Envelope(
              id: msg.messageId.toString(),
              channelType: 'telegram',
              senderId: msg.from!.id.toString(),
              groupId:
                  msg.chat.id != msg.from!.id ? msg.chat.id.toString() : null,
              content: msg.text!,
              timestamp: DateTime.fromMillisecondsSinceEpoch(msg.date * 1000),
              metadata: {
                'username': msg.from!.username,
                'firstName': msg.from!.firstName,
                'chatTitle': msg.chat.title,
              },
            );
            _handler!(envelope);
          }
        }
      });

      _log.info('Telegram bot @${user.username} connected');
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('409') || errorStr.contains('Conflict')) {
        if (attempt < 3) {
          _log.warning(
              'Telegram 409 Conflict during connection. Retrying in 4s (Attempt $attempt/3)...');
          await Future<void>.delayed(const Duration(seconds: 4));
          return _connectWithRetry(attempt + 1);
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    
    if (_teledart != null) {
      _teledart!.stop();
      _teledart = null;
      // Give the HTTP client a moment to release long-polling connections
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _log.info('Telegram bot disconnected');
  }

  Future<void> _handleVoiceMessage(dynamic msg) async {
    try {
      final String fileId = msg.voice!.fileId as String;
      final fileInfo = await _teledart!.getFile(fileId);
      final fileUrl =
          'https://api.telegram.org/file/bot$token/${fileInfo.filePath}';

      final tempDir = Directory.systemTemp;
      final tempFile =
          File(p.join(tempDir.path, 'tg_voice_${msg.messageId}.ogg'));

      final request = await HttpClient().getUrl(Uri.parse(fileUrl));
      final response = await request.close();
      await response.pipe(tempFile.openWrite());

      if (_teledart == null) return;

      _log.info('Transcribing voice message (ID: ${msg.messageId})...');
      
      final sttScript = p.join(Env.scriptsDir, 'stt.py');
      _log.info('Using STT script: $sttScript');

      if (!await File(sttScript).exists()) {
        _log.severe('STT script NOT FOUND at: $sttScript');
        await _teledart!.sendMessage(msg.chat.id,
            '❌ Sprachnachricht-Fehler: STT-Skript wurde nicht gefunden.');
        return;
      }

      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        [sttScript, tempFile.path],
      );

      if (result.exitCode != 0) {
        _log.severe('STT script failed: ${result.stderr}');
        return;
      }

      final transcription = result.stdout.toString().trim();
      _log.info('Transcription result: $transcription');

      if (transcription.isNotEmpty) {
        final envelope = Envelope(
          id: msg.messageId.toString(),
          channelType: 'telegram',
          senderId: msg.from!.id.toString(),
          groupId: msg.chat.id != msg.from!.id ? msg.chat.id.toString() : null,
          content: transcription,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch((msg.date as int) * 1000),
          metadata: {
            'username': msg.from!.username,
            'firstName': msg.from!.firstName,
            'chatTitle': msg.chat.title,
            'isVoice': true,
          },
        );
        _handler!(envelope);
      }

      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e, st) {
      _log.severe('Error processing Telegram voice message: $e', e, st);
    }
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!isConnected) throw Exception('Telegram channel not connected');

    final dynamic chatId =
        groupId != null ? int.parse(groupId) : int.parse(peerId);

    if (media != null && media.isNotEmpty) {
      // Basic media handling for Telegram
      for (final item in media) {
        if (item.type == MediaType.image) {
          await _teledart?.sendPhoto(chatId, item.url,
              caption: item.caption ?? content);
          return;
        } else if (item.type == MediaType.audio) {
          await _teledart?.sendVoice(chatId, File(item.url),
              caption: item.caption ?? (content.isEmpty ? null : content));
          return;
        }
      }
    }

    await _teledart?.sendMessage(chatId, content);
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }

  @override
  void onError(void Function(String message) handler) {
    _errorHandler = handler;
  }
}
