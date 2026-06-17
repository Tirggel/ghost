import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class EmailTab extends ConsumerStatefulWidget {
  const EmailTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<EmailTab> createState() => _EmailTabState();
}

class _EmailTabState extends ConsumerState<EmailTab> {
  bool _isLoading = true;
  List<dynamic> _accounts = [];
  Map<String, dynamic>? _selectedAccount;
  bool _isEditing = false;
  bool _isNew = false;
  bool _isTesting = false;
  bool _isSaving = false;

  // Form Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController();
  final _imapPasswordController = TextEditingController();
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _writingStyleController = TextEditingController();

  // AI Flags
  bool _autoSummarize = true;
  bool _autoReply = false;
  bool _autoTag = true;
  bool _autoSpam = false;
  bool _autoCalendar = false;
  bool _autoUrgent = false;
  bool _imapSecure = true;
  bool _smtpSecure = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    _imapPasswordController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpPasswordController.dispose();
    _writingStyleController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      final response = await ref.read(gatewayClientProvider).call('email.listAccounts', {});
      if (response != null && response['accounts'] != null) {
        setState(() {
          _accounts = response['accounts'] as List<dynamic>;
        });
      }
    } catch (e) {
      AppSnackBar.showError(context, 'Failed to load email accounts: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _selectAccount(Map<String, dynamic> acc) {
    setState(() {
      _selectedAccount = acc;
      _isEditing = true;
      _isNew = false;

      // Populate Controllers
      _nameController.text = acc['name'] as String? ?? '';
      _emailController.text = acc['email'] as String? ?? '';
      _imapHostController.text = acc['imapHost'] as String? ?? '';
      _imapPortController.text = (acc['imapPort'] ?? 993).toString();
      _imapPasswordController.clear(); // Never populate password back for security
      _smtpHostController.text = acc['smtpHost'] as String? ?? '';
      _smtpPortController.text = (acc['smtpPort'] ?? 465).toString();
      _smtpPasswordController.clear();

      _autoSummarize = acc['autoSummarize'] as bool? ?? true;
      _autoReply = acc['autoReply'] as bool? ?? false;
      _autoTag = acc['autoTag'] as bool? ?? true;
      _autoSpam = acc['autoSpam'] as bool? ?? false;
      _autoCalendar = acc['autoCalendar'] as bool? ?? false;
      _autoUrgent = acc['autoUrgent'] as bool? ?? false;
      _imapSecure = acc['imapSecure'] as bool? ?? true;
      _smtpSecure = acc['smtpSecure'] as bool? ?? true;
      final style = acc['writingStyle'] as String? ?? '';
      _writingStyleController.text = (style.isEmpty || style == 'Friendly, polite and concise.')
          ? 'settings.email.writing_style_hint'.tr()
          : style;
    });
  }

  void _addNewAccount() {
    setState(() {
      _selectedAccount = null;
      _isEditing = true;
      _isNew = true;

      // Clear Controllers
      _nameController.text = 'settings.email.default_name'.tr();
      _emailController.clear();
      _imapHostController.clear();
      _imapPortController.text = '993';
      _imapPasswordController.clear();
      _smtpHostController.clear();
      _smtpPortController.text = '465';
      _smtpPasswordController.clear();

      _autoSummarize = true;
      _autoReply = false;
      _autoTag = true;
      _autoSpam = false;
      _autoCalendar = false;
      _autoUrgent = false;
      _imapSecure = true;
      _smtpSecure = true;
      _writingStyleController.text = 'settings.email.writing_style_hint'.tr();
    });
  }

  Map<String, dynamic> _buildAccountConfig() {
    return {
      'id': _isNew ? '' : (_selectedAccount?['id'] ?? ''),
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'imapHost': _imapHostController.text.trim(),
      'imapPort': int.tryParse(_imapPortController.text.trim()) ?? 993,
      'imapSecure': _imapSecure,
      'smtpHost': _smtpHostController.text.trim(),
      'smtpPort': int.tryParse(_smtpPortController.text.trim()) ?? 465,
      'smtpSecure': _smtpSecure,
      'autoSummarize': _autoSummarize,
      'autoReply': _autoReply,
      'autoTag': _autoTag,
      'autoSpam': _autoSpam,
      'autoCalendar': _autoCalendar,
      'autoUrgent': _autoUrgent,
      'writingStyle': _writingStyleController.text.trim(),
      'enabled': _selectedAccount?['enabled'] ?? true,
    };
  }

  Future<void> _testConnection() async {
    if (_emailController.text.isEmpty ||
        _imapHostController.text.isEmpty ||
        _smtpHostController.text.isEmpty) {
      AppSnackBar.showError(context, 'settings.email.required_fields'.tr());
      return;
    }

    setState(() => _isTesting = true);
    try {
      final config = _buildAccountConfig();
      final response = await ref.read(gatewayClientProvider).call('email.testAccount', {
        'account': config,
        'imapPassword': _imapPasswordController.text.isNotEmpty ? _imapPasswordController.text : null,
        'smtpPassword': _smtpPasswordController.text.isNotEmpty ? _smtpPasswordController.text : null,
      });

      if (response != null && response['success'] == true) {
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AppAlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                  const SizedBox(width: 10),
                  Text('settings.email.test_success_title'.tr()),
                ],
              ),
              content: Text(
                'settings.email.test_success_msg'.tr(),
                style: const TextStyle(
                  height: 1.4,
                  fontSize: 13,
                  color: AppColors.textDim,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('common.ok'.tr()),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          AppAlertDialog.showError(
            context: context,
            message: 'settings.email.test_failed_msg'.tr(),
          );
        }
      }
    } catch (e) {
      AppSnackBar.showError(context, 'settings.email.test_failed_err'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (_emailController.text.isEmpty ||
        _imapHostController.text.isEmpty ||
        _smtpHostController.text.isEmpty) {
      AppSnackBar.showError(context, 'settings.email.required_fields'.tr());
      return;
    }

    setState(() => _isSaving = true);
    try {
      final config = _buildAccountConfig();
      await ref.read(gatewayClientProvider).call('email.saveAccount', {
        'account': config,
        'imapPassword': _imapPasswordController.text.isNotEmpty ? _imapPasswordController.text : null,
        'smtpPassword': _smtpPasswordController.text.isNotEmpty ? _smtpPasswordController.text : null,
      });

      AppSnackBar.showSuccess(context, 'settings.email.saved_success'.tr());
      setState(() {
        _isEditing = false;
        _isNew = false;
        _selectedAccount = null;
      });
      await _loadAccounts();
    } catch (e) {
      AppSnackBar.showError(context, 'settings.email.failed_save'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    if (_selectedAccount == null) return;
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.email.delete_account'.tr(),
      content: 'settings.email.delete_confirm_msg'.tr(namedArgs: {'email': _selectedAccount!['email']}),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      try {
        await ref.read(gatewayClientProvider).call('email.deleteAccount', {
          'id': _selectedAccount!['id'],
        });
        AppSnackBar.showSuccess(context, 'settings.email.deleted_success'.tr());
        setState(() {
          _isEditing = false;
          _selectedAccount = null;
        });
        await _loadAccounts();
      } catch (e) {
        AppSnackBar.showError(context, 'settings.email.failed_delete'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return AppSettingsPage(
      onBack: _isEditing ? () => setState(() => _isEditing = false) : widget.onBack,
      onNext: _isEditing ? null : widget.onNext,
      onSave: _isEditing ? _save : null,
      isSaveLoading: _isSaving,
      topPadding: widget.topPadding,
      children: [
        if (!_isEditing) ...[
          const AppSectionHeader('settings.email.title', large: true),
          Text(
            'settings.email.desc'.tr(),
            style: const TextStyle(
              fontSize: AppConstants.fontSizeBody,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 24),
          if (_accounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const Icon(Icons.mail_outline_rounded, size: 64, color: AppColors.textDim),
                    const SizedBox(height: 16),
                    Text(
                      'settings.email.no_accounts'.tr(),
                      style: const TextStyle(color: AppColors.textDim),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _addNewAccount,
                      icon: const Icon(Icons.add),
                      label: Text('settings.email.add_account'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _accounts.length,
              itemBuilder: (context, index) {
                final acc = _accounts[index] as Map<String, dynamic>;
                return Card(
                  color: AppColors.pureBlack,
                  shape: Border.all(color: AppColors.border),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(
                      (acc['name'] as String).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
                    ),
                    subtitle: Text(
                      acc['email'] as String,
                      style: const TextStyle(color: AppColors.textDim),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
                    onTap: () => _selectAccount(acc),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addNewAccount,
                icon: const Icon(Icons.add),
                label: Text('settings.email.add_account'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMain,
                  side: const BorderSide(color: AppColors.border),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ),
          ]
        ] else ...[
          AppSectionHeader(_isNew ? 'settings.email.add_title' : 'settings.email.edit_title', large: true),
          const SizedBox(height: 16),

          // Core configuration fields
          _buildTextField(label: 'settings.email.label_name'.tr(), hint: 'settings.email.hint_name'.tr(), controller: _nameController),
          _buildTextField(label: 'settings.email.label_address'.tr(), hint: 'settings.email.hint_address'.tr(), controller: _emailController),

          const SizedBox(height: 16),
          Text('settings.email.imap_server'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          _buildTextField(label: 'settings.email.host'.tr(), hint: 'imap.domain.com', controller: _imapHostController),
          Row(
            children: [
              Expanded(child: _buildTextField(label: 'settings.email.port'.tr(), hint: '993', controller: _imapPortController)),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Row(
                  children: [
                    Checkbox(
                      value: _imapSecure,
                      onChanged: (val) => setState(() => _imapSecure = val ?? true),
                      activeColor: AppColors.primary,
                    ),
                    Text('settings.email.ssl_secure'.tr()),
                  ],
                ),
              ),
            ],
          ),
          _buildTextField(
            label: 'settings.email.password'.tr(),
            hint: _isNew ? 'settings.email.password'.tr() : 'settings.email.password_hint_edit'.tr(),
            controller: _imapPasswordController,
            obscureText: true,
          ),

          const SizedBox(height: 16),
          Text('settings.email.smtp_server'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          _buildTextField(label: 'settings.email.host'.tr(), hint: 'smtp.domain.com', controller: _smtpHostController),
          Row(
            children: [
              Expanded(child: _buildTextField(label: 'settings.email.port'.tr(), hint: '465', controller: _smtpPortController)),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Row(
                  children: [
                    Checkbox(
                      value: _smtpSecure,
                      onChanged: (val) => setState(() => _smtpSecure = val ?? true),
                      activeColor: AppColors.primary,
                    ),
                    Text('settings.email.ssl_secure'.tr()),
                  ],
                ),
              ),
            ],
          ),
          _buildTextField(
            label: 'settings.email.smtp_password'.tr(),
            hint: 'settings.email.smtp_password_hint'.tr(),
            controller: _smtpPasswordController,
            obscureText: true,
          ),

          const SizedBox(height: 24),
          Text('settings.email.ai_triage'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 12),
          _buildSwitchTile('settings.email.auto_summarize'.tr(), 'settings.email.auto_summarize_desc'.tr(), _autoSummarize, (val) => setState(() => _autoSummarize = val)),
          _buildSwitchTile('settings.email.auto_tag'.tr(), 'settings.email.auto_tag_desc'.tr(), _autoTag, (val) => setState(() => _autoTag = val)),
          _buildSwitchTile('settings.email.auto_urgency'.tr(), 'settings.email.auto_urgency_desc'.tr(), _autoUrgent, (val) => setState(() => _autoUrgent = val)),
          _buildSwitchTile('settings.email.auto_reply'.tr(), 'settings.email.auto_reply_desc'.tr(), _autoReply, (val) => setState(() => _autoReply = val)),
          _buildSwitchTile('settings.email.auto_spam'.tr(), 'settings.email.auto_spam_desc'.tr(), _autoSpam, (val) => setState(() => _autoSpam = val)),
          _buildSwitchTile('settings.email.auto_calendar'.tr(), 'settings.email.auto_calendar_desc'.tr(), _autoCalendar, (val) => setState(() => _autoCalendar = val)),

          const SizedBox(height: 16),
          _buildTextField(
            label: 'settings.email.writing_style'.tr(),
            hint: 'settings.email.writing_style_hint'.tr(),
            controller: _writingStyleController,
            maxLines: 2,
          ),

          const SizedBox(height: 32),
          Row(
            children: [
              if (_isTesting)
                const CircularProgressIndicator()
              else
                OutlinedButton.icon(
                  onPressed: _testConnection,
                  icon: const Icon(Icons.sync_alt),
                  label: Text('settings.email.test_connection'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMain,
                    side: const BorderSide(color: AppColors.border),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              const Spacer(),
              if (!_isNew)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete, color: AppColors.error),
                  label: Text('settings.email.delete_account'.tr(), style: const TextStyle(color: AppColors.error)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                ),
            ],
          ),
        ]
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormLabel(label),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            obscureText: obscureText,
            maxLines: maxLines,
            style: const TextStyle(color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textDim),
              filled: true,
              fillColor: AppColors.pureBlack,
              border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(String title, String desc, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(desc, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
    );
  }
}
