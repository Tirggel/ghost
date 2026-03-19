// Ghost — Session manager.

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import 'session.dart';
import 'store.dart';

final _log = Logger('Ghost.SessionManager');

const _uuid = Uuid();

/// Manages sessions: creation, lookup, and message routing.
class SessionManager {
  SessionManager({
    required this.store,
    this.defaultAgentId = 'default',
    this.maxHistory = 100,
  });

  final SessionStore store;
  final String defaultAgentId;
  final int maxHistory;

  /// In-memory session cache.
  final Map<String, Session> _sessions = {};

  /// Load all existing sessions from disk into memory.
  Future<void> loadAll() async {
    final sessionIds = await store.listSessionIds();
    for (final id in sessionIds) {
      try {
        final messages = await store.loadTranscript(id);
        if (messages.isNotEmpty) {
          final firstMsg = messages.first;
          final meta = firstMsg.metadata;

          final channelType = meta['channelType'] as String? ?? 'gateway';
          final peerId = meta['senderId'] as String? ?? 'unknown';
          final groupId = meta['groupId'] as String?;

          String? sessionModel;
          String? sessionProvider;
          String? sessionAgentId;
          String? sessionAgentName;
          String? sessionTitle;
          for (final m in messages) {
            if (m.metadata.containsKey('agentId')) {
              sessionAgentId = m.metadata['agentId'] as String?;
            }
            if (m.metadata.containsKey('agentName')) {
              sessionAgentName = m.metadata['agentName'] as String?;
            }
            if (m.metadata.containsKey('model')) {
              sessionModel = m.metadata['model'] as String?;
            }
            if (m.metadata.containsKey('provider')) {
              sessionProvider = m.metadata['provider'] as String?;
            }
            if (m.metadata.containsKey('title')) {
              sessionTitle = m.metadata['title'] as String?;
            }
          }

          final session = Session(
            id: id,
            agentId: sessionAgentId ?? defaultAgentId,
            agentName: sessionAgentName,
            channelType: channelType,
            peerId: peerId,
            groupId: groupId,
            model: sessionModel,
            provider: sessionProvider,
            title: sessionTitle,
            type: groupId != null ? SessionType.group : SessionType.main,
            history: messages,
          );

          final key = groupId != null
              ? '$channelType:$groupId'
              : '$channelType:$peerId';
          _sessions[key] = session;
          _log.fine('Loaded session $id from disk');
        }
      } catch (e) {
        _log.warning('Failed to load session $id: $e');
      }
    }
  }

  /// Create a specific session (e.g. for a new chat in the UI).
  Session createSession({
    required String id,
    required String channelType,
    required String peerId,
    String? groupId,
  }) {
    final session = Session(
      id: id,
      agentId: defaultAgentId,
      channelType: channelType,
      peerId: peerId,
      groupId: groupId,
      type: groupId != null ? SessionType.group : SessionType.main,
    );
    _sessions[id] = session;
    _log.info('Created specific session $id for $channelType:$peerId');
    return session;
  }

  /// Resolve a session for the given channel/peer, creating if needed.
  Future<Session> resolveSession({
    required String channelType,
    required String peerId,
    String? groupId,
  }) async {
    final key =
        groupId != null ? '$channelType:$groupId' : '$channelType:$peerId';

    // Check in-memory cache
    if (_sessions.containsKey(key)) {
      return _sessions[key]!;
    }

    // Create new session
    final session = Session(
      id: _uuid.v4(),
      agentId: defaultAgentId,
      channelType: channelType,
      peerId: peerId,
      groupId: groupId,
      type: groupId != null ? SessionType.group : SessionType.main,
    );

    // Try to load existing transcript
    final existingIds = await store.listSessionIds();
    for (final existingId in existingIds) {
      final transcript = await store.loadTranscript(existingId);
      if (transcript.isNotEmpty) {
        final firstMsg = transcript.first;
        final meta = firstMsg.metadata;
        if (meta['channelType'] == channelType &&
            meta['senderId'] == peerId &&
            (groupId == null || meta['groupId'] == groupId)) {
          String? sessionModel;
          String? sessionProvider;
          String? sessionAgentId;
          String? sessionAgentName;
          String? sessionTitle;
          for (final m in transcript) {
            if (m.metadata.containsKey('agentId')) {
              sessionAgentId = m.metadata['agentId'] as String?;
            }
            if (m.metadata.containsKey('agentName')) {
              sessionAgentName = m.metadata['agentName'] as String?;
            }
            if (m.metadata.containsKey('model')) {
              sessionModel = m.metadata['model'] as String?;
            }
            if (m.metadata.containsKey('provider')) {
              sessionProvider = m.metadata['provider'] as String?;
            }
            if (m.metadata.containsKey('title')) {
              sessionTitle = m.metadata['title'] as String?;
            }
          }

          // Restore existing session
          final restored = Session(
            id: existingId,
            agentId: sessionAgentId ?? defaultAgentId,
            agentName: sessionAgentName,
            channelType: channelType,
            peerId: peerId,
            groupId: groupId,
            model: sessionModel,
            provider: sessionProvider,
            title: sessionTitle,
            type: groupId != null ? SessionType.group : SessionType.main,
            history: transcript,
          );
          _sessions[key] = restored;
          _log.fine('Restored session $existingId for $key');
          return restored;
        }
      }
    }

    _sessions[key] = session;
    _log.info('Created new session ${session.id} for $key');
    return session;
  }

  /// Add a message to a session and persist it.
  Future<void> addMessage({
    required String sessionId,
    required String role,
    required String content,
    Map<String, dynamic> metadata = const {},
    List<MessageAttachment> attachments = const [],
  }) async {
    final message = Message(
      role: role,
      content: content,
      timestamp: DateTime.now(),
      metadata: metadata,
      attachments: attachments,
    );

    // Update in-memory session if cached
    for (final session in _sessions.values) {
      if (session.id == sessionId) {
        session.addMessage(message);

        // Prune history if too long
        if (session.history.length > maxHistory) {
          session.history.removeRange(0, session.history.length - maxHistory);
        }
        break;
      }
    }

    // Persist to disk
    await store.appendMessage(sessionId, message);
  }

  /// Get a session by ID.
  Session? getSession(String sessionId) {
    for (final session in _sessions.values) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  /// List all active sessions.
  List<Map<String, dynamic>> listSessions() {
    return _sessions.values.map((s) => s.toSummary()).toList();
  }

  /// Get session history.
  Future<List<Message>> getHistory(String sessionId, {int? maxMessages}) async {
    final session = getSession(sessionId);
    if (session != null) {
      if (maxMessages != null) {
        return session.lastMessages(maxMessages);
      }
      return List.unmodifiable(session.history);
    }

    // Fall back to disk
    if (maxMessages != null) {
      return store.loadLastMessages(sessionId, maxMessages);
    }
    return store.loadTranscript(sessionId);
  }

  /// Clear a session from memory.
  void evictSession(String sessionKey) {
    _sessions.remove(sessionKey);
  }

  /// Delete a session by ID: remove from cache and delete transcript.
  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((_, s) => s.id == sessionId);
    await store.deleteTranscript(sessionId);
    _log.info('Deleted session $sessionId');
  }

  /// Clear all cached sessions.
  void clearCache() {
    _sessions.clear();
  }
}
