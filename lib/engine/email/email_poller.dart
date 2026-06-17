import 'dart:async';
import 'dart:convert';
import 'package:cron/cron.dart';
import 'package:logging/logging.dart';

import '../agent/manager.dart';
import '../models/message.dart';
import '../tools/registry.dart';
import 'email_manager.dart';
import 'email_models.dart';

class EmailPoller {
  EmailPoller({
    required this.emailManager,
    required this.agentManager,
    this.onEmailChanged,
  });

  final EmailManager emailManager;
  final AgentManager agentManager;
  final void Function(String accountId)? onEmailChanged;

  final Cron _cron = Cron();
  final Logger _log = Logger('Ghost.EmailPoller');
  bool _running = false;
  ScheduledTask? _scheduledTask;

  void start() {
    if (_running) return;
    _running = true;
    // Run every 1 minute
    _scheduledTask = _cron.schedule(Schedule.parse('*/1 * * * *'), () async {
      _log.info('Running background email polling and triage...');
      await pollAndTriageAll();
    });
    _log.info('EmailPoller started (runs every 1 minute).');
    
    // Trigger initial polling after a short delay
    Timer(const Duration(seconds: 15), () {
      _log.info('Triggering initial background email poll...');
      pollAndTriageAll();
    });
  }

  void stop() {
    if (!_running) return;
    _scheduledTask?.cancel();
    _cron.close();
    _running = false;
    _log.info('EmailPoller stopped.');
  }

  Future<void> pollAndTriageAll() async {
    try {
      final accounts = await emailManager.listAccounts();
      for (final account in accounts) {
        if (!account.enabled) continue;
        await _pollAndTriageAccount(account);
      }
    } catch (e) {
      _log.severe('Error during background polling: $e');
    }
  }

  Future<void> _pollAndTriageAccount(EmailAccount account) async {
    _log.info('Polling account: ${account.email}');
    try {
      await emailManager.syncMailbox(account.id, folder: 'INBOX', count: 20);
      onEmailChanged?.call(account.id);
    } catch (e) {
      _log.warning('Failed to sync INBOX for ${account.email}: $e');
      return;
    }

    final cached = await emailManager.listEmails(account.id, folder: 'INBOX', limit: 20);
    final untriaged = cached.where((e) => e.summary.isEmpty).toList();

    if (untriaged.isEmpty) {
      _log.fine('No new untriaged emails for ${account.email}.');
      return;
    }

    _log.info('Triage processing for ${untriaged.length} new emails on ${account.email}');
    for (final email in untriaged) {
      try {
        await triageEmail(account, email);
        onEmailChanged?.call(account.id);
      } catch (e) {
        _log.severe('Failed to triage email ${email.id}: $e');
      }
    }
  }

  Future<void> triageEmail(EmailAccount account, CachedEmail email) async {
    final hasAiEnabled = account.autoSummarize ||
        account.autoTag ||
        account.autoUrgent ||
        account.autoReply ||
        account.autoSpam ||
        account.autoCalendar;

    if (!hasAiEnabled) {
      final updatedEmail = email.copyWith(
        summary: 'Triage disabled by settings.',
      );
      await emailManager.emailsBox.put(email.id, jsonEncode(updatedEmail.toJson()));
      return;
    }

    final lang = agentManager.config.user.language.split('_').first.toLowerCase();
    final langNames = {
      'de': 'German (Deutsch)',
      'en': 'English',
      'fr': 'French (Français)',
      'es': 'Spanish (Español)',
      'it': 'Italian (Italiano)',
      'pt': 'Portuguese (Português)',
      'nl': 'Dutch (Nederlands)',
    };
    final targetLanguage = langNames[lang] ?? 'English';

    final systemPrompt = '''
You are an email triage assistant. Analyze the following email.
Generate a JSON object with exactly the following structure:
{
  "summary": "A 2-sentence summary of the email.",
  "tags": ["tag1", "tag2"],
  "urgency": "none" | "low" | "medium" | "high" | "critical",
  "urgencyReason": "Reason for urgency level.",
  "spam": true | false,
  "spamReason": "Reason for spam verdict.",
  "draftReply": "A drafted reply to this email, matching the user's style: '${account.writingStyle}'.",
  "event": {
    "summary": "Title of event",
    "description": "Details",
    "start": "ISO 8601 start time",
    "end": "ISO 8601 end time"
  } // or null if no event/meeting is found in the email
}

IMPORTANT: You MUST write the text values of "summary", "urgencyReason", "spamReason", and "draftReply" in $targetLanguage.
Use the current local time 2026-06-03T12:01:50+02:00 as a reference point for any relative dates or times.
Do NOT output anything else except the raw JSON.
''';

    final emailContent = '''
From: ${email.sender}
To: ${email.to}
Date: ${email.date.toIso8601String()}
Subject: ${email.subject}

Body:
${email.bodyText.isNotEmpty ? email.bodyText : email.bodyHtml}
''';

    final provider = agentManager.defaultAgent.provider;
    final response = await provider.chat(
      messages: [
        Message(
          role: 'user',
          content: emailContent,
          timestamp: DateTime.now(),
        ),
      ],
      systemPrompt: systemPrompt,
    );

    try {
      final text = response.content.trim();
      final jsonStr = text.startsWith('```')
          ? text.replaceFirst(RegExp(r'^```json\s*'), '').replaceFirst(RegExp(r'\s*```$'), '')
          : text;

      final Map<String, dynamic> data = jsonDecode(jsonStr) as Map<String, dynamic>;

      var updatedEmail = email.copyWith(
        summary: account.autoSummarize ? (data['summary'] as String? ?? '') : 'Summarization disabled.',
        tags: account.autoTag ? ((data['tags'] as List<dynamic>?)?.cast<String>() ?? []) : [],
        urgency: account.autoUrgent ? (data['urgency'] as String? ?? 'none') : 'none',
        urgencyReason: account.autoUrgent ? (data['urgencyReason'] as String? ?? '') : '',
        spamVerdict: account.autoSpam ? (data['spam'] as bool? ?? false) : false,
        spamReason: account.autoSpam ? (data['spamReason'] as String? ?? '') : '',
        aiReplyDraft: account.autoReply ? (data['draftReply'] as String? ?? '') : '',
      );

      await emailManager.emailsBox.put(email.id, jsonEncode(updatedEmail.toJson()));

      // 1. SPAM Actions
      if (updatedEmail.spamVerdict && account.autoSpam) {
        _log.info('Email classified as SPAM. Moving to Junk folder...');
        try {
          await emailManager.moveEmail(account.id, email.id, 'Junk');
          return; // Stop processing further actions for spam
        } catch (e) {
          _log.warning('Could not move spam email to Junk: $e. Fallback to spam tag.');
        }
      }

      // 2. Calendar Event Actions
      if (data['event'] != null && account.autoCalendar) {
        final eventData = data['event'] as Map<String, dynamic>;
        _log.info('Meeting/Event detected in email. Creating calendar event: ${eventData['summary']}');
        try {
          final toolRegistry = agentManager.toolRegistry;
          final context = ToolContext(
            sessionId: 'email_triage_${email.id}',
            agentId: 'default-agent',
            workspaceDir: agentManager.workspaceDir,
            stateDir: agentManager.stateDir,
          );

          if (toolRegistry.isAllowed('google_calendar_add')) {
            await toolRegistry.execute('google_calendar_add', eventData, context);
          } else if (toolRegistry.isAllowed('ms_calendar_add')) {
            await toolRegistry.execute('ms_calendar_add', eventData, context);
          }
        } catch (e) {
          _log.warning('Failed to auto-add calendar event: $e');
        }
      }
    } catch (e) {
      _log.severe('Error parsing triage LLM JSON response: $e\nResponse was: ${response.content}');
      // Save fallback triage to avoid infinite retries
      final updatedEmail = email.copyWith(
        summary: 'Error analyzing email with AI.',
      );
      await emailManager.emailsBox.put(email.id, jsonEncode(updatedEmail.toJson()));
    }
  }
}
