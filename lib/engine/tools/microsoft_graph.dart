// Ghost — Microsoft Graph API Tools
// Covers: Mail (Outlook), Calendar, OneDrive Files

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/secure_storage.dart';
import 'registry.dart';

class MicrosoftGraphTools {
  static void registerAll(ToolRegistry registry, SecureStorage storage) {
    registry.register(MsMailListTool(storage));
    registry.register(MsMailSendTool(storage));
    registry.register(MsMailDeleteTool(storage));
    registry.register(MsCalendarListTool(storage));
    registry.register(MsCalendarAddEventTool(storage));
    registry.register(MsCalendarDeleteEventTool(storage));
    registry.register(MsOneDriveListTool(storage));
    registry.register(MsOneDriveDeleteTool(storage));
  }
}

// ---------------------------------------------------------------------------
// Shared HTTP client helper
// ---------------------------------------------------------------------------

class MsGraphClient {
  static const _baseUrl = 'https://graph.microsoft.com/v1.0';

  static Future<String?> _getToken(SecureStorage storage) async {
    final token = await storage.get('ms_graph_access_token');
    if (token == null || token.isEmpty) return null;
    return token;
  }

  static Future<http.Response?> get(
    SecureStorage storage,
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final token = await _getToken(storage);
    if (token == null) return null;

    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: queryParams);
    return http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  static Future<http.Response?> post(
    SecureStorage storage,
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _getToken(storage);
    if (token == null) return null;

    return http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  static Future<http.Response?> delete(
    SecureStorage storage,
    String path,
  ) async {
    final token = await _getToken(storage);
    if (token == null) return null;

    return http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// Returns true if the stored token is valid.
  static Future<bool> testConnection(SecureStorage storage) async {
    try {
      final res = await get(storage, '/me');
      return res != null && res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

const _notConnected =
    'Microsoft 365 is not connected. Please sign in via Settings > Integrations.';

// ---------------------------------------------------------------------------
// Mail Tools
// ---------------------------------------------------------------------------

class MsMailListTool extends Tool {
  MsMailListTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_mail_list';

  @override
  String get description =>
      "List emails from the user's Outlook/Microsoft 365 inbox.";

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'folder': {
            'type': 'string',
            'description':
                'Folder to read: "inbox" (default), "sentitems", "drafts", "deleteditems", "junkemail".',
          },
          'maxResults': {
            'type': 'integer',
            'description': 'Max number of emails to return (default 10).',
          },
          'filter': {
            'type': 'string',
            'description':
                'OData filter string, e.g. "isRead eq false" for unread only.',
          },
        },
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Listing ${input['folder'] ?? 'inbox'} emails...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final folder = input['folder'] as String? ?? 'inbox';
    final maxResults = (input['maxResults'] as num?)?.toInt() ?? 10;
    final filter = input['filter'] as String?;

    final queryParams = <String, String>{
      r'$top': '$maxResults',
      r'$select': 'id,subject,from,receivedDateTime,isRead,bodyPreview',
      r'$orderby': 'receivedDateTime desc',
      if (filter != null) r'$filter': filter,
    };

    final res = await MsGraphClient.get(
      storage,
      '/me/mailFolders/$folder/messages',
      queryParams: queryParams,
    );

    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 401) {
      return const ToolResult.error(
          'Microsoft 365 token expired. Please sign in again via Settings > Integrations.');
    }
    if (res.statusCode != 200) {
      return ToolResult.error('Mail API error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final messages = (data['value'] as List<dynamic>?) ?? [];

    if (messages.isEmpty) {
      return ToolResult(output: 'No emails found in $folder.');
    }

    final buffer = StringBuffer('Emails in $folder:\n');
    for (final msg in messages) {
      final subject = msg['subject'] ?? '(no subject)';
      final from = (msg['from']?['emailAddress']?['address']) ?? 'Unknown';
      final date = msg['receivedDateTime'] ?? '';
      final isRead = msg['isRead'] as bool? ?? true;
      final preview = msg['bodyPreview'] ?? '';
      final id = msg['id'] ?? '';
      buffer.writeln(
          '- ID: $id | ${isRead ? '' : '[UNREAD] '}From: $from | Subject: $subject | Date: $date');
      if (preview.isNotEmpty) buffer.writeln('  Preview: $preview');
    }
    return ToolResult(output: buffer.toString());
  }
}

// ---------------------------------------------------------------------------

class MsMailSendTool extends Tool {
  MsMailSendTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_mail_send';

  @override
  String get description => 'Send an email via Microsoft Outlook / Microsoft 365.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
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
            'description': 'Text content of the email.',
          },
          'cc': {
            'type': 'string',
            'description': 'Optional CC email address.',
          },
        },
        'required': ['to', 'subject', 'body'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Sending email to ${input['to']}...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final to = input['to'] as String;
    final subject = input['subject'] as String;
    final body = input['body'] as String;
    final cc = input['cc'] as String?;

    final payload = <String, dynamic>{
      'message': {
        'subject': subject,
        'body': {'contentType': 'Text', 'content': body},
        'toRecipients': [
          {
            'emailAddress': {'address': to}
          }
        ],
        if (cc != null)
          'ccRecipients': [
            {
              'emailAddress': {'address': cc}
            }
          ],
      },
      'saveToSentItems': true,
    };

    final res = await MsGraphClient.post(storage, '/me/sendMail', payload);
    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 401) {
      return const ToolResult.error(
          'Microsoft 365 token expired. Please sign in again.');
    }
    if (res.statusCode == 202) {
      return const ToolResult(output: 'Email sent successfully.');
    }
    return ToolResult.error('Failed to send email (${res.statusCode}): ${res.body}');
  }
}

// ---------------------------------------------------------------------------

class MsMailDeleteTool extends Tool {
  MsMailDeleteTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_mail_delete';

  @override
  String get description => 'Move an Outlook email to the Deleted Items folder.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
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
    final id = input['messageId'] as String;
    final res = await MsGraphClient.delete(storage, '/me/messages/$id');
    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 204) {
      return const ToolResult(output: 'Email deleted successfully.');
    }
    return ToolResult.error('Failed to delete email (${res.statusCode}): ${res.body}');
  }
}

// ---------------------------------------------------------------------------
// Calendar Tools
// ---------------------------------------------------------------------------

class MsCalendarListTool extends Tool {
  MsCalendarListTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_calendar_list';

  @override
  String get description =>
      "List upcoming events from the user's Microsoft Outlook Calendar.";

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'maxResults': {
            'type': 'integer',
            'description': 'Max number of events to return (default 10).',
          },
        },
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Listing upcoming calendar events...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final maxResults = (input['maxResults'] as num?)?.toInt() ?? 10;
    final now = DateTime.now().toUtc().toIso8601String();

    final queryParams = <String, String>{
      r'$top': '$maxResults',
      r'$select': 'id,subject,start,end,location,organizer',
      r'$filter': "start/dateTime ge '$now'",
      r'$orderby': 'start/dateTime asc',
    };

    final res = await MsGraphClient.get(
      storage,
      '/me/events',
      queryParams: queryParams,
    );

    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 401) {
      return const ToolResult.error(
          'Microsoft 365 token expired. Please sign in again.');
    }
    if (res.statusCode != 200) {
      return ToolResult.error('Calendar error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final events = (data['value'] as List<dynamic>?) ?? [];

    if (events.isEmpty) return const ToolResult(output: 'No upcoming events.');

    final buffer = StringBuffer('Upcoming calendar events:\n');
    for (final e in events) {
      final subject = e['subject'] ?? '(no title)';
      final start = e['start']?['dateTime'] ?? '';
      final end = e['end']?['dateTime'] ?? '';
      final location = e['location']?['displayName'] ?? '';
      final id = e['id'] ?? '';
      buffer.writeln(
          '- ID: $id | $subject | Start: $start | End: $end${location.isNotEmpty ? ' | Location: $location' : ''}');
    }
    return ToolResult(output: buffer.toString());
  }
}

// ---------------------------------------------------------------------------

class MsCalendarAddEventTool extends Tool {
  MsCalendarAddEventTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_calendar_add';

  @override
  String get description => "Add a new event to the user's Outlook Calendar.";

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'subject': {'type': 'string', 'description': 'Title of the event.'},
          'body': {
            'type': 'string',
            'description': 'Optional description/notes for the event.',
          },
          'start': {
            'type': 'string',
            'description': 'Start time in ISO 8601 format (e.g. 2025-05-01T10:00:00).',
          },
          'end': {
            'type': 'string',
            'description': 'End time in ISO 8601 format (e.g. 2025-05-01T11:00:00).',
          },
          'location': {
            'type': 'string',
            'description': 'Optional location of the event.',
          },
          'timeZone': {
            'type': 'string',
            'description': 'Time zone (e.g. "Europe/Berlin"). Defaults to UTC.',
          },
        },
        'required': ['subject', 'start', 'end'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Adding calendar event: ${input['subject']}...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final tz = input['timeZone'] as String? ?? 'UTC';

    final payload = <String, dynamic>{
      'subject': input['subject'],
      'body': {
        'contentType': 'Text',
        'content': input['body'] ?? '',
      },
      'start': {'dateTime': input['start'], 'timeZone': tz},
      'end': {'dateTime': input['end'], 'timeZone': tz},
      if (input['location'] != null)
        'location': {'displayName': input['location']},
    };

    final res = await MsGraphClient.post(storage, '/me/events', payload);
    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return ToolResult(
          output:
              'Event created: ${data['subject']} (ID: ${data['id']})');
    }
    return ToolResult.error('Failed to create event (${res.statusCode}): ${res.body}');
  }
}

// ---------------------------------------------------------------------------

class MsCalendarDeleteEventTool extends Tool {
  MsCalendarDeleteEventTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_calendar_delete';

  @override
  String get description => 'Delete an event from the Outlook Calendar.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
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
    final id = input['eventId'] as String;
    final res = await MsGraphClient.delete(storage, '/me/events/$id');
    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 204) {
      return const ToolResult(output: 'Calendar event deleted successfully.');
    }
    return ToolResult.error('Failed to delete event (${res.statusCode}): ${res.body}');
  }
}

// ---------------------------------------------------------------------------
// OneDrive Tools
// ---------------------------------------------------------------------------

class MsOneDriveListTool extends Tool {
  MsOneDriveListTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_onedrive_list';

  @override
  String get description =>
      "Search for files in the user's OneDrive.";

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Filename or keyword to search for.',
          },
          'maxResults': {
            'type': 'integer',
            'description': 'Max number of files to return (default 10).',
          },
        },
        'required': ['query'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Searching OneDrive for "${input['query']}"...';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final query = input['query'] as String;
    final maxResults = (input['maxResults'] as num?)?.toInt() ?? 10;

    final res = await MsGraphClient.get(
      storage,
      '/me/drive/root/search(q=\'${Uri.encodeComponent(query)}\')',
      queryParams: {
        r'$top': '$maxResults',
        r'$select': 'id,name,size,webUrl,lastModifiedDateTime',
      },
    );

    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 401) {
      return const ToolResult.error(
          'Microsoft 365 token expired. Please sign in again.');
    }
    if (res.statusCode != 200) {
      return ToolResult.error('OneDrive error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final files = (data['value'] as List<dynamic>?) ?? [];

    if (files.isEmpty) {
      return ToolResult(output: 'No files found matching "$query".');
    }

    final buffer = StringBuffer('OneDrive files matching "$query":\n');
    for (final f in files) {
      final name = f['name'] ?? '?';
      final id = f['id'] ?? '';
      final size = f['size'] ?? 0;
      final modified = f['lastModifiedDateTime'] ?? '';
      final url = f['webUrl'] ?? '';
      buffer.writeln(
          '- ID: $id | $name | Size: ${size}B | Modified: $modified | URL: $url');
    }
    return ToolResult(output: buffer.toString());
  }
}

// ---------------------------------------------------------------------------

class MsOneDriveDeleteTool extends Tool {
  MsOneDriveDeleteTool(this.storage);
  final SecureStorage storage;

  @override
  String get name => 'ms_onedrive_delete';

  @override
  String get description => 'Delete a file from OneDrive.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
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
    final id = input['fileId'] as String;
    final res = await MsGraphClient.delete(storage, '/me/drive/items/$id');
    if (res == null) return const ToolResult.error(_notConnected);
    if (res.statusCode == 204) {
      return const ToolResult(output: 'File deleted successfully.');
    }
    return ToolResult.error('Failed to delete file (${res.statusCode}): ${res.body}');
  }
}
