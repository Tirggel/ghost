import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/app_styles.dart';
import '../../core/constants.dart';
import '../widgets/app_dialogs.dart';

class BusinessCardField {
  BusinessCardField({
    required this.label,
    this.value,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
    this.customEditWidget,
  });
  final String label;
  final String? value;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final Widget? customEditWidget;
}

class BusinessCard extends StatefulWidget {
  const BusinessCard({
    super.key,
    required this.title,
    this.avatar,
    this.avatarBuilder,
    required this.fields,
    required this.onSave,
    this.onEditToggle,
    this.onDelete,
    this.initialEdit = false,
    this.isEditing,
    this.isEnabled,
    this.onToggleEnabled,
    this.bottom,
    this.maxViewFields,
  }) : assert(
         avatar != null || avatarBuilder != null,
         'Either avatar or avatarBuilder must be provided',
       );
  final String title;
  final Widget? avatar;
  final Widget Function(BuildContext context, bool isEditing)? avatarBuilder;
  final List<BusinessCardField> fields;
  final Future<void> Function() onSave;
  final VoidCallback? onEditToggle;
  final Future<void> Function()? onDelete;
  final bool initialEdit;
  final bool? isEditing;
  final bool? isEnabled;
  final ValueChanged<bool>? onToggleEnabled;
  final Widget Function(BuildContext context, bool isEditing)? bottom;
  final int? maxViewFields;

  @override
  State<BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<BusinessCard> with SettingsSaveMixin {
  bool? _internalIsEditing;

  bool get _isEditing => widget.isEditing ?? _internalIsEditing ?? false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing == null) {
      _internalIsEditing = widget.initialEdit;
    }
  }

  void _toggleEdit() {
    if (widget.isEditing == null) {
      setState(() {
        _internalIsEditing = !_isEditing;
      });
    }
    widget.onEditToggle?.call();
  }

  Future<void> _handleSave() async {
    await handleSave(() async {
      await widget.onSave();
      if (mounted && widget.isEditing == null) {
        setState(() {
          _internalIsEditing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isEditing ? null : _toggleEdit,
      child: MouseRegion(
        cursor: _isEditing
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.zero, // Brutalist square
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.avatarBuilder?.call(context, _isEditing) ??
                            widget.avatar!,
                        const SizedBox(width: 24),
                        Expanded(
                          child: _isEditing
                              ? _buildEditFields()
                              : _buildViewFields(),
                        ),
                      ],
                    ),
                    if (widget.bottom != null &&
                        (widget.maxViewFields == null || _isEditing)) ...[
                      const SizedBox(height: 24),
                      widget.bottom!(context, _isEditing),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: _isEditing ? AppColors.surface : AppColors.background,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.title.tr().toUpperCase(),
            style: const TextStyle(
              fontSize: AppConstants.fontSizeTitle,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          Row(
            children: [
              if (widget.isEnabled != null && widget.onToggleEnabled != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (widget.isEnabled!
                                ? 'common.enabled'
                                : 'common.disabled')
                            .tr(),
                        style: TextStyle(
                          fontSize: AppConstants.fontSizeCaption,
                          color: widget.isEnabled!
                              ? AppColors.primary
                              : AppColors.textDim,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: widget.isEnabled!,
                          onChanged: widget.onToggleEnabled,
                          activeThumbColor: AppColors.primary,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 20,
                        color: AppColors.border.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              if (_isEditing && widget.onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  style: IconButton.styleFrom(foregroundColor: AppColors.white)
                      .copyWith(
                        foregroundColor:
                            WidgetStateProperty.resolveWith<Color?>((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return AppColors.error;
                              }
                              return AppColors.white;
                            }),
                      ),
                  onPressed: () async {
                    final confirmed = await AppAlertDialog.showConfirmation(
                      context: context,
                      title: 'common.delete'.tr(),
                      content: 'settings.agents.delete_content'.tr(
                        namedArgs: {'name': ''},
                      ),
                      confirmLabel: 'common.delete'.tr(),
                      isDestructive: true,
                    );
                    if (confirmed == true) {
                      await widget.onDelete!();
                    }
                  },
                  tooltip: 'common.delete'.tr(),
                ),
              if (_isEditing)
                IconButton(
                  icon: isSaveLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.save, color: AppColors.primary),
                  onPressed: isSaveLoading ? null : _handleSave,
                  tooltip: 'common.save'.tr(),
                ),
              IconButton(
                icon: Icon(
                  _isEditing ? Icons.close : Icons.edit_outlined,
                  size: 20,
                  color: _isEditing ? AppColors.textDim : AppColors.primary,
                ),
                onPressed: isSaveLoading ? null : _toggleEdit,
                tooltip: (_isEditing ? 'common.cancel' : 'common.edit').tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewFields() {
    final displayFields = widget.maxViewFields != null
        ? widget.fields.take(widget.maxViewFields!).toList()
        : widget.fields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: displayFields.map((field) {
        final displayValue = field.value ?? field.controller.text;
        if (displayValue.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.label.tr().toUpperCase(),
                style: const TextStyle(
                  fontSize: AppConstants.fontSizeLabelTiny,
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayValue,
                style: const TextStyle(
                  fontSize: AppConstants.fontSizeBody,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEditFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.fields.map((field) {
        if (field.customEditWidget != null) {
          return field.customEditWidget!;
        }
        return AppFormField.text(
          controller: field.controller,
          label: field.label,
          hint: field.hint,
          maxLines: field.maxLines,
        );
      }).toList(),
    );
  }
}
