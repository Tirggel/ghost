import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/app_styles.dart';
import '../../core/constants.dart';

class BusinessCardField {
  final String label;
  final String? value;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final Widget? customEditWidget;

  BusinessCardField({
    required this.label,
    this.value,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
    this.customEditWidget,
  });
}

class BusinessCard extends StatefulWidget {
  final String title;
  final Widget avatar;
  final List<BusinessCardField> fields;
  final Future<void> Function() onSave;
  final VoidCallback? onEditToggle;
  final Future<void> Function()? onDelete;
  final bool initialEdit;
  final bool? isEnabled;
  final ValueChanged<bool>? onToggleEnabled;
  final Widget Function(BuildContext context, bool isEditing)? bottom;
  final int? maxViewFields;

  const BusinessCard({
    super.key,
    required this.title,
    required this.avatar,
    required this.fields,
    required this.onSave,
    this.onEditToggle,
    this.onDelete,
    this.initialEdit = false,
    this.isEnabled,
    this.onToggleEnabled,
    this.bottom,
    this.maxViewFields,
  });

  @override
  State<BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<BusinessCard> {
  late bool _isEditing;
  bool _isSaving = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.initialEdit;
  }

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
    });
    widget.onEditToggle?.call();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave();
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _isEditing || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
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
                      widget.avatar,
                      const SizedBox(width: 24),
                      Expanded(
                        child: _isEditing
                            ? _buildEditFields()
                            : _buildViewFields(),
                      ),
                    ],
                  ),
                  if (widget.bottom != null && (widget.maxViewFields == null || _isEditing)) ...[
                    const SizedBox(height: 24),
                    widget.bottom!(context, _isEditing),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: _isEditing ? AppColors.surface : AppColors.background,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.title.tr().toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
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
                        (widget.isEnabled! ? 'common.enabled' : 'common.disabled').tr(),
                        style: TextStyle(
                          fontSize: AppConstants.fontSizeCaption,
                          color: widget.isEnabled! ? AppColors.primary : AppColors.textDim,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: widget.isEnabled!,
                          onChanged: widget.onToggleEnabled,
                          activeColor: AppColors.primary,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        title: Text('common.delete'.tr()),
                        content: Text(
                          'settings.agents.delete_content'.tr(
                            namedArgs: {'name': ''},
                          ),
                        ),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('common.cancel'.tr()),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              'common.delete'.tr(),
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await widget.onDelete!();
                    }
                  },
                  tooltip: 'common.delete'.tr(),
                ),
              if (_isEditing)
                IconButton(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.save, color: AppColors.primary),
                  onPressed: _isSaving ? null : _handleSave,
                  tooltip: 'common.save'.tr(),
                ),
              IconButton(
                icon: Icon(
                  _isEditing ? Icons.close : Icons.edit_outlined,
                  size: 20,
                  color: _isEditing ? AppColors.textDim : AppColors.primary,
                ),
                onPressed: _isSaving ? null : _toggleEdit,
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
                  fontSize: 9,
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
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
