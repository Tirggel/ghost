import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/app_snackbar.dart';
import 'email_composer.dart';

class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  List<dynamic> _accounts = [];
  String? _selectedAccountId;

  // Folders keyed by accountId — supports multiple accounts simultaneously
  final Map<String, List<dynamic>> _foldersByAccount = {};
  // Accounts whose folder list is collapsed in the sidebar
  final Set<String> _collapsedAccounts = {};

  String _selectedFolder = 'INBOX';

  List<dynamic> _emails = [];
  String? _selectedEmailId;
  Map<String, dynamic>? _selectedEmail;
  final Set<String> _selectedEmailIds = {};
  int _emailsLimit = 50;

  bool _isLoadingFolders = false;
  bool _isLoadingEmails = false;
  bool _isSyncing = false;

  final _searchController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _broadcastSub;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _setupBroadcastListener();
    _searchController.addListener(() {
      _loadEmails();
    });
  }

  @override
  void dispose() {
    _broadcastSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setupBroadcastListener() {
    _broadcastSub = ref.read(gatewayClientProvider).messages.listen((msg) {
      final method = msg['method'] as String?;
      if (method == 'email.changed' || method == 'email.accountsChanged') {
        _loadAccounts(silent: true);
        if (_selectedAccountId != null) {
          _loadFolders(silent: true);
          _loadEmails(silent: true);
        }
      }
    });
  }

  Future<void> _loadAccounts({bool silent = false}) async {
    try {
      final response = await ref.read(gatewayClientProvider).call('email.listAccounts', {});
      if (response != null && response['accounts'] != null) {
        final accounts = response['accounts'] as List<dynamic>;
        setState(() {
          _accounts = accounts;
          if (_selectedAccountId == null && accounts.isNotEmpty) {
            _selectedAccountId = accounts.first['id'] as String;
          }
        });
        // Load folders for ALL accounts so the sidebar is always fully populated
        await _loadFolders(silent: silent);
        await _loadEmails(silent: silent);
      }
    } catch (e) {
      AppSnackBar.showError(context, 'Failed to load email accounts: $e');
    }
  }

  // Returns a short display label from a raw IMAP folder path.
  // e.g. "[Gmail]/Alle Nachrichten" → "Alle Nachrichten"
  String _folderDisplayName(String path) {
    final last = path.split('/').last;
    return last.toUpperCase();
  }

  // Priority order for the fixed sub-folder list (matched against display name).
  static const _folderOrder = [
    'INBOX',
    'GESENDET',
    'SENT',
    'ALLE NACHRICHTEN',
    'ALL MAIL',
    'PAPIERKORB',
    'TRASH',
    'DELETED',
    'SPAM',
    'JUNK',
  ];

  // Load folders for every account and store them in _foldersByAccount
  Future<void> _loadFolders({bool silent = false}) async {
    if (_accounts.isEmpty) return;
    if (!silent) setState(() => _isLoadingFolders = true);
    try {
      for (final acc in _accounts) {
        final accountId = acc['id'] as String;
        try {
          final response = await ref.read(gatewayClientProvider).call('email.listFolders', {
            'accountId': accountId,
          });
          if (response != null && response['folders'] != null) {
            final rawFolders = response['folders'] as List<dynamic>;
            final wanted = rawFolders.where((f) {
              final display = _folderDisplayName(f['name'] as String? ?? '').toUpperCase();
              return _folderOrder.contains(display);
            }).toList();
            wanted.sort((a, b) {
              final da = _folderDisplayName(a['name'] as String? ?? '').toUpperCase();
              final db = _folderDisplayName(b['name'] as String? ?? '').toUpperCase();
              final ia = _folderOrder.indexWhere((o) => da.contains(o));
              final ib = _folderOrder.indexWhere((o) => db.contains(o));
              return ia.compareTo(ib);
            });
            setState(() {
              _foldersByAccount[accountId] = wanted;
            });
          }
        } catch (_) {}
      }
    } finally {
      if (!silent) setState(() => _isLoadingFolders = false);
    }
  }


  Future<void> _loadEmails({bool silent = false}) async {
    if (_selectedAccountId == null) return;
    if (!silent) setState(() => _isLoadingEmails = true);
    try {
      final filterText = _searchController.text.trim();
      final response = await ref.read(gatewayClientProvider).call('email.listEmails', {
        'accountId': _selectedAccountId,
        'folder': _selectedFolder,
        'limit': _emailsLimit,
        'filter': filterText.isNotEmpty ? filterText : null,
      });
      if (response != null && response['emails'] != null) {
        final emails = response['emails'] as List<dynamic>;
        setState(() {
          _emails = emails;
          if (_selectedEmailId != null) {
            final found = emails.firstWhere((e) => e['id'] == _selectedEmailId, orElse: () => null);
            if (found != null) {
              _selectedEmail = found as Map<String, dynamic>;
            } else {
              _selectedEmailId = null;
              _selectedEmail = null;
            }
          }
        });
      }
    } catch (e) {
      AppSnackBar.showError(context, 'Failed to load emails: $e');
    } finally {
      if (!silent) setState(() => _isLoadingEmails = false);
    }
  }

  Future<void> _syncMailbox({int? count}) async {
    if (_selectedAccountId == null) return;
    setState(() => _isSyncing = true);
    AppSnackBar.show(context, 'email.syncing_mailbox'.tr(), icon: Icons.info_outline);
    try {
      // RPC now awaits the sync completion before returning — no delay needed.
      await ref.read(gatewayClientProvider).call('email.triggerScan', {
        'accountId': _selectedAccountId,
        'folder': _selectedFolder,
        'count': count ?? _emailsLimit,
      });
      await _loadEmails(silent: true);
      await _loadFolders(silent: true);
    } catch (e) {
      AppSnackBar.showError(context, 'email.failed_sync'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _markFlags({bool? isRead, bool? isFavorite}) async {
    if (_selectedAccountId == null || _selectedEmail == null) return;
    final emailId = _selectedEmail!['id'] as String;
    try {
      await ref.read(gatewayClientProvider).call('email.markFlags', {
        'accountId': _selectedAccountId,
        'emailId': emailId,
        if (isRead != null) 'isRead': isRead,
        if (isFavorite != null) 'isFavorite': isFavorite,
      });
      
      // Update local state
      setState(() {
        if (_selectedEmail != null) {
          if (isRead != null) _selectedEmail!['isRead'] = isRead;
          if (isFavorite != null) _selectedEmail!['isFavorite'] = isFavorite;
        }
      });
      _loadEmails(silent: true);
    } catch (e) {
      AppSnackBar.showError(context, 'email.failed_update_flags'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _moveEmail(String targetFolder) async {
    if (_selectedAccountId == null || _selectedEmail == null) return;
    final emailId = _selectedEmail!['id'] as String;
    try {
      await ref.read(gatewayClientProvider).call('email.moveEmail', {
        'accountId': _selectedAccountId,
        'emailId': emailId,
        'targetFolder': targetFolder,
      });
      AppSnackBar.showSuccess(context, 'email.email_moved_success'.tr(namedArgs: {'folder': targetFolder}));
      setState(() {
        _selectedEmailId = null;
        _selectedEmail = null;
      });
      await _loadEmails();
      await _loadFolders(silent: true);
    } catch (e) {
      AppSnackBar.showError(context, 'email.failed_move_email'.tr(namedArgs: {'error': e.toString()}));
    }
  }



  Future<void> _deleteEmailPermanently() async {
    if (_selectedAccountId == null || _selectedEmail == null) return;
    final emailId = _selectedEmail!['id'] as String;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('email.delete_permanent_confirm_title'.tr().toUpperCase(), style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        content: Text('email.delete_permanent_confirm_msg'.tr(), style: const TextStyle(color: AppColors.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('email.cancel'.tr().toUpperCase(), style: const TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('email.delete'.tr().toUpperCase(), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(gatewayClientProvider).call('email.deleteEmailPermanently', {
        'accountId': _selectedAccountId,
        'emailId': emailId,
      });
      AppSnackBar.showSuccess(context, 'email.delete_permanent_success'.tr());
      setState(() {
        _selectedEmailId = null;
        _selectedEmail = null;
      });
      await _loadEmails();
      await _loadFolders(silent: true);
    } catch (e) {
      AppSnackBar.showError(context, 'email.failed_delete_permanent'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _batchMove(String targetFolder) async {
    if (_selectedAccountId == null || _selectedEmailIds.isEmpty) return;

    setState(() => _isLoadingEmails = true);
    try {
      final count = _selectedEmailIds.length;
      await ref.read(gatewayClientProvider).call('email.moveEmails', {
        'accountId': _selectedAccountId,
        'emailIds': _selectedEmailIds.toList(),
        'targetFolder': targetFolder,
      });
      AppSnackBar.showSuccess(context, 'email.batch_move_success'.tr(namedArgs: {'count': count.toString(), 'folder': targetFolder}));
      setState(() {
        _selectedEmailIds.clear();
        _selectedEmailId = null;
        _selectedEmail = null;
      });
      await _loadEmails();
      await _loadFolders(silent: true);
    } catch (e) {
      AppSnackBar.showError(context, 'email.failed_move_email'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      setState(() => _isLoadingEmails = false);
    }
  }

  Future<void> _batchDeletePermanently() async {
    if (_selectedAccountId == null || _selectedEmailIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('email.batch_delete_confirm_title'.tr().toUpperCase(), style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        content: Text('email.batch_delete_confirm_msg'.tr(namedArgs: {'count': _selectedEmailIds.length.toString()}), style: const TextStyle(color: AppColors.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('email.cancel'.tr().toUpperCase(), style: const TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('email.delete'.tr().toUpperCase(), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoadingEmails = true);
    try {
      final count = _selectedEmailIds.length;
      await ref.read(gatewayClientProvider).call('email.deleteEmailsPermanently', {
        'accountId': _selectedAccountId,
        'emailIds': _selectedEmailIds.toList(),
      });
      AppSnackBar.showSuccess(context, 'email.batch_delete_success'.tr(namedArgs: {'count': count.toString()}));
      setState(() {
        _selectedEmailIds.clear();
        _selectedEmailId = null;
        _selectedEmail = null;
      });
      await _loadEmails();
      await _loadFolders(silent: true);
    } catch (e) {
      AppSnackBar.showError(context, 'email.failed_delete_permanent'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      setState(() => _isLoadingEmails = false);
    }
  }

  Future<void> _downloadAttachment(String fileName) async {
    if (_selectedAccountId == null || _selectedEmail == null) return;
    final emailId = _selectedEmail!['id'] as String;
    AppSnackBar.show(context, 'email.downloading_attachment'.tr(), icon: Icons.info_outline);
    try {
      final response = await ref.read(gatewayClientProvider).call('email.downloadAttachment', {
        'accountId': _selectedAccountId,
        'emailId': emailId,
        'fileName': fileName,
      });
      if (response != null && response['path'] != null) {
        if (mounted) {
          AppSnackBar.showSuccess(context, 'email.downloaded_to'.tr(namedArgs: {'path': response['path'].toString()}));
        }
      }
    } catch (e) {
      AppSnackBar.showError(context, 'email.download_failed'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  void _openComposer({String? replyToEmail, String? replySubject, String? initialBody, String? emailId}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmailComposer(
        accountId: _selectedAccountId!,
        to: replyToEmail,
        subject: replySubject,
        initialBody: initialBody,
        emailId: emailId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Pane (Accounts & Folders)
          _buildLeftPane(),
          // Fine vertical border
          const VerticalDivider(width: 1, color: AppColors.border, thickness: 1),
          // Middle Pane (Email List)
          Expanded(
            flex: 2,
            child: _buildMiddlePane(),
          ),
          // Fine vertical border
          const VerticalDivider(width: 1, color: AppColors.border, thickness: 1),
          // Right Pane (Email Detail)
          Expanded(
            flex: 3,
            child: _buildRightPane(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPane() {
    return SizedBox(
      width: 260,
      child: Material(
        color: AppColors.pureBlack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compose Button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ElevatedButton.icon(
                onPressed: _selectedAccountId != null ? () => _openComposer() : null,
                icon: const Icon(Icons.edit_note, size: 20),
                label: Text('email.compose'.tr().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

            const Divider(color: AppColors.border, height: 16),

            // Multi-account collapsible folder tree
            Expanded(
              child: _isLoadingFolders && _foldersByAccount.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _buildFolderTree(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderTree() {
    Widget buildFolderTile(Map<String, dynamic> f, String accountId, {bool isSub = false}) {
      final path = f['name'] as String;
      final display = _folderDisplayName(path);
      final totalCount = f['totalCount'] as int? ?? 0;
      final isSelected = _selectedAccountId == accountId && _selectedFolder == path;

      IconData icon = Icons.folder_open_outlined;
      final d = display.toUpperCase();
      if (d == 'INBOX') icon = Icons.inbox_outlined;
      if (d.contains('SENT') || d.contains('GESENDET')) icon = Icons.send_outlined;
      if (d.contains('ALLE') || d.contains('ALL MAIL')) icon = Icons.all_inbox_outlined;
      if (d.contains('TRASH') || d.contains('DELETE') || d.contains('PAPIERKORB')) icon = Icons.delete_outline_outlined;
      if (d.contains('SPAM') || d.contains('JUNK')) icon = Icons.report_gmailerrorred_outlined;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedAccountId = accountId;
              _selectedFolder = path;
              _selectedEmailId = null;
              _selectedEmail = null;
              _emailsLimit = 50;
            });
            _loadEmails();
            _syncMailbox();
          },
          child: Container(
            color: isSelected ? AppColors.surface : Colors.transparent,
            padding: EdgeInsets.only(
              left: isSub ? 36 : 16,
              right: 12,
              top: 9,
              bottom: 9,
            ),
            child: Row(
              children: [
                if (isSub) const SizedBox(width: 4),
                Icon(icon, size: 16, color: isSelected ? AppColors.primary : AppColors.textDim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    display,
                    style: TextStyle(
                      color: isSelected ? AppColors.textMain : AppColors.textDim,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
                      fontSize: isSub ? 12 : 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (totalCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: const BoxDecoration(color: AppColors.primary),
                    child: Text(
                      totalCount.toString(),
                      style: const TextStyle(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final items = <Widget>[];

    for (int i = 0; i < _accounts.length; i++) {
      final acc = _accounts[i] as Map<String, dynamic>;
      final accountId = acc['id'] as String;
      final accountName = acc['name'] as String? ?? '';
      final accountEmail = acc['email'] as String? ?? '';
      final isCollapsed = _collapsedAccounts.contains(accountId);
      final folders = _foldersByAccount[accountId] ?? [];
      final inboxFolders = folders.where((f) => !(f['name'] as String).contains('/')).toList();
      final subFolders = folders.where((f) => (f['name'] as String).contains('/')).toList();

      // Separator between accounts
      if (i > 0) {
        items.add(const Divider(color: AppColors.border, height: 1, thickness: 1));
        items.add(const SizedBox(height: 4));
      }

      // Account header — shows name + email, tap to expand/collapse
      items.add(
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() {
              if (isCollapsed) {
                _collapsedAccounts.remove(accountId);
              } else {
                _collapsedAccounts.add(accountId);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isCollapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 18,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          accountName.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          accountEmail,
                          style: TextStyle(
                            color: AppColors.textDim.withAlpha(180),
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (!isCollapsed) {
        // INBOX and top-level
        for (final f in inboxFolders) {
          items.add(buildFolderTile(f as Map<String, dynamic>, accountId));
        }
        // Sub-folders
        if (subFolders.isNotEmpty) {
          items.add(
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 12, top: 6, bottom: 2),
              child: Text(
                'ORDNER',
                style: TextStyle(
                  color: AppColors.textDim.withAlpha(120),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          );
          for (final f in subFolders) {
            items.add(buildFolderTile(f as Map<String, dynamic>, accountId, isSub: true));
          }
        }
        items.add(const SizedBox(height: 4));
      }
    }

    if (items.isEmpty) {
      return const Center(
        child: Text('Keine Konten', style: TextStyle(color: AppColors.textDim)),
      );
    }

    return ListView(children: items);
  }

  Widget _buildMiddlePane() {
    final folderUpper = _selectedFolder.toUpperCase();
    final isTrashFolder = folderUpper.contains('TRASH') ||
        folderUpper.contains('DELETE') ||
        folderUpper.contains('PAPIERKORB');

    return Column(
      children: [
        // Search & Refresh bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.textMain),
                  decoration: InputDecoration(
                    hintText: 'email.search_placeholder'.tr(),
                    hintStyle: const TextStyle(color: AppColors.textDim),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textDim),
                    filled: true,
                    fillColor: AppColors.pureBlack,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.border)),
                    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.primary)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),

              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
                child: _isSyncing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.sync, color: AppColors.textMain),
                        onPressed: _syncMailbox,
                        tooltip: 'email.title'.tr(), // Sync mailbox tooltip
                      ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.pureBlack,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _emails.isNotEmpty && _selectedEmailIds.length == _emails.length,
                  activeColor: AppColors.primary,
                  checkColor: AppColors.background,
                  onChanged: _emails.isEmpty
                      ? null
                      : (val) {
                          setState(() {
                            if (val == true) {
                              _selectedEmailIds.addAll(_emails.map((e) => e['id'] as String));
                            } else {
                              _selectedEmailIds.clear();
                            }
                          });
                        },
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedEmailIds.isEmpty
                      ? _selectedFolder.toUpperCase()
                      : 'settings.common.selected_count'.tr(namedArgs: {'count': _selectedEmailIds.length.toString()}),
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                if (_selectedEmailIds.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.archive_outlined, color: AppColors.textMain, size: 20),
                    onPressed: () => _batchMove('Archive'),
                    tooltip: 'email.archive'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                    onPressed: isTrashFolder ? _batchDeletePermanently : () => _batchMove('Trash'),
                    tooltip: 'email.delete'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMain, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedEmailIds.clear();
                      });
                    },
                    tooltip: 'email.cancel'.tr(),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // Emails List
        Expanded(
          child: _isLoadingEmails
              ? const Center(child: CircularProgressIndicator())
              : _emails.isEmpty
                  ? Center(child: Text('email.no_emails'.tr(namedArgs: {'folder': _selectedFolder}), style: const TextStyle(color: AppColors.textDim)))
                  : ListView.builder(
                      itemCount: _emails.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _emails.length) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: AppColors.border)),
                            ),
                            child: Center(
                              child: TextButton.icon(
                                onPressed: _isSyncing
                                    ? null
                                    : () {
                                        setState(() {
                                          _emailsLimit += 50;
                                        });
                                        _loadEmails();
                                        _syncMailbox();
                                      },
                                icon: _isSyncing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.expand_more, size: 16, color: AppColors.primary),
                                label: Text(
                                  'email.load_more'.tr().toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final email = _emails[index] as Map<String, dynamic>;
                        final id = email['id'] as String;
                        final isSelected = _selectedEmailId == id;
                        final isRead = email['isRead'] as bool? ?? false;
                        final isFavorite = email['isFavorite'] as bool? ?? false;
                        final summary = email['summary'] as String? ?? '';
                        final tags = (email['tags'] as List<dynamic>?)?.cast<String>() ?? [];
                        final urgency = email['urgency'] as String? ?? 'none';

                        return Container(
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border)),
                          ),
                          child: ListTile(
                            selected: isSelected,
                            selectedTileColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Checkbox(
                              value: _selectedEmailIds.contains(id),
                              activeColor: AppColors.primary,
                              checkColor: AppColors.background,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedEmailIds.add(id);
                                  } else {
                                    _selectedEmailIds.remove(id);
                                  }
                                });
                              },
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    email['sender'] as String? ?? '',
                                    style: TextStyle(
                                      color: isRead ? AppColors.textMain : AppColors.primary,
                                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isFavorite)
                                  const Icon(Icons.star, color: Colors.amber, size: 16)
                                else if (!isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  email['subject'] as String? ?? '(No Subject)',
                                  style: TextStyle(
                                    color: AppColors.textMain,
                                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (summary.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    summary,
                                    style: const TextStyle(
                                      color: AppColors.textDim,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (tags.isNotEmpty || urgency != 'none') ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      if (urgency != 'none' && urgency != 'low')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          color: urgency == 'critical' || urgency == 'high' ? AppColors.error : Colors.amber,
                                          child: Text(
                                            urgency.toUpperCase(),
                                            style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ...tags.map((t) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            color: AppColors.border,
                                            child: Text(
                                              t.toUpperCase(),
                                              style: const TextStyle(color: AppColors.textMain, fontSize: 9),
                                            ),
                                          )),
                                    ],
                                  )
                                ]
                              ],
                            ),
                            onTap: () {
                              setState(() {
                                _selectedEmailId = id;
                                _selectedEmail = email;
                              });
                              if (!isRead) {
                                _markFlags(isRead: true);
                              }
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRightPane() {
    if (_selectedEmail == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mail_outline, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            Text(
              'email.select_email'.tr().toUpperCase(),
              style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ],
        ),
      );
    }

    final email = _selectedEmail!;
    final subject = email['subject'] as String? ?? '(No Subject)';
    final sender = email['sender'] as String? ?? '';
    final to = email['to'] as String? ?? '';
    final dateStr = email['date'] as String? ?? '';
    final formattedDate = dateStr.isNotEmpty ? DateTime.parse(dateStr).toLocal().toString().substring(0, 16) : '';
    final isRead = email['isRead'] as bool? ?? false;
    final isFavorite = email['isFavorite'] as bool? ?? false;
    final bodyText = email['bodyText'] as String? ?? '';
    final summary = email['summary'] as String? ?? '';
    final urgency = email['urgency'] as String? ?? 'none';
    final urgencyReason = email['urgencyReason'] as String? ?? '';
    final tags = (email['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final aiReplyDraft = email['aiReplyDraft'] as String? ?? '';
    final hasAttachments = email['hasAttachments'] as bool? ?? false;
    final spamVerdict = email['spamVerdict'] as bool? ?? false;
    final spamReason = email['spamReason'] as String? ?? '';
    final folderUpper = _selectedFolder.toUpperCase();
    final isTrashFolder = folderUpper.contains('TRASH') ||
        folderUpper.contains('DELETE') ||
        folderUpper.contains('PAPIERKORB');

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined, color: AppColors.textMain),
                  onPressed: () => _markFlags(isRead: !isRead),
                  tooltip: isRead ? 'email.mark_unread'.tr() : 'email.mark_read'.tr(),
                ),
                IconButton(
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border, color: isFavorite ? Colors.amber : AppColors.textMain),
                  onPressed: () => _markFlags(isFavorite: !isFavorite),
                  tooltip: isFavorite ? 'email.remove_star'.tr() : 'email.star_message'.tr(),
                ),
                const SizedBox(width: 8),
                const VerticalDivider(width: 1, color: AppColors.border),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.reply_outlined, color: AppColors.textMain),
                  onPressed: () => _openComposer(
                    replyToEmail: sender,
                    replySubject: 'Re: $subject',
                    emailId: _selectedEmail!['id'] as String?,
                  ),
                  tooltip: 'email.reply'.tr(),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined, color: AppColors.textMain),
                  onPressed: () => _moveEmail('Archive'),
                  tooltip: 'email.archive'.tr(),
                ),
                if (isTrashFolder) ...[
                  IconButton(
                    icon: const Icon(Icons.restore_from_trash_outlined, color: AppColors.textMain),
                    onPressed: () => _moveEmail('INBOX'),
                    tooltip: 'email.restore'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: _deleteEmailPermanently,
                    tooltip: 'email.delete'.tr(),
                  ),
                ] else
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () => _moveEmail('Trash'),
                    tooltip: 'email.delete'.tr(),
                  ),
                if (spamVerdict)
                  IconButton(
                    icon: const Icon(Icons.report_gmailerrorred_outlined, color: Colors.amber),
                    onPressed: () => _moveEmail('Junk'),
                    tooltip: 'email.move_to_spam'.tr(),
                  ),
              ],
            ),
          ),

          // Detail Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title / Subject
                  Text(
                    subject.toUpperCase(),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 16),

                   // Sender & Metadata Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.pureBlack,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('email.from'.tr() + ' ', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 11)),
                            Expanded(child: Text(sender, style: const TextStyle(color: AppColors.textMain, fontSize: 12))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('email.to'.tr() + ' ', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 11)),
                            Expanded(child: Text(to, style: const TextStyle(color: AppColors.textMain, fontSize: 12))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('email.date'.tr() + ' ', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 11)),
                            Expanded(child: Text(formattedDate, style: const TextStyle(color: AppColors.textMain, fontSize: 12))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // AI Insights Collapsible box
                  if (summary.isNotEmpty || spamVerdict || urgency != 'none') ...[
                    _buildAiInsightsBox(summary, urgency, urgencyReason, tags, spamVerdict, spamReason),
                    const SizedBox(height: 16),
                  ],

                  // AI Reply Assistant
                  if (aiReplyDraft.isNotEmpty) ...[
                    _buildAiReplyAssistantBox(aiReplyDraft, sender, subject),
                    const SizedBox(height: 16),
                  ],

                  // Email Body
                  Text('email.message_content'.tr(), style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                  const Divider(color: AppColors.border, height: 16),
                  const SizedBox(height: 8),
                  SelectableText(
                    bodyText,
                    style: const TextStyle(color: AppColors.textMain, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // Attachments Section
                  if (hasAttachments) ...[
                    Text('email.attachments'.tr(), style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                    const Divider(color: AppColors.border, height: 16),
                    _buildAttachmentsList(),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiInsightsBox(
    String summary,
    String urgency,
    String urgencyReason,
    List<String> tags,
    bool spamVerdict,
    String spamReason,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'email.ai_insights'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 12, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (spamVerdict) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.2),
                border: Border.all(color: AppColors.error),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.report, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('email.spam_detected'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 11)),
                        Text(spamReason, style: const TextStyle(color: AppColors.textMain, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (summary.isNotEmpty) ...[
            Text('email.summary'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMain)),
            const SizedBox(height: 2),
            Text(summary, style: const TextStyle(color: AppColors.textMain, fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
          ],
          if (urgency != 'none') ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('email.urgency'.tr() + ' ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMain)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: urgency == 'critical' || urgency == 'high' ? AppColors.error : Colors.amber,
                  child: Text(urgency.toUpperCase(), style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (urgencyReason.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(urgencyReason, style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
            ],
            const SizedBox(height: 8),
          ],
          if (tags.isNotEmpty) ...[
            Text('email.classified_tags'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textMain)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: AppColors.border,
                    child: Text(t.toUpperCase(), style: const TextStyle(color: AppColors.textMain, fontSize: 10)),
                  )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiReplyAssistantBox(String draft, String replyToEmail, String subject) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureBlack,
        border: Border.all(color: Colors.purple, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assistant_outlined, color: Colors.purpleAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                'email.ai_reply_assistant'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.purpleAccent, fontSize: 12, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: MarkdownBody(
              data: draft,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: AppColors.textMain, fontSize: 12, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openComposer(
                  replyToEmail: replyToEmail,
                  replySubject: 'Re: $subject',
                  initialBody: draft,
                  emailId: _selectedEmail!['id'] as String?,
                ),
                icon: const Icon(Icons.edit, size: 16),
                label: Text('email.edit_send'.tr(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purpleAccent,
                  side: const BorderSide(color: Colors.purple),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAttachmentsList() {
    // Generate dummy attachments since enough_mail only parses them online or on-demand
    // To make this look professional, we can read filenames from body or let it display the actual names
    // Wait, MimeMessage findContentInfo() returns List<ContentInfo> which contains fileName
    // Since we don't have the fully fetched message inside Hive (just subject/body), we can either:
    // - Retrieve attachments from CachedEmail model (wait! Does CachedEmail have attachments? No, it has hasAttachments flag).
    // Let's call server to get attachment names!
    // Or we can fetch folders/structure.
    // Wait, let's write a simple FutureBuilder that fetches attachment names from the server!
    // Yes! Let's do that, it is extremely robust.
    return FutureBuilder<List<String>>(
      future: _fetchAttachmentNames(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
          return Center(child: Text('email.attachments_offline'.tr(), style: const TextStyle(color: AppColors.textDim, fontSize: 12)));
        }

        final names = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: names.length,
          itemBuilder: (context, index) {
            final name = names[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.pureBlack,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name, style: const TextStyle(color: AppColors.textMain, fontSize: 12))),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: AppColors.primary, size: 18),
                    onPressed: () => _downloadAttachment(name),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<String>> _fetchAttachmentNames() async {
    if (_selectedAccountId == null || _selectedEmail == null) return [];
    final emailId = _selectedEmail!['id'] as String;
    try {
      final response = await ref.read(gatewayClientProvider).call('email.getAttachmentNames', {
        'accountId': _selectedAccountId,
        'emailId': emailId,
      });
      if (response != null && response['names'] != null) {
        return (response['names'] as List<dynamic>).cast<String>();
      }
    } catch (_) {}
    return [];
  }
}
