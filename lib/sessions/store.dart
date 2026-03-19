// Ghost — JSONL transcript store for sessions.

import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:logging/logging.dart';

import '../models/message.dart';

final _log = Logger('Ghost.SessionStore');

/// Stores session transcripts in an encrypted Hive CE box.
///
/// Uses AES-256 for encryption at rest.
class SessionStore {
  SessionStore({required this.encryptionKey});

  /// The 32-byte encryption key for the Hive box.
  final Uint8List encryptionKey;

  static const _boxName = 'data-tressor';
  bool _initialized = false;
  late Box<String> _box;

  Future<void> _ensureOpen() async {
    if (_initialized) return;
    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    _initialized = true;
  }

  /// Append a message to a session's transcript.
  Future<void> appendMessage(String sessionId, Message message) async {
    await _ensureOpen();

    final jsonStr = _box.get(sessionId);
    final List<dynamic> history =
        jsonStr != null ? jsonDecode(jsonStr) as List<dynamic> : [];

    history.add(message.toJson());
    await _box.put(sessionId, jsonEncode(history));

    _log.fine('Appended message to session $sessionId');
  }

  /// Load all messages for a session.
  Future<List<Message>> loadTranscript(String sessionId) async {
    await _ensureOpen();

    final jsonStr = _box.get(sessionId);
    if (jsonStr == null) return [];

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final messages =
          list.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
      _log.fine('Loaded ${messages.length} messages for session $sessionId');
      return messages;
    } catch (e) {
      _log.warning('Failed to parse session $sessionId: $e');
      return [];
    }
  }

  /// Load the last N messages for a session.
  Future<List<Message>> loadLastMessages(String sessionId, int count) async {
    final all = await loadTranscript(sessionId);
    if (count >= all.length) return all;
    return all.sublist(all.length - count);
  }

  /// Check if a session transcript exists.
  Future<bool> exists(String sessionId) async {
    await _ensureOpen();
    return _box.containsKey(sessionId);
  }

  /// Delete a session transcript.
  Future<void> deleteTranscript(String sessionId) async {
    await _ensureOpen();
    if (_box.containsKey(sessionId)) {
      await _box.delete(sessionId);
      _log.info('Deleted transcript for session $sessionId');
    }
  }

  /// List all session IDs that have transcripts.
  Future<List<String>> listSessionIds() async {
    await _ensureOpen();
    return _box.keys.map((k) => k.toString()).toList();
  }
}
