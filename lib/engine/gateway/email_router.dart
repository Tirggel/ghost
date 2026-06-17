import 'dart:convert';
import 'package:logging/logging.dart';

import '../gateway/server.dart';
import '../infra/errors.dart';
import '../email/email_manager.dart';
import '../email/email_models.dart';
import '../agent/manager.dart';
import '../models/message.dart';

final _log = Logger('Ghost.EmailRouter');

class EmailRouter {
  EmailRouter({
    required this.gateway,
    required this.emailManager,
    required this.agentManager,
  });

  final GatewayServer gateway;
  final EmailManager emailManager;
  final AgentManager agentManager;


  void register() {
    // --- List Accounts ---
    gateway.rpcRegistry.register('email.listAccounts', (params, context) async {
      final accounts = await emailManager.listAccounts();
      return {
        'status': 'ok',
        'accounts': accounts.map((a) => a.toJson()).toList(),
      };
    });

    // --- Get Single Account ---
    gateway.rpcRegistry.register('email.getAccount', (params, context) async {
      final id = params?['id'] as String?;
      if (id == null) throw ProtocolError('Missing required parameter: id');

      final account = await emailManager.getAccount(id);
      if (account == null) throw ProtocolError('Email account not found: $id');

      return {
        'status': 'ok',
        'account': account.toJson(),
      };
    });

    // --- Save Account ---
    gateway.rpcRegistry.register('email.saveAccount', (params, context) async {
      final accountData = params?['account'] as Map<String, dynamic>?;
      if (accountData == null) {
        throw ProtocolError('Missing required parameter: account');
      }

      final account = EmailAccount.fromJson(accountData);
      final imapPassword = params?['imapPassword'] as String?;
      final smtpPassword = params?['smtpPassword'] as String?;

      await emailManager.saveAccount(
        account,
        imapPassword: imapPassword,
        smtpPassword: smtpPassword,
      );

      gateway.broadcast('email.accountsChanged');
      return {'status': 'ok'};
    });

    // --- Delete Account ---
    gateway.rpcRegistry.register('email.deleteAccount', (params, context) async {
      final id = params?['id'] as String?;
      if (id == null) throw ProtocolError('Missing required parameter: id');

      await emailManager.deleteAccount(id);
      gateway.broadcast('email.accountsChanged');
      return {'status': 'ok'};
    });

    // --- Test Account Connection ---
    gateway.rpcRegistry.register('email.testAccount', (params, context) async {
      final accountData = params?['account'] as Map<String, dynamic>?;
      if (accountData == null) {
        throw ProtocolError('Missing required parameter: account');
      }

      final account = EmailAccount.fromJson(accountData);
      final imapPassword = params?['imapPassword'] as String?;
      final smtpPassword = params?['smtpPassword'] as String?;

      final success = await emailManager.testConnection(
        account,
        imapPassword: imapPassword,
        smtpPassword: smtpPassword,
      );

      return {
        'status': 'ok',
        'success': success,
      };
    });

    // --- List Folders ---
    gateway.rpcRegistry.register('email.listFolders', (params, context) async {
      final accountId = params?['accountId'] as String?;
      if (accountId == null) {
        throw ProtocolError('Missing required parameter: accountId');
      }

      final folders = await emailManager.listFolders(accountId);
      return {
        'status': 'ok',
        'folders': folders.map((f) => f.toJson()).toList(),
      };
    });

    // --- List Emails ---
    gateway.rpcRegistry.register('email.listEmails', (params, context) async {
      final accountId = params?['accountId'] as String?;
      if (accountId == null) {
        throw ProtocolError('Missing required parameter: accountId');
      }

      final folder = params?['folder'] as String?;
      final limit = (params?['limit'] as num?)?.toInt() ?? 50;
      final offset = (params?['offset'] as num?)?.toInt() ?? 0;
      final filter = params?['filter'] as String?;

      final emails = await emailManager.listEmails(
        accountId,
        folder: folder,
        limit: limit,
        offset: offset,
        filter: filter,
      );

      return {
        'status': 'ok',
        'emails': emails.map((e) => e.toJson()).toList(),
      };
    });

    // --- Mark Flags (Read/Favorite) ---
    gateway.rpcRegistry.register('email.markFlags', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailId = params?['emailId'] as String?;
      if (accountId == null || emailId == null) {
        throw ProtocolError('Missing required parameters: accountId, emailId');
      }

      final isRead = params?['isRead'] as bool?;
      final isFavorite = params?['isFavorite'] as bool?;

      await emailManager.markFlags(
        accountId,
        emailId,
        isRead: isRead,
        isFavorite: isFavorite,
      );

      gateway.broadcast('email.changed', {'accountId': accountId, 'emailId': emailId});
      return {'status': 'ok'};
    });

    // --- Move Email ---
    gateway.rpcRegistry.register('email.moveEmail', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailId = params?['emailId'] as String?;
      final targetFolder = params?['targetFolder'] as String?;

      if (accountId == null || emailId == null || targetFolder == null) {
        throw ProtocolError('Missing required parameters: accountId, emailId, targetFolder');
      }

      await emailManager.moveEmail(accountId, emailId, targetFolder);
      gateway.broadcast('email.changed', {'accountId': accountId, 'emailId': emailId});
      return {'status': 'ok'};
    });

    // --- Empty Folder ---
    gateway.rpcRegistry.register('email.emptyFolder', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final folder = params?['folder'] as String?;

      if (accountId == null || folder == null) {
        throw ProtocolError('Missing required parameters: accountId, folder');
      }

      await emailManager.emptyFolder(accountId, folder);
      gateway.broadcast('email.changed', {'accountId': accountId});
      return {'status': 'ok'};
    });

    // --- Delete Email Permanently ---
    gateway.rpcRegistry.register('email.deleteEmailPermanently', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailId = params?['emailId'] as String?;

      if (accountId == null || emailId == null) {
        throw ProtocolError('Missing required parameters: accountId, emailId');
      }

      await emailManager.deleteEmailPermanently(accountId, emailId);
      gateway.broadcast('email.changed', {'accountId': accountId, 'emailId': emailId});
      return {'status': 'ok'};
    });

    // --- Move Batch Emails ---
    gateway.rpcRegistry.register('email.moveEmails', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailIds = (params?['emailIds'] as List<dynamic>?)?.cast<String>();
      final targetFolder = params?['targetFolder'] as String?;

      if (accountId == null || emailIds == null || targetFolder == null) {
        throw ProtocolError('Missing required parameters: accountId, emailIds, targetFolder');
      }

      await emailManager.moveEmails(accountId, emailIds, targetFolder);
      gateway.broadcast('email.changed', {'accountId': accountId});
      return {'status': 'ok'};
    });

    // --- Delete Batch Emails Permanently ---
    gateway.rpcRegistry.register('email.deleteEmailsPermanently', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailIds = (params?['emailIds'] as List<dynamic>?)?.cast<String>();

      if (accountId == null || emailIds == null) {
        throw ProtocolError('Missing required parameters: accountId, emailIds');
      }

      await emailManager.deleteEmailsPermanently(accountId, emailIds);
      gateway.broadcast('email.changed', {'accountId': accountId});
      return {'status': 'ok'};
    });

    // --- Send Email ---
    gateway.rpcRegistry.register('email.sendEmail', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final to = params?['to'] as String?;
      final subject = params?['subject'] as String?;
      final bodyMarkdown = params?['bodyMarkdown'] as String?;
      final attachmentPaths = (params?['attachmentPaths'] as List<dynamic>?)?.cast<String>();

      if (accountId == null || to == null || subject == null || bodyMarkdown == null) {
        throw ProtocolError('Missing required parameters: accountId, to, subject, bodyMarkdown');
      }

      await emailManager.sendEmail(
        accountId,
        to: to,
        subject: subject,
        bodyMarkdown: bodyMarkdown,
        attachmentPaths: attachmentPaths,
      );

      return {'status': 'ok'};
    });

    // --- Generate AI Reply Draft ---
    gateway.rpcRegistry.register('email.generateReply', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailId = params?['emailId'] as String?;

      if (accountId == null || emailId == null) {
        throw ProtocolError('Missing required parameters: accountId, emailId');
      }

      final account = await emailManager.getAccount(accountId);
      if (account == null) {
        throw ProtocolError('Email account not found: $accountId');
      }

      final emailJson = emailManager.emailsBox.get(emailId);
      if (emailJson == null) {
        throw ProtocolError('Email not found in cache: $emailId');
      }
      final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);

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
You are an email assistant. Generate a professional and contextually appropriate reply to the following email.
The reply should match the user's preferred writing style: '${account.writingStyle}'.
IMPORTANT: You MUST write the reply in $targetLanguage.
Do not include any placeholders like [Your Name] or [Insert Date]. Write a complete, ready-to-send draft.
Only return the generated reply text, do not wrap it in JSON or add any conversational introductory text. Just the draft itself.
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

      final reply = response.content.trim();

      return {
        'status': 'ok',
        'reply': reply,
      };
    });

    // --- Download Attachment ---
    gateway.rpcRegistry.register('email.downloadAttachment', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailId = params?['emailId'] as String?;
      final fileName = params?['fileName'] as String?;

      if (accountId == null || emailId == null || fileName == null) {
        throw ProtocolError('Missing required parameters: accountId, emailId, fileName');
      }

      final localPath = await emailManager.downloadAttachment(accountId, emailId, fileName);
      return {
        'status': 'ok',
        'path': localPath,
      };
    });

    // --- Get Attachment Names ---
    gateway.rpcRegistry.register('email.getAttachmentNames', (params, context) async {
      final accountId = params?['accountId'] as String?;
      final emailId = params?['emailId'] as String?;
      if (accountId == null || emailId == null) {
        throw ProtocolError('Missing required parameters: accountId, emailId');
      }
      final names = await emailManager.getAttachmentNames(accountId, emailId);
      return {
        'status': 'ok',
        'names': names,
      };
    });

    // --- Manual Trigger Scan ---
    gateway.rpcRegistry.register('email.triggerScan', (params, context) async {
      final accountId = params?['accountId'] as String?;
      if (accountId == null) {
        throw ProtocolError('Missing required parameter: accountId');
      }

      final folder = params?['folder'] as String? ?? 'INBOX';
      final count = (params?['count'] as num?)?.toInt() ?? 50;
      
      // Await sync completion so the caller knows data is ready in the local cache.
      // The broadcast signals any other listeners (e.g. background screens) to refresh.
      try {
        await emailManager.syncMailbox(accountId, folder: folder, count: count);
        gateway.broadcast('email.changed', {'accountId': accountId});
      } catch (e) {
        _log.warning('Manual trigger scan failed: $e');
        rethrow;
      }

      return {'status': 'synced'};
    });

    _log.info('Email RPC routes registered');
  }
}
