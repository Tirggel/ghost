import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';
import '../../core/models/config_models.dart';
import '../../providers/gateway_provider.dart';

class ChatInputField extends ConsumerStatefulWidget {
  const ChatInputField({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onStop,
    required this.isProcessing,
  });

  final TextEditingController controller;
  final Function(String, List<PlatformFile>) onSend;
  final VoidCallback onStop;
  final bool isProcessing;

  @override
  ConsumerState<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends ConsumerState<ChatInputField> {
  final List<PlatformFile> _attachments = [];

  Future<void> _pickFiles(ModelCapabilities caps) async {
    final List<String> allowedExtensions = [];
    if (caps.supportsPdf) allowedExtensions.add('pdf');
    if (caps.supportsText) {
      allowedExtensions.addAll(['txt', 'md', 'dart', 'py', 'js', 'json']);
    }

    final FileType type = (caps.supportsImage || caps.supportsVideo || caps.supportsAudio)
        ? FileType.any
        : FileType.custom;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
        allowedExtensions: type == FileType.custom ? allowedExtensions : null,
      );

      if (result != null) {
        setState(() {
          _attachments.addAll(result.files);
        });
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  void _handleSend() {
    if (widget.controller.text.trim().isEmpty && _attachments.isEmpty) return;
    widget.onSend(widget.controller.text, List.from(_attachments));
    setState(() {
      _attachments.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final capsAsync = ref.watch(currentModelCapabilitiesProvider);
    final caps = capsAsync.value ?? ModelCapabilities.textOnly();

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachments.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.only(bottom: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                itemBuilder: (context, index) {
                  final file = _attachments[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getFileIcon(file.extension),
                          size: 16,
                          color: AppColors.textDim,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            file.name,
                            style: const TextStyle(fontSize: 12, color: AppColors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _removeAttachment(index),
                          child: const Icon(Icons.close, size: 14, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _pickFiles(caps),
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.textDim,
                  ),
                  tooltip: 'chat.attach_files'.tr(),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      hintText: 'chat.type_message'.tr(),
                      hintStyle: const TextStyle(color: AppColors.textDim),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                if (widget.isProcessing)
                  IconButton(
                    onPressed: widget.onStop,
                    icon: const Icon(
                      Icons.stop_circle_rounded,
                      color: AppConstants.iconColorError,
                      size: AppConstants.iconSizeExtraLarge,
                    ),
                    tooltip: 'common.stop'.tr(),
                  )
                else
                  IconButton(
                    onPressed: _handleSend,
                    icon: const Icon(
                      Icons.send_rounded,
                      color: AppConstants.iconColorPrimary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String? extension) {
    if (extension == null) return Icons.insert_drive_file_outlined;
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_library_outlined;
      case 'mp3':
      case 'wav':
      case 'm4a':
        return Icons.audiotrack_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
