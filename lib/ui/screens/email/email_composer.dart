import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/app_snackbar.dart';

class EmailComposer extends ConsumerStatefulWidget {
  const EmailComposer({
    super.key,
    required this.accountId,
    this.to,
    this.subject,
    this.initialBody,
    this.emailId,
  });

  final String accountId;
  final String? to;
  final String? subject;
  final String? initialBody;
  final String? emailId;

  @override
  ConsumerState<EmailComposer> createState() => _EmailComposerState();
}

class _EmailComposerState extends ConsumerState<EmailComposer> {
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final List<String> _attachmentPaths = [];
  bool _isSending = false;
  bool _isGeneratingReply = false;

  Future<void> _generateReply() async {
    if (widget.emailId == null) return;

    setState(() => _isGeneratingReply = true);
    AppSnackBar.show(context, 'email.generating_reply'.tr(), icon: Icons.auto_awesome);

    try {
      final response = await ref.read(gatewayClientProvider).call('email.generateReply', {
        'accountId': widget.accountId,
        'emailId': widget.emailId,
      });

      if (response != null && response['status'] == 'ok' && response['reply'] != null) {
        setState(() {
          _bodyController.text = response['reply'] as String;
        });
        if (mounted) {
          AppSnackBar.showSuccess(context, 'email.saved'.tr());
        }
      } else {
        throw Exception('Server returned non-ok status or empty reply');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'email.failed_send_email'.tr(namedArgs: {'error': e.toString()}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingReply = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.to != null) _toController.text = widget.to!;
    if (widget.subject != null) _subjectController.text = widget.subject!;
    if (widget.initialBody != null) _bodyController.text = widget.initialBody!;
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      if (result != null && result.paths.isNotEmpty) {
        setState(() {
          for (final path in result.paths) {
            if (path != null && !_attachmentPaths.contains(path)) {
              _attachmentPaths.add(path);
            }
          }
        });
      }
    } catch (e) {
      AppSnackBar.showError(context, 'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachmentPaths.removeAt(index);
    });
  }

  Future<void> _send() async {
    final to = _toController.text.trim();
    final subject = _subjectController.text.trim();
    final body = _bodyController.text.trim();

    if (to.isEmpty) {
      AppSnackBar.showError(context, 'email.specify_recipient'.tr());
      return;
    }

    setState(() => _isSending = true);
    AppSnackBar.show(context, 'email.sending_email'.tr(), icon: Icons.info_outline);

    try {
      final response = await ref.read(gatewayClientProvider).call('email.sendEmail', {
        'accountId': widget.accountId,
        'to': to,
        'subject': subject.isEmpty ? '(No Subject)' : subject,
        'bodyMarkdown': body,
        if (_attachmentPaths.isNotEmpty) 'attachmentPaths': _attachmentPaths,
      });

      if (response != null && response['status'] == 'ok') {
        if (mounted) {
          AppSnackBar.showSuccess(context, 'email.email_sent_success'.tr());
          Navigator.pop(context);
        }
      } else {
        throw Exception('Server returned non-ok status');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'email.failed_send_email'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.border, width: 1),
      ),
      child: Container(
        width: 800,
        height: 650,
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(
                    'email.new_message'.tr().toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textMain,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMain),
                    onPressed: _isSending ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form Fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // To field
                    _buildInputField(
                      label: 'email.to'.tr().replaceAll(':', ''),
                      hint: 'email.to_hint'.tr(),
                      controller: _toController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),

                    // Subject field
                    _buildInputField(
                      label: 'email.subject'.tr().replaceAll(':', ''),
                      hint: 'email.subject_hint'.tr(),
                      controller: _subjectController,
                    ),
                    const SizedBox(height: 16),

                    // Body editor
                    Row(
                      children: [
                        Text(
                          'email.message_body'.tr(),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (widget.emailId != null) ...[
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _isGeneratingReply || _isSending ? null : _generateReply,
                            icon: _isGeneratingReply
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.purpleAccent,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 12, color: Colors.purpleAccent),
                            label: Text(
                              'email.generate_reply'.tr(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.purpleAccent,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bodyController,
                      style: const TextStyle(color: AppColors.textMain, fontSize: 13, height: 1.4),
                      maxLines: 12,
                      minLines: 8,
                      decoration: InputDecoration(
                        hintText: 'email.body_hint'.tr(),
                        hintStyle: const TextStyle(color: AppColors.textDim),
                        filled: true,
                        fillColor: AppColors.pureBlack,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Attachments tray
                    Row(
                      children: [
                        Text(
                          'email.attachments'.tr(),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _pickAttachment,
                          icon: const Icon(Icons.attach_file, size: 14),
                          label: Text('email.add_file'.tr(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 16),
                    if (_attachmentPaths.isEmpty)
                      Text(
                        'email.no_attachments'.tr(),
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12, fontStyle: FontStyle.italic),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _attachmentPaths.length,
                        itemBuilder: (context, index) {
                          final path = _attachmentPaths[index];
                          final name = p.basename(path);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.pureBlack,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.insert_drive_file, color: AppColors.textDim, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(color: AppColors.textMain, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                                  onPressed: () => _removeAttachment(index),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Actions footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSending ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMain,
                      side: const BorderSide(color: AppColors.border),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: Text('email.cancel'.tr().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                        : const Icon(Icons.send_outlined, size: 16),
                    label: Text('email.send'.tr().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textDim,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.textMain, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textDim),
            filled: true,
            fillColor: AppColors.pureBlack,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
