import 'dart:convert';
import 'registry.dart';
import '../sessions/store.dart';

class SessionTools {
  static void registerAll(ToolRegistry registry, SessionStore store) {
    registry.register(SessionsListTool(store));
    registry.register(SessionsHistoryTool(store));
  }
}

class SessionsListTool extends Tool {
  SessionsListTool(this.store);

  final SessionStore store;

  @override
  String get name => 'sessions_list';

  @override
  String get description =>
      'List previous conversation sessions you had with the user. Returns session IDs and the first message snippet. Use this to find a session ID to read its history.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  String getLogSummary(Map<String, dynamic> input) => 'Listing all sessions...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final ids = await store.listSessionIds();
    final List<Map<String, dynamic>> sessions = [];
    for (final id in ids) {
      if (id == context.sessionId) continue; // Optional: skip current session

      final transcript = await store.loadTranscript(id);
      if (transcript.isNotEmpty) {
        final firstMsg = transcript.firstWhere(
          (m) => m.role == 'user',
          orElse: () => transcript.first,
        );
        String snippet = firstMsg.content;
        if (snippet.length > 50) snippet = '${snippet.substring(0, 50)}...';

        sessions.add({
          'id': id,
          'startedAt': transcript.first.timestamp.toIso8601String(),
          'first_user_message': snippet
        });
      }
    }
    return ToolResult(output: jsonEncode(sessions));
  }
}

class SessionsHistoryTool extends Tool {
  SessionsHistoryTool(this.store);

  final SessionStore store;

  @override
  String get name => 'sessions_history';

  @override
  String get description =>
      'Get the chat history of a specific session by its ID.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'sessionId': {
            'type': 'string',
            'description': 'The ID of the session to fetch history for.'
          },
          'maxMessages': {
            'type': 'integer',
            'description': 'Optional. Number of recent messages to fetch.'
          }
        },
        'required': ['sessionId'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      input['sessionId'] as String;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final sessionId = input['sessionId'] as String?;
    if (sessionId == null) {
      return const ToolResult.error('sessionId is required');
    }
    final maxMessages = input['maxMessages'] as int?;

    final transcript = maxMessages != null
        ? await store.loadLastMessages(sessionId, maxMessages)
        : await store.loadTranscript(sessionId);

    if (transcript.isEmpty) {
      return const ToolResult.error('Session not found or is empty.');
    }

    final history =
        transcript.map((m) => {'role': m.role, 'content': m.content}).toList();
    return ToolResult(output: jsonEncode(history));
  }
}
