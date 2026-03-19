import 'dart:convert';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import '../config/secure_storage.dart';
import 'registry.dart';

class GoogleWorkspaceTools {
  static void registerAll(ToolRegistry registry, SecureStorage storage) {
    registry.register(GoogleCalendarTool(storage));
    registry.register(GoogleCalendarAddEventTool(storage));
    registry.register(GoogleCalendarDeleteEventTool(storage));
    registry.register(GoogleGmailTool(storage));
    registry.register(GoogleGmailDeleteTool(storage));
    registry.register(GoogleGmailSendTool(storage));
    registry.register(GoogleDriveTool(storage));
    registry.register(GoogleDriveDeleteTool(storage));
  }
}

class GoogleWorkspaceClient {
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/drive',
  ];

  static Future<AuthClient?> getClient(SecureStorage storage) async {
    final token = await storage.get('google_access_token');
    if (token == null || token.isEmpty) return null;

    final credentials = AccessCredentials(
      AccessToken('Bearer', token,
          DateTime.now().toUtc().add(const Duration(minutes: 50))),
      null,
      scopes,
    );
    return authenticatedClient(http.Client(), credentials);
  }

  static Future<bool> testConnection(SecureStorage storage) async {
    final client = await getClient(storage);
    if (client == null) return false;
    try {
      final api = gmail.GmailApi(client);
      await api.users.getProfile('me');
      return true;
    } catch (e) {
      return false;
    } finally {
      client.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Google Calendar Tools
// ---------------------------------------------------------------------------

class GoogleCalendarTool extends Tool {
  GoogleCalendarTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_calendar_list';

  @override
  String get description =>
      "View upcoming events in the user's Google Calendar.";

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'maxResults': {
            'type': 'integer',
            'description':
                'The maximum number of events to return (default 10).',
          },
        },
      };

  @override
  String getLogSummary(Map<String, dynamic> input) => 'Listing upcoming events...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error(
          'Google Workspace is not connected. Please sign in via Settings > Integrations.');
    }

    final maxResults = (input['maxResults'] as num?)?.toInt() ?? 10;

    try {
      final api = calendar.CalendarApi(client);
      final events = await api.events.list('primary',
          timeMin: DateTime.now().toUtc(),
          maxResults: maxResults,
          singleEvents: true,
          orderBy: 'startTime');

      if (events.items == null || events.items!.isEmpty) {
        return const ToolResult(output: 'No upcoming events found.');
      }

      final buffer = StringBuffer('Upcoming events:\n');
      for (final event in events.items!) {
        final start = event.start?.dateTime ?? event.start?.date;
        buffer.writeln('- ID: ${event.id} | ${event.summary} at $start');
      }
      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Calendar error: $e');
    }
  }
}

class GoogleCalendarAddEventTool extends Tool {
  GoogleCalendarAddEventTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_calendar_add';

  @override
  String get description => "Add a new event to the user's Google Calendar.";

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'summary': {
            'type': 'string',
            'description': 'The title of the event.',
          },
          'description': {
            'type': 'string',
            'description': 'The description of the event.',
          },
          'start': {
            'type': 'string',
            'description':
                'The start time in ISO 8601 format (e.g., 2023-10-27T10:00:00Z).',
          },
          'end': {
            'type': 'string',
            'description':
                'The end time in ISO 8601 format (e.g., 2023-10-27T11:00:00Z).',
          },
        },
        'required': ['summary', 'start', 'end'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Adding event: ${input['summary']}...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error('Google Workspace is not connected.');
    }

    try {
      final api = calendar.CalendarApi(client);
      final event = calendar.Event()
        ..summary = input['summary'] as String
        ..description = input['description'] as String?
        ..start = (calendar.EventDateTime()
          ..dateTime = DateTime.parse(input['start'] as String).toUtc())
        ..end = (calendar.EventDateTime()
          ..dateTime = DateTime.parse(input['end'] as String).toUtc());

      final created = await api.events.insert(event, 'primary');
      return ToolResult(
          output:
              'Event created successfully: ${created.summary} (ID: ${created.id})');
    } catch (e) {
      return ToolResult.error('Failed to add calendar event: $e');
    }
  }
}

class GoogleCalendarDeleteEventTool extends Tool {
  GoogleCalendarDeleteEventTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_calendar_delete';

  @override
  String get description => "Delete an event from the user's Google Calendar.";

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'eventId': {
            'type': 'string',
            'description': 'The ID of the event to delete.',
          },
        },
        'required': ['eventId'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error('Google Workspace is not connected.');
    }

    try {
      final api = calendar.CalendarApi(client);
      await api.events.delete('primary', input['eventId'] as String);
      return const ToolResult(output: 'Event deleted successfully.');
    } catch (e) {
      return ToolResult.error('Failed to delete calendar event: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Google Gmail Tools
// ---------------------------------------------------------------------------

class GoogleGmailTool extends Tool {
  GoogleGmailTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_gmail_list';

  @override
  String get description => "List the user's emails from Gmail.";

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'query': {
            'type': 'string',
            'description':
                'Gmail search query (e.g., "is:unread", "from:someone@example.com"). Defaults to "is:unread".',
          },
          'maxResults': {
            'type': 'integer',
            'description':
                'The maximum number of emails to return (default 10).',
          },
        },
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Searching emails for "${input['query'] ?? 'is:unread'}"...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error(
          'Google Workspace is not connected. Please sign in via Settings > Integrations.');
    }

    final query = input['query'] as String? ?? 'is:unread';
    final maxResults = (input['maxResults'] as num?)?.toInt() ?? 10;

    try {
      final api = gmail.GmailApi(client);
      final response =
          await api.users.messages.list('me', q: query, maxResults: maxResults);

      if (response.messages == null || response.messages!.isEmpty) {
        return ToolResult(output: 'No emails found matching query: $query');
      }

      final buffer = StringBuffer('Emails (query: $query):\n');
      for (final msgRef in response.messages!) {
        final msg = await api.users.messages.get('me', msgRef.id!);
        String subject = 'No Subject';
        String from = 'Unknown Sender';
        final headers = msg.payload?.headers;
        if (headers != null) {
          for (final h in headers) {
            if (h.name == 'Subject') subject = h.value ?? subject;
            if (h.name == 'From') from = h.value ?? from;
          }
        }
        buffer.writeln(
            '- ID: ${msg.id} | From: $from | Subject: $subject | Snippet: ${msg.snippet}');
      }
      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Gmail error: $e');
    }
  }
}

class GoogleGmailDeleteTool extends Tool {
  GoogleGmailDeleteTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_gmail_delete';

  @override
  String get description => 'Move a Gmail message to the trash.';

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'messageId': {
            'type': 'string',
            'description': 'The ID of the message to delete.',
          },
        },
        'required': ['messageId'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error('Google Workspace is not connected.');
    }

    try {
      final api = gmail.GmailApi(client);
      await api.users.messages.trash('me', input['messageId'] as String);
      return const ToolResult(output: 'Email moved to trash successfully.');
    } catch (e) {
      return ToolResult.error('Failed to delete email: $e');
    }
  }
}

class GoogleGmailSendTool extends Tool {
  GoogleGmailSendTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_gmail_send';

  @override
  String get description => 'Send a new email message.';

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'to': {
            'type': 'string',
            'description': 'Recipient email address.',
          },
          'subject': {
            'type': 'string',
            'description': 'Subject of the email.',
          },
          'body': {
            'type': 'string',
            'description': 'The text content of the email.',
          },
        },
        'required': ['to', 'subject', 'body'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Sending email to: ${input['to']}...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error('Google Workspace is not connected.');
    }

    try {
      final api = gmail.GmailApi(client);
      final to = input['to'] as String;
      final subject = input['subject'] as String;
      final body = input['body'] as String;

      // Construct a simple RFC 822 message
      final rawMessage = 'To: $to\r\n'
          'Subject: $subject\r\n'
          'Content-Type: text/plain; charset="UTF-8"\r\n\r\n'
          '$body';

      final message = gmail.Message()
        ..raw = base64Url.encode(utf8.encode(rawMessage)).replaceAll('=', '');

      await api.users.messages.send(message, 'me');
      return const ToolResult(output: 'Email sent successfully.');
    } catch (e) {
      return ToolResult.error('Failed to send email: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Google Drive Tools
// ---------------------------------------------------------------------------

class GoogleDriveTool extends Tool {
  GoogleDriveTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_drive_list';

  @override
  String get description => "Search for files in the user's Google Drive.";

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'query': {
            'type': 'string',
            'description':
                'The search query for filenames (e.g., "name contains \'report\'").',
          },
          'maxResults': {
            'type': 'integer',
            'description':
                'The maximum number of files to return (default 10).',
          },
        },
        'required': ['query'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Searching Drive for "${input['query']}"...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final query = input['query'] as String;
    final maxResults = (input['maxResults'] as num?)?.toInt() ?? 10;

    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error(
          'Google Workspace is not connected. Please sign in via Settings > Integrations.');
    }

    try {
      final api = drive.DriveApi(client);
      final response = await api.files.list(
          q: query, pageSize: maxResults, $fields: 'files(id, name, mimeType)');

      if (response.files == null || response.files!.isEmpty) {
        return ToolResult(output: 'No files found matching query: $query');
      }

      final buffer = StringBuffer('Drive files:\n');
      for (final file in response.files!) {
        buffer.writeln(
            '- ID: ${file.id} | ${file.name} (Type: ${file.mimeType})');
      }
      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Drive error: $e');
    }
  }
}

class GoogleDriveDeleteTool extends Tool {
  GoogleDriveDeleteTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'google_drive_delete';

  @override
  String get description => 'Delete a file from Google Drive.';

  @override
  Map<String, dynamic> get inputSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'fileId': {
            'type': 'string',
            'description': 'The ID of the file to delete.',
          },
        },
        'required': ['fileId'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final client = await GoogleWorkspaceClient.getClient(storage);
    if (client == null) {
      return const ToolResult.error('Google Workspace is not connected.');
    }

    try {
      final api = drive.DriveApi(client);
      await api.files.delete(input['fileId'] as String);
      return const ToolResult(output: 'File deleted successfully.');
    } catch (e) {
      return ToolResult.error('Failed to delete file: $e');
    }
  }
}
