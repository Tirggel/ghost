import 'dart:convert';
import 'dart:io';
import 'package:enough_mail/enough_mail.dart';
import 'package:hive_ce/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../config/secure_storage.dart';
import 'email_models.dart';

class EmailManager {
  EmailManager({
    required this.secureStorage,
    required this.stateDir,
  });

  final SecureStorage secureStorage;
  final String stateDir;

  static const String _accountsBoxName = 'email_accounts';
  static const String _emailsBoxName = 'emails';

  late Box<String> _accountsBox;
  late Box<String> _emailsBox;
  bool _initialized = false;

  Box<String> get accountsBox => _accountsBox;
  Box<String> get emailsBox => _emailsBox;

  final Map<String, MailClient> _clients = {};
  final Logger _log = Logger('Ghost.EmailManager');

  Future<void> init() async {
    if (_initialized) return;
    final attachmentsDir = Directory(p.join(stateDir, 'mail-attachments'));
    if (!attachmentsDir.existsSync()) {
      attachmentsDir.createSync(recursive: true);
    }
    _accountsBox = await Hive.openBox<String>(_accountsBoxName);
    _emailsBox = await Hive.openBox<String>(_emailsBoxName);
    _initialized = true;
    _log.info('EmailManager initialized.');
  }

  Future<void> close() async {
    if (!_initialized) return;
    for (final client in _clients.values) {
      try {
        await client.disconnect();
      } catch (e) {
        _log.warning('Error disconnecting client: $e');
      }
    }
    _clients.clear();
    await _accountsBox.close();
    await _emailsBox.close();
    _initialized = false;
    _log.info('EmailManager closed.');
  }

  Future<List<EmailAccount>> listAccounts() async {
    await init();
    final list = <EmailAccount>[];
    for (final value in _accountsBox.values) {
      try {
        list.add(EmailAccount.fromJson(jsonDecode(value) as Map<String, dynamic>));
      } catch (e) {
        _log.severe('Error parsing email account: $e');
      }
    }
    return list;
  }

  Future<EmailAccount?> getAccount(String id) async {
    await init();
    final value = _accountsBox.get(id);
    if (value == null) return null;
    try {
      return EmailAccount.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAccount(
    EmailAccount account, {
    String? imapPassword,
    String? smtpPassword,
  }) async {
    await init();
    await _accountsBox.put(account.id, jsonEncode(account.toJson()));
    if (imapPassword != null && imapPassword.isNotEmpty) {
      await secureStorage.set('email_account_${account.id}_imap_password', imapPassword);
    }
    if (smtpPassword != null && smtpPassword.isNotEmpty) {
      await secureStorage.set('email_account_${account.id}_smtp_password', smtpPassword);
    }
    // Force reconnect next time
    final client = _clients.remove(account.id);
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<void> deleteAccount(String id) async {
    await init();
    await _accountsBox.delete(id);
    await secureStorage.remove('email_account_${id}_imap_password');
    await secureStorage.remove('email_account_${id}_smtp_password');

    final client = _clients.remove(id);
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {}
    }

    final keysToDelete = <String>[];
    for (final key in _emailsBox.keys) {
      try {
        final emailJson = _emailsBox.get(key);
        if (emailJson != null) {
          final decoded = jsonDecode(emailJson) as Map<String, dynamic>;
          if (decoded['accountId'] == id) {
            keysToDelete.add(key as String);
          }
        }
      } catch (_) {}
    }
    if (keysToDelete.isNotEmpty) {
      await _emailsBox.deleteAll(keysToDelete);
    }
  }

  Future<MailAccount> _buildMailAccount(EmailAccount account, {String? imapPassword, String? smtpPassword}) async {
    final effectiveImapPassword = imapPassword ??
        await secureStorage.get('email_account_${account.id}_imap_password') ??
        '';

    final incomingSocketType = account.imapSecure ? SocketType.ssl : SocketType.plain;
    final outgoingSocketType = account.smtpSecure ? SocketType.ssl : SocketType.plain;

    return MailAccount.fromManualSettings(
      name: account.name,
      email: account.email,
      incomingHost: account.imapHost,
      outgoingHost: account.smtpHost,
      password: effectiveImapPassword,
      userName: account.email,
      incomingPort: account.imapPort,
      outgoingPort: account.smtpPort,
      incomingSocketType: incomingSocketType,
      outgoingSocketType: outgoingSocketType,
    );
  }

  Future<bool> testConnection(EmailAccount account, {String? imapPassword, String? smtpPassword}) async {
    try {
      final mailAccount = await _buildMailAccount(account, imapPassword: imapPassword, smtpPassword: smtpPassword);
      final client = MailClient(mailAccount);
      await client.connect();
      await client.disconnect();
      return true;
    } catch (e) {
      _log.warning('Test connection failed for ${account.email}: $e');
      return false;
    }
  }

  Future<MailClient> _getClientForAccount(EmailAccount account) async {
    await init();
    if (_clients.containsKey(account.id)) {
      final client = _clients[account.id]!;
      if (client.isConnected) {
        return client;
      }
    }
    final mailAccount = await _buildMailAccount(account);
    final client = MailClient(mailAccount);
    await client.connect();
    _clients[account.id] = client;
    return client;
  }

  Future<void> _selectMailbox(MailClient client, String folder) async {
    if (folder.toUpperCase() == 'INBOX') {
      await client.selectInbox();
      return;
    }
    
    try {
      await client.selectMailboxByPath(folder);
    } catch (e) {
      _log.warning('selectMailboxByPath failed for $folder: $e. Retrying via listMailboxes lookup...');
      final mailboxes = await client.listMailboxes();
      final target = mailboxes.firstWhere(
        (m) => m.path.toLowerCase() == folder.toLowerCase(),
        orElse: () => throw Exception('Mailbox $folder not found on server.'),
      );
      await client.selectMailbox(target);
    }
  }

  Future<List<CachedEmail>> listEmails(
    String accountId, {
    String? folder,
    int limit = 50,
    int offset = 0,
    String? filter,
  }) async {
    await init();
    var query = _emailsBox.values.map((v) => CachedEmail.fromJson(jsonDecode(v) as Map<String, dynamic>))
        .where((e) => e.accountId == accountId);

    if (folder != null && folder.isNotEmpty) {
      query = query.where((e) => e.folder.toLowerCase() == folder.toLowerCase());
    }

    if (filter != null && filter.isNotEmpty) {
      final lowerFilter = filter.toLowerCase();
      if (lowerFilter == 'unread') {
        query = query.where((e) => !e.isRead);
      } else if (lowerFilter == 'favorite') {
        query = query.where((e) => e.isFavorite);
      } else if (lowerFilter == 'spam') {
        query = query.where((e) => e.spamVerdict);
      } else if (lowerFilter.startsWith('urgency:')) {
        final u = lowerFilter.substring(8);
        query = query.where((e) => e.urgency.toLowerCase() == u);
      } else {
        query = query.where((e) =>
            e.subject.toLowerCase().contains(lowerFilter) ||
            e.sender.toLowerCase().contains(lowerFilter) ||
            e.bodyText.toLowerCase().contains(lowerFilter));
      }
    }

    final list = query.toList();
    list.sort((a, b) => b.date.compareTo(a.date));

    return list.skip(offset).take(limit).toList();
  }

  Future<List<EmailFolder>> listFolders(String accountId) async {
    await init();
    final account = await getAccount(accountId);
    if (account == null) return [];

    final localFolders = <String, EmailFolder>{};
    
    // Build initial folder list from cache
    for (final value in _emailsBox.values) {
      try {
        final email = CachedEmail.fromJson(jsonDecode(value) as Map<String, dynamic>);
        if (email.accountId == accountId) {
          final current = localFolders[email.folder] ?? EmailFolder(name: email.folder);
          localFolders[email.folder] = EmailFolder(
            name: email.folder,
            unreadCount: current.unreadCount + (email.isRead ? 0 : 1),
            totalCount: current.totalCount + 1,
          );
        }
      } catch (_) {}
    }

    // Try online sync if connected
    try {
      final client = await _getClientForAccount(account);
      final mailboxes = await client.listMailboxes();
      final result = <EmailFolder>[];
      for (final mb in mailboxes) {
        final cached = localFolders[mb.path];
        result.add(EmailFolder(
          name: mb.path,
          unreadCount: cached?.unreadCount ?? 0,
          totalCount: cached?.totalCount ?? 0,
        ));
      }
      return result;
    } catch (e) {
      _log.warning('Could not fetch folders from server, using local cache: $e');
      return localFolders.values.toList();
    }
  }

  Future<void> syncMailbox(String accountId, {String folder = 'INBOX', int count = 50}) async {
    final account = await getAccount(accountId);
    if (account == null || !account.enabled) return;

    final client = await _getClientForAccount(account);
    await _selectMailbox(client, folder);

    final messages = await client.fetchMessages(count: count);
    
    // Build set of UIDs returned by the server
    final serverUids = messages.map((m) => m.uid ?? m.sequenceId ?? 0).toSet();
    int? minUid;
    for (final m in messages) {
      final uid = m.uid ?? m.sequenceId ?? 0;
      if (minUid == null || uid < minUid) {
        minUid = uid;
      }
    }

    final isFolderEmpty = client.selectedMailbox?.messagesExists == 0;

    // Prune stale/deleted emails from local cache
    final localKeysToDelete = <String>[];
    for (final key in _emailsBox.keys) {
      try {
        final emailJson = _emailsBox.get(key);
        if (emailJson != null) {
          final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);
          if (email.accountId == accountId && email.folder.toLowerCase() == folder.toLowerCase()) {
            if (isFolderEmpty) {
              localKeysToDelete.add(key as String);
            } else if (minUid != null && email.uid >= minUid && !serverUids.contains(email.uid)) {
              localKeysToDelete.add(key as String);
            }
          }
        }
      } catch (_) {}
    }

    if (localKeysToDelete.isNotEmpty) {
      _log.info('Pruning ${localKeysToDelete.length} stale/deleted emails from local cache for $folder');
      await _emailsBox.deleteAll(localKeysToDelete);
    }

    for (final message in messages) {
      final uid = message.uid ?? message.sequenceId ?? 0;
      final messageId = message.getHeaderValue('Message-ID') ?? '';
      final localId = '${accountId}_${folder}_$uid';

      final existingJson = _emailsBox.get(localId);
      final isRead = message.isSeen;
      final isFavorite = message.isFlagged;

      if (existingJson != null) {
        final existing = CachedEmail.fromJson(jsonDecode(existingJson) as Map<String, dynamic>);
        if (existing.isRead != isRead || existing.isFavorite != isFavorite) {
          final updated = existing.copyWith(isRead: isRead, isFavorite: isFavorite);
          await _emailsBox.put(localId, jsonEncode(updated.toJson()));
        }
      } else {
        final subject = message.decodeSubject() ?? '(No Subject)';
        final sender = _formatAddresses(message.from);
        final to = _formatAddresses(message.to);
        final date = message.decodeDate() ?? DateTime.now();
        final bodyText = message.decodeTextPlainPart() ?? '';
        final bodyHtml = message.decodeTextHtmlPart() ?? '';
        final hasAttachments = message.findContentInfo().isNotEmpty;

        final cachedEmail = CachedEmail(
          id: localId,
          accountId: accountId,
          uid: uid,
          folder: folder,
          messageId: messageId,
          subject: subject,
          sender: sender,
          to: to,
          date: date,
          bodyText: bodyText,
          bodyHtml: bodyHtml,
          isRead: isRead,
          isFavorite: isFavorite,
          hasAttachments: hasAttachments,
        );

        await _emailsBox.put(localId, jsonEncode(cachedEmail.toJson()));
      }
    }
  }

  Future<void> markFlags(String accountId, String emailId, {bool? isRead, bool? isFavorite}) async {
    await init();
    final emailJson = _emailsBox.get(emailId);
    if (emailJson == null) return;

    var email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);
    email = email.copyWith(isRead: isRead, isFavorite: isFavorite);
    await _emailsBox.put(emailId, jsonEncode(email.toJson()));

    // Sync to server in background
    try {
      final account = await getAccount(accountId);
      if (account == null || !account.enabled) return;

      final client = await _getClientForAccount(account);
      await _selectMailbox(client, email.folder);

      final seq = MessageSequence(isUidSequence: true);
      seq.add(email.uid);

      if (isRead != null) {
        if (isRead) {
          await client.markSeen(seq);
        } else {
          await client.markUnseen(seq);
        }
      }

      if (isFavorite != null) {
        if (isFavorite) {
          await client.markFlagged(seq);
        } else {
          await client.markUnflagged(seq);
        }
      }
    } catch (e) {
      _log.warning('Failed to sync flags to mail server: $e');
    }
  }

  Future<void> moveEmail(String accountId, String emailId, String targetFolder) async {
    await init();
    final emailJson = _emailsBox.get(emailId);
    if (emailJson == null) return;

    final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);

    try {
      final account = await getAccount(accountId);
      if (account == null || !account.enabled) return;

      final client = await _getClientForAccount(account);
      await _selectMailbox(client, email.folder);

      MailboxFlag? specialFlag;
      if (targetFolder.toLowerCase() == 'trash') {
        specialFlag = MailboxFlag.trash;
      } else if (targetFolder.toLowerCase() == 'archive') {
        specialFlag = MailboxFlag.archive;
      } else if (targetFolder.toLowerCase() == 'junk' || targetFolder.toLowerCase() == 'spam') {
        specialFlag = MailboxFlag.junk;
      } else if (targetFolder.toLowerCase() == 'sent') {
        specialFlag = MailboxFlag.sent;
      } else if (targetFolder.toLowerCase() == 'drafts') {
        specialFlag = MailboxFlag.drafts;
      }

      final mailboxes = await client.listMailboxes();
      Mailbox? targetMailbox;

      for (final m in mailboxes) {
        if (m.path.toLowerCase() == targetFolder.toLowerCase()) {
          targetMailbox = m;
          break;
        }
      }

      if (targetMailbox == null && specialFlag != null) {
        for (final m in mailboxes) {
          if (m.hasFlag(specialFlag)) {
            targetMailbox = m;
            break;
          }
        }
      }

      if (targetMailbox == null && targetFolder.toLowerCase() == 'trash') {
        for (final m in mailboxes) {
          final pathLower = m.path.toLowerCase();
          if (pathLower.contains('trash') || 
              pathLower.contains('papierkorb') || 
              pathLower.contains('deleted')) {
            targetMailbox = m;
            break;
          }
        }
      }

      if (targetMailbox == null) {
        throw Exception('Target folder $targetFolder not found on server.');
      }

      final seq = MessageSequence(isUidSequence: true);
      seq.add(email.uid);
      await client.moveMessages(seq, targetMailbox);

      // Expunge the source mailbox to ensure the moved message is removed from the source folder on the server
      final lowlevelClient = client.lowLevelIncomingMailClient;
      if (lowlevelClient is ImapClient) {
        await lowlevelClient.expunge();
      }

      // Locally delete from cache (since it moved folders) and let sync fetch it in the new folder
      await _emailsBox.delete(emailId);

      final targetPath = targetMailbox.path;
      // Trigger background sync for the target folder so the counts update correctly
      syncMailbox(accountId, folder: targetPath, count: 20).catchError((e) {
        _log.warning('Failed to sync target folder $targetPath after move: $e');
      });
    } catch (e) {
      _log.warning('Failed to move email on server: $e');
      // Update folder path locally anyway as fallback
      final updated = email.copyWith(folder: targetFolder);
      await _emailsBox.put(emailId, jsonEncode(updated.toJson()));
    }
  }

  Future<void> sendEmail(
    String accountId, {
    required String to,
    required String subject,
    required String bodyMarkdown,
    List<String>? attachmentPaths,
  }) async {
    await init();
    final account = await getAccount(accountId);
    if (account == null || !account.enabled) {
      throw Exception('Email account not found or disabled.');
    }

    final client = await _getClientForAccount(account);
    final builder = MessageBuilder.prepareMultipartAlternativeMessage(
      plainText: bodyMarkdown,
      htmlText: _markdownToHtml(bodyMarkdown),
    )
      ..from = [MailAddress(account.name, account.email)]
      ..to = [MailAddress('', to)]
      ..subject = subject;

    if (attachmentPaths != null) {
      for (final path in attachmentPaths) {
        final file = File(path);
        if (file.existsSync()) {
          final fileName = p.basename(path);
          final bytes = await file.readAsBytes();
          builder.addBinary(bytes, _getMediaType(fileName), filename: fileName);
        }
      }
    }

    final mimeMessage = builder.buildMimeMessage();
    await client.sendMessage(mimeMessage);

    // Save to Sent folder on IMAP in background
    try {
      await client.appendMessageToFlag(mimeMessage, MailboxFlag.sent, flags: ['\\Seen']);
    } catch (e) {
      _log.warning('Failed to save sent message to Sent folder: $e');
    }
  }

  Future<String> downloadAttachment(String accountId, String emailId, String fileName) async {
    await init();
    final emailJson = _emailsBox.get(emailId);
    if (emailJson == null) {
      throw Exception('Email not found in local cache: $emailId');
    }
    final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);
    
    final localPath = p.join(stateDir, 'mail-attachments', '${email.id}_$fileName');
    final localFile = File(localPath);
    if (localFile.existsSync()) {
      return localPath;
    }

    final account = await getAccount(accountId);
    if (account == null) {
      throw Exception('Email account not found: $accountId');
    }

    final client = await _getClientForAccount(account);
    await _selectMailbox(client, email.folder);

    final seq = MessageSequence(isUidSequence: true);
    seq.add(email.uid);
    final messages = await client.fetchMessageSequence(seq, fetchPreference: FetchPreference.fullWhenWithinSize);
    if (messages.isEmpty) {
      throw Exception('Failed to fetch email from server.');
    }

    final message = messages.first;
    final contentInfos = message.findContentInfo();
    for (final contentInfo in contentInfos) {
      if (contentInfo.fileName == fileName) {
        final part = message.getPart(contentInfo.fetchId);
        if (part != null) {
          final bytes = part.decodeContentBinary();
          if (bytes != null) {
            await localFile.writeAsBytes(bytes);
            return localPath;
          }
        }
      }
    }
    throw Exception('Attachment $fileName not found in email.');
  }

  Future<List<String>> getAttachmentNames(String accountId, String emailId) async {
    await init();
    final emailJson = _emailsBox.get(emailId);
    if (emailJson == null) return [];
    final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);
    if (!email.hasAttachments) return [];

    try {
      final account = await getAccount(accountId);
      if (account == null) return [];

      final client = await _getClientForAccount(account);
      await _selectMailbox(client, email.folder);

      final seq = MessageSequence(isUidSequence: true);
      seq.add(email.uid);
      final messages = await client.fetchMessageSequence(seq, fetchPreference: FetchPreference.fullWhenWithinSize);
      if (messages.isEmpty) return [];

      final message = messages.first;
      return message.findContentInfo().map((c) => c.fileName ?? 'attachment_${c.fetchId}').toList();
    } catch (e) {
      _log.warning('Failed to fetch attachment names: $e');
      return [];
    }
  }

  Future<void> emptyFolder(String accountId, String folder) async {
    await init();
    try {
      final account = await getAccount(accountId);
      if (account == null || !account.enabled) return;

      final client = await _getClientForAccount(account);
      final mailboxes = await client.listMailboxes();
      Mailbox? targetMailbox;

      for (final m in mailboxes) {
        if (m.path.toLowerCase() == folder.toLowerCase()) {
          targetMailbox = m;
          break;
        }
      }

      // Fallback for Trash
      if (targetMailbox == null && folder.toLowerCase() == 'trash') {
        for (final m in mailboxes) {
          if (m.hasFlag(MailboxFlag.trash)) {
            targetMailbox = m;
            break;
          }
        }
      }

      if (targetMailbox == null && folder.toLowerCase() == 'trash') {
        for (final m in mailboxes) {
          final pathLower = m.path.toLowerCase();
          if (pathLower.contains('trash') || 
              pathLower.contains('papierkorb') || 
              pathLower.contains('deleted')) {
            targetMailbox = m;
            break;
          }
        }
      }

      if (targetMailbox == null) {
        throw Exception('Target folder $folder not found on server.');
      }

      await client.selectMailbox(targetMailbox);
      await client.deleteAllMessages(targetMailbox, expunge: true);

      // Locally delete all cached emails from this folder
      final keysToDelete = <String>[];
      for (final key in _emailsBox.keys) {
        try {
          final emailJson = _emailsBox.get(key);
          if (emailJson != null) {
            final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);
            if (email.accountId == accountId && email.folder.toLowerCase() == targetMailbox.path.toLowerCase()) {
              keysToDelete.add(key as String);
            }
          }
        } catch (_) {}
      }

      if (keysToDelete.isNotEmpty) {
        await _emailsBox.deleteAll(keysToDelete);
      }
    } catch (e) {
      _log.warning('Failed to empty folder $folder: $e');
      rethrow;
    }
  }

  Future<void> deleteEmailPermanently(String accountId, String emailId) async {
    await init();
    final emailJson = _emailsBox.get(emailId);
    if (emailJson == null) return;

    final email = CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>);

    try {
      final account = await getAccount(accountId);
      if (account == null || !account.enabled) return;

      final client = await _getClientForAccount(account);
      await _selectMailbox(client, email.folder);

      final seq = MessageSequence(isUidSequence: true);
      seq.add(email.uid);
      
      final lowlevelClient = client.lowLevelIncomingMailClient;
      if (lowlevelClient is ImapClient) {
        if (seq.isUidSequence) {
          await lowlevelClient.uidStore(seq, [MessageFlags.deleted]);
        } else {
          await lowlevelClient.store(seq, [MessageFlags.deleted]);
        }
        await lowlevelClient.expunge();
      } else {
        await client.deleteMessages(seq, expunge: true);
      }

      // Locally delete from cache
      await _emailsBox.delete(emailId);
    } catch (e) {
      _log.warning('Failed to permanently delete email $emailId: $e');
      // Delete locally anyway as fallback
      await _emailsBox.delete(emailId);
      rethrow;
    }
  }

  Future<void> moveEmails(String accountId, List<String> emailIds, String targetFolder) async {
    await init();
    try {
      final account = await getAccount(accountId);
      if (account == null || !account.enabled) return;

      final client = await _getClientForAccount(account);
      final mailboxes = await client.listMailboxes();
      Mailbox? targetMailbox;

      for (final m in mailboxes) {
        if (m.path.toLowerCase() == targetFolder.toLowerCase()) {
          targetMailbox = m;
          break;
        }
      }

      MailboxFlag? specialFlag;
      if (targetFolder.toLowerCase() == 'trash') {
        specialFlag = MailboxFlag.trash;
      } else if (targetFolder.toLowerCase() == 'archive') {
        specialFlag = MailboxFlag.archive;
      } else if (targetFolder.toLowerCase() == 'junk' || targetFolder.toLowerCase() == 'spam') {
        specialFlag = MailboxFlag.junk;
      }

      if (targetMailbox == null && specialFlag != null) {
        for (final m in mailboxes) {
          if (m.hasFlag(specialFlag)) {
            targetMailbox = m;
            break;
          }
        }
      }

      if (targetMailbox == null && targetFolder.toLowerCase() == 'trash') {
        for (final m in mailboxes) {
          final pathLower = m.path.toLowerCase();
          if (pathLower.contains('trash') || 
              pathLower.contains('papierkorb') || 
              pathLower.contains('deleted')) {
            targetMailbox = m;
            break;
          }
        }
      }

      if (targetMailbox == null) {
        throw Exception('Target folder $targetFolder not found on server.');
      }

      // Group emails by their current folders
      final emailsToMove = <CachedEmail>[];
      for (final id in emailIds) {
        final emailJson = _emailsBox.get(id);
        if (emailJson != null) {
          emailsToMove.add(CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>));
        }
      }

      final groupedByFolder = <String, List<CachedEmail>>{};
      for (final email in emailsToMove) {
        groupedByFolder.putIfAbsent(email.folder, () => []).add(email);
      }

      for (final entry in groupedByFolder.entries) {
        final sourceFolder = entry.key;
        final folderEmails = entry.value;

        await _selectMailbox(client, sourceFolder);

        final seq = MessageSequence(isUidSequence: true);
        for (final email in folderEmails) {
          seq.add(email.uid);
        }

        await client.moveMessages(seq, targetMailbox);

        final lowlevelClient = client.lowLevelIncomingMailClient;
        if (lowlevelClient is ImapClient) {
          await lowlevelClient.expunge();
        }

        for (final email in folderEmails) {
          await _emailsBox.delete(email.id);
        }
      }

      // Sync target folder
      syncMailbox(accountId, folder: targetMailbox.path, count: 20).catchError((e) {
        _log.warning('Failed to sync target folder ${targetMailbox?.path} after move: $e');
      });
    } catch (e) {
      _log.warning('Failed to move batch of emails: $e');
      rethrow;
    }
  }

  Future<void> deleteEmailsPermanently(String accountId, List<String> emailIds) async {
    await init();
    try {
      final account = await getAccount(accountId);
      if (account == null || !account.enabled) return;

      final client = await _getClientForAccount(account);

      final emailsToDelete = <CachedEmail>[];
      for (final id in emailIds) {
        final emailJson = _emailsBox.get(id);
        if (emailJson != null) {
          emailsToDelete.add(CachedEmail.fromJson(jsonDecode(emailJson) as Map<String, dynamic>));
        }
      }

      final groupedByFolder = <String, List<CachedEmail>>{};
      for (final email in emailsToDelete) {
        groupedByFolder.putIfAbsent(email.folder, () => []).add(email);
      }

      for (final entry in groupedByFolder.entries) {
        final sourceFolder = entry.key;
        final folderEmails = entry.value;

        await _selectMailbox(client, sourceFolder);

        final seq = MessageSequence(isUidSequence: true);
        for (final email in folderEmails) {
          seq.add(email.uid);
        }

        final lowlevelClient = client.lowLevelIncomingMailClient;
        if (lowlevelClient is ImapClient) {
          if (seq.isUidSequence) {
            await lowlevelClient.uidStore(seq, [MessageFlags.deleted]);
          } else {
            await lowlevelClient.store(seq, [MessageFlags.deleted]);
          }
          await lowlevelClient.expunge();
        } else {
          await client.deleteMessages(seq, expunge: true);
        }

        for (final email in folderEmails) {
          await _emailsBox.delete(email.id);
        }
      }
    } catch (e) {
      _log.warning('Failed to permanently delete batch of emails: $e');
      rethrow;
    }
  }

  // Helpers
  String _formatAddresses(List<MailAddress>? addresses) {
    if (addresses == null) return '';
    return addresses.map((a) {
      if (a.personalName != null && a.personalName!.isNotEmpty) {
        return '${a.personalName} <${a.email}>';
      }
      return a.email;
    }).join(', ');
  }

  MediaType _getMediaType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return MediaSubtype.applicationPdf.mediaType;
      case '.jpg':
      case '.jpeg':
        return MediaSubtype.imageJpeg.mediaType;
      case '.png':
        return MediaSubtype.imagePng.mediaType;
      case '.gif':
        return MediaSubtype.imageGif.mediaType;
      case '.txt':
        return MediaSubtype.textPlain.mediaType;
      case '.html':
        return MediaSubtype.textHtml.mediaType;
      case '.zip':
        return MediaSubtype.applicationZip.mediaType;
      default:
        return MediaSubtype.applicationOctetStream.mediaType;
    }
  }

  String _markdownToHtml(String markdown) {
    var html = markdown
        .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => '<strong>${m[1]}</strong>')
        .replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => '<em>${m[1]}</em>')
        .replaceAllMapped(RegExp(r'^-\s+(.*?)$', multiLine: true), (m) => '<li>${m[1]}</li>')
        .replaceAll('\n', '<br>');
    
    if (html.contains('<li>')) {
      html = '<ul>$html</ul>'.replaceAll('</ul><br><ul>', '').replaceAll('<br><li>', '<li>');
    }
    return html;
  }
}
