// ---------------------------------------------------------------------------
// app_styles.dart — Shared form widgets & style helpers
//
// Use these instead of local _textInput / _inputDec / _sectionHeader etc.
// in both setup_wizard_screen.dart and shell_screen.dart.
// ---------------------------------------------------------------------------

import 'package:easy_localization/easy_localization.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'settings_sub_nav_bar.dart';
import 'app_snackbar.dart';

// ---------------------------------------------------------------------------
// AppInputDecoration
// ---------------------------------------------------------------------------

/// Canonical input decoration used for all labelled form fields (dropdowns,
/// text fields with floating labels).
class AppInputDecoration {
  const AppInputDecoration._();

  static InputDecoration standard(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: AppColors.background,
      labelStyle: const TextStyle(
        color: AppColors.textDim,
        fontSize: AppConstants.fontSizeBody,
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  /// Compact decoration for fields without a floating label (hint-only).
  static InputDecoration compact({
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: (hint != null && hint.isNotEmpty) ? hint : null,
      hintStyle: const TextStyle(
        color: AppColors.textDim,
        fontSize: AppConstants.fontSizeSmall,
      ),
      isDense: true,
      filled: true,
      fillColor: AppColors.background,
      border: const OutlineInputBorder(),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

// ---------------------------------------------------------------------------
// AppFormLabel
// ---------------------------------------------------------------------------

/// Small label rendered above form fields — matches the wizard's _label() style.
class AppFormLabel extends StatelessWidget {
  const AppFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Text(
      text.isEmpty ? '' : text.tr().toUpperCase(),
      style: const TextStyle(
        color: AppColors.textDim,
        fontSize: AppConstants.fontSizeLabelTiny,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppFormField
// ---------------------------------------------------------------------------

/// A labelled text field consistent across wizard and settings.
///
/// Usage:
/// ```dart
/// AppFormField.text(
///   controller: _nameController,
///   label: 'Name',
///   hint: 'Enter your name',
/// )
/// ```
class AppFormField extends StatelessWidget {
  const AppFormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  /// Named constructor alias kept for call sites.
  static AppFormField text({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool obscureText = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    Widget? prefixIcon,
    Widget? suffixIcon,
    Key? key,
  }) {
    return AppFormField(
      controller: controller,
      label: label,
      hint: hint,
      maxLines: maxLines,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      key: key,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormLabel(label),
          const SizedBox(height: 6),
          Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus && onSubmitted != null) {
                onSubmitted!(controller.text);
              }
            },
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              obscureText: obscureText,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              decoration: AppInputDecoration.compact(
                hint: hint.tr(),
                prefixIcon: prefixIcon,
                suffixIcon: suffixIcon,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppDropdownField
// ---------------------------------------------------------------------------

/// A labelled dropdown consistent with the rest of the form system.
class AppDropdownField<T> extends StatefulWidget {
  const AppDropdownField({
    required this.value,
    this.label,
    required this.items,
    required this.onChanged,
    required this.displayValue,
    this.itemBuilder,
    this.selectedItemBuilder,
    this.hint,
    this.prefixIcon,
    super.key,
  });

  final T? value;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T) displayValue;
  final Widget Function(T)? itemBuilder;
  final List<Widget> Function(BuildContext)? selectedItemBuilder;

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  bool _hasFocus = false;

  void _openDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AppDropdownDialog<T>(
        items: widget.items,
        selectedValue: widget.value,
        onSelected: widget.onChanged,
        title: widget.label ?? widget.hint ?? '',
        displayValue: widget.displayValue,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    String displayStr = (widget.hint != null && widget.hint!.isNotEmpty) ? widget.hint!.tr() : '';
    if (widget.value != null) {
      displayStr = widget.displayValue(widget.value as T);
    }
    
    Widget? activeChild;
    if (widget.selectedItemBuilder != null && widget.value != null) {
      final widgets = widget.selectedItemBuilder!(context);
      final index = widget.items.indexOf(widget.value as T);
      if (index >= 0 && index < widgets.length) {
        activeChild = widgets[index];
      }
    }
    if (activeChild == null && widget.itemBuilder != null && widget.value != null) {
      activeChild = widget.itemBuilder!(widget.value as T);
    }
    activeChild ??= Text(
      displayStr,
      style: TextStyle(
        color: widget.value != null ? AppColors.white : AppColors.textDim,
        fontSize: AppConstants.fontSizeBody,
      ),
      overflow: TextOverflow.ellipsis,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null && widget.label!.isNotEmpty) ...[
            AppFormLabel(widget.label!),
            const SizedBox(height: 6),
          ],
          Focus(
            onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
            child: GestureDetector(
              onTap: widget.items.isEmpty ? null : () => _openDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _hasFocus ? AppColors.primary : AppColors.border,
                    width: _hasFocus ? 1.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
                  color: AppColors.background,
                ),
                child: Row(
                  children: [
                    if (widget.prefixIcon != null) ...[
                      widget.prefixIcon!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: activeChild),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textDim,
                      size: AppConstants.settingsIconSize,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDropdownDialog<T> extends StatefulWidget {

  const _AppDropdownDialog({
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    required this.title,
    required this.displayValue,
    this.itemBuilder,
  });
  final List<T> items;
  final T? selectedValue;
  final void Function(T?) onSelected;
  final String title;
  final String Function(T) displayValue;
  final Widget Function(T)? itemBuilder;

  @override
  State<_AppDropdownDialog<T>> createState() => _AppDropdownDialogState<T>();
}

class _AppDropdownDialogState<T> extends State<_AppDropdownDialog<T>> {
  final _searchController = TextEditingController();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_sortAndFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _sortAndFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((i) {
          final label = widget.displayValue(i).toLowerCase();
          return label.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.isEmpty ? '' : widget.title.tr(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                AppCloseButton(
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (widget.items.length > 5) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                decoration: AppInputDecoration.compact(
                  hint: 'sidebar.search_placeholder'.tr(),
                ).copyWith(
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textDim,
                    size: 18,
                  ),
                  fillColor: AppColors.background,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        'common.no_results'.tr(),
                        style: const TextStyle(color: AppColors.textDim),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final isSelected = item == widget.selectedValue;

                        Widget content;
                        if (widget.itemBuilder != null) {
                          content = widget.itemBuilder!(item);
                        } else {
                          content = Text(
                            widget.displayValue(item),
                            style: TextStyle(
                              color: isSelected ? AppColors.primary : AppColors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          );
                        }

                        return ListTile(
                          title: content,
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                  size: 16,
                                )
                              : null,
                          onTap: () {
                            widget.onSelected(item);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppSectionHeader
// ---------------------------------------------------------------------------

/// Section header used in settings tabs and dialogs.
///
/// [large] = true  → fontSizeTitle (16) — for top-level settings tab headers
/// [large] = false → fontSizeSubhead (14) — for sub-sections inside dialogs
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.title, {this.large = false, super.key});

  final String title;
  final bool large;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.settingsHeaderBottomPadding),
      child: Text(
        title.tr().toUpperCase(),
        style: TextStyle(
          fontSize: large
              ? AppConstants.fontSizeTitle
              : AppConstants.fontSizeSubhead,
          fontWeight: FontWeight.w900,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppEmojiPickerConfig — canonical EmojiPicker Config
// ---------------------------------------------------------------------------

/// The single canonical `Config` for every `EmojiPicker` in the app.
const Config appEmojiPickerConfig = Config(
  checkPlatformCompatibility: true,
  emojiViewConfig: EmojiViewConfig(
    columns: 7,
    emojiSizeMax: 28,
    backgroundColor: AppColors.surface,
    buttonMode: ButtonMode.MATERIAL,
    recentsLimit: 28,
  ),
  viewOrderConfig: ViewOrderConfig(
    top: EmojiPickerItem.categoryBar,
    middle: EmojiPickerItem.emojiView,
    bottom: EmojiPickerItem.searchBar,
  ),
  categoryViewConfig: CategoryViewConfig(
    backgroundColor: AppColors.surface,
    dividerColor: AppColors.border,
    indicatorColor: AppColors.primary,
    iconColorSelected: AppColors.primary,
    iconColor: AppColors.textDim,
    tabBarHeight: 46,
  ),
  bottomActionBarConfig: BottomActionBarConfig(
    backgroundColor: AppColors.surface,
    buttonColor: AppColors.surface,
    buttonIconColor: AppColors.textDim,
  ),
  searchViewConfig: SearchViewConfig(
    backgroundColor: AppColors.surface,
    buttonIconColor: AppColors.textDim,
  ),
);

/// Shows the shared emoji picker bottom sheet.
///
/// [onSelected] is called with the chosen emoji string.
void showAppEmojiPicker(
  BuildContext context, {
  required void Function(String emoji) onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (ctx) => SizedBox(
      height: 350,
      child: EmojiPicker(
        onEmojiSelected: (_, emoji) {
          onSelected(emoji.emoji);
          Navigator.pop(ctx);
        },
        config: appEmojiPickerConfig,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// AppSectionLabel — ALLCAPS section label (used in dialogs e.g. model picker)
// ---------------------------------------------------------------------------

class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title.tr().toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: AppConstants.fontSizeLabelTiny,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppSaveButton — canonical primary action button
// ---------------------------------------------------------------------------

class AppSaveButton extends StatelessWidget {
  const AppSaveButton({
    required this.label,
    required this.onPressed,
    this.icon = Icons.save,
    this.isLoading = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    final button = ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.black,
              ),
            )
          : Icon(icon, size: AppConstants.settingsIconSize),
      label: Text(label.tr().toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.black,
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      ),
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

// ---------------------------------------------------------------------------
// AppNavButton — consistent Back/Next/Action buttons
// ---------------------------------------------------------------------------

class AppNavButton extends StatelessWidget {
  const AppNavButton({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.icon,
    this.backgroundColor,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    if (isPrimary) {
      final style = ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.primary,
        foregroundColor: AppColors.black,
        minimumSize: const Size(120, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      );

      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox(),
        label: Text(label.tr().toUpperCase(), 
          style: const TextStyle(fontWeight: FontWeight.w900)),
        style: style,
      );
    } else {
      final style = OutlinedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.background,
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        minimumSize: const Size(120, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      );

      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox(),
        label: Text(label.tr().toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900)),
        style: style,
      );
    }
  }
}


// ---------------------------------------------------------------------------
// AppHoverCard — hoverable AnimatedContainer card (matches wizard tile look)
// ---------------------------------------------------------------------------

/// A selectable card that animates its border/background colour on hover/tap.
/// Use [isSelected] to drive the active state.
class AppHoverCard extends StatefulWidget {
  const AppHoverCard({
    required this.child,
    required this.onTap,
    this.isSelected = false,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.padding,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool isSelected;
  final EdgeInsets margin;
  final EdgeInsets? padding;

  @override
  State<AppHoverCard> createState() => _AppHoverCardState();
}

class _AppHoverCardState extends State<AppHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    final active = widget.isSelected || _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: widget.margin,
          padding: widget.padding ?? const EdgeInsets.all(AppConstants.cardPadding),
          decoration: BoxDecoration(
            color: active
                ? AppColors.surfaceLight // Etwas heller bei Hover
                : AppColors.surface,
            borderRadius: BorderRadius.zero,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppLanguageTile — wizard-style language selection card
// ---------------------------------------------------------------------------

/// A selectable language card matching the wizard's _languageTile design.
class AppLanguageTile extends StatelessWidget {
  const AppLanguageTile({
    required this.label,
    required this.sublabel,
    required this.flag,
    required this.onTap,
    required this.isSelected,
    this.onFlagTap,
    super.key,
  });

  final String label;
  final String sublabel;
  final String flag;
  final VoidCallback onTap;
  final VoidCallback? onFlagTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return AppHoverCard(
      isSelected: isSelected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onFlagTap,
            child: Text(
              flag,
              style: const TextStyle(
                fontSize: 24,
                fontFamilyFallback: [
                  'Apple Color Emoji',
                  'Segoe UI Emoji',
                  'Noto Color Emoji',
                  'Android Emoji',
                  'EmojiSymbols',
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.primary : AppColors.textMain,
                  ),
                ),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeSmall,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_circle,
              color: AppConstants.iconColorPrimary,
              size: AppConstants.settingsIconSize,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppIconBox — step-header icon container (wizard _stepShell icon box)
// ---------------------------------------------------------------------------

/// A rounded box containing an icon — used as wizard/section step header.
class AppIconBox extends StatelessWidget {
  const AppIconBox({required this.icon, this.color, super.key});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Container(
      width: AppConstants.iconBoxSize,
      height: AppConstants.iconBoxSize,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Icon(
        icon,
        size: AppConstants.iconBoxIconSize,
        color: color ?? AppColors.primary,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppSettingsTile — shared tile with hover effects for settings
// ---------------------------------------------------------------------------

/// A generic tile used in settings with premium hover effects.
class AppSettingsTile extends StatelessWidget {
  const AppSettingsTile({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.child,
    this.onTap,
    this.isSelected = false,
    super.key,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;
  final VoidCallback? onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return AppHoverCard(
      isSelected: isSelected,
      onTap: onTap ?? () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: AppConstants.fontSizeSmall,
                          color: AppColors.textDim,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppSettingsNavBar — consistent settings navigation with Save/Next/Back
// ---------------------------------------------------------------------------

/// The canonical bottom navigation bar used in settings tabs.
///
/// Matches the design in the 'Memory' tab:
/// - Container with top border
/// - 'Back' (outlined) on the far left
/// - 'Save' (primary) and 'Next' (outlined) in a group on the right
class AppSettingsNavBar extends StatelessWidget {
  const AppSettingsNavBar({
    this.onBack,
    this.onNext,
    this.onSave,
    this.saveLabel,
    this.isSaveLoading = false,
    this.saveIcon = Icons.save,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSave;
  final String? saveLabel;
  final bool isSaveLoading;
  final IconData saveIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      color: AppColors.background,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (onBack != null)
            AppNavButton(
              onPressed: onBack,
              label: 'common.back',
            )
          else
            const SizedBox(),
          Row(
            children: [
              if (onSave != null)
                AppSaveButton(
                  onPressed: onSave,
                  label: saveLabel ?? 'common.save',
                  isLoading: isSaveLoading,
                  icon: saveIcon,
                ),
              if (onNext != null) ...[
                if (onSave != null) const SizedBox(width: 10),
                AppNavButton(
                  onPressed: onNext,
                  label: 'common.next',
                  isPrimary: false, // Per 'Memory' tab design
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App Error Overlay
// ---------------------------------------------------------------------------

/// A premium error dialog widget with an alert icon and red accents.
class AppErrorDialog extends StatelessWidget {

  const AppErrorDialog({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.errorDark),
          const SizedBox(width: 12),
          Text(
            'common.error'.tr(),
            style: const TextStyle(
              color: AppColors.errorDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(
          color: AppColors.textMain,
          fontSize: AppConstants.fontSizeBody,
        ),
      ),
      actions: [
        AppNavButton(
          onPressed: () => Navigator.pop(context),
          label: 'common.ok',
          isPrimary: false,
          backgroundColor: AppColors.black,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// AppCloseButton — turns red on hover
// ---------------------------------------------------------------------------

class AppCloseButton extends StatefulWidget {
  const AppCloseButton({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  State<AppCloseButton> createState() => _AppCloseButtonState();
}

class _AppCloseButtonState extends State<AppCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: IconButton(
        icon: const Icon(Icons.close),
        onPressed: widget.onPressed,
        color: _isHovered ? AppColors.error : AppColors.textDim,
        splashRadius: 20,
      ),
    );
  }
}

/// Helper to show the [AppErrorDialog].
void showAppErrorDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AppErrorDialog(message: message),
  );
}

// ---------------------------------------------------------------------------
// SettingsSaveMixin — standardized saving logic for settings tabs
// ---------------------------------------------------------------------------

/// Mixin to provide consistent save-operation lifecycle management.
///
/// Use it in your `State` classes:
/// ```dart
/// class _MyTabState extends ConsumerState<MyTab> with SettingsSaveMixin {
///   ...
///   @override
///   Widget build(BuildContext context) {
///     return AppSettingsPage(
///       onSave: () => handleSave(_saveAction),
///       isSaveLoading: isSaveLoading,
///       ...
///     );
///   }
/// }
/// ```
mixin SettingsSaveMixin<T extends StatefulWidget> on State<T> {
  bool _isSaving = false;
  
  /// Whether a save operation is currently in progress.
  bool get isSaveLoading => _isSaving;

  /// Handles the save operation with loading state, error reporting and success notification.
  Future<void> handleSave(
    Future<void> Function() saveAction, {
    String? successMessage,
  }) async {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    try {
      await saveAction();
      if (mounted) {
        AppSnackBar.showSuccess(
          context, 
          successMessage ?? 'common.saved'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// AppSettingsPage — unified layout for settings tabs
// ---------------------------------------------------------------------------

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({
    super.key,
    this.subTabLabels,
    this.currentSubTabIndex,
    this.onSubTabChanged,
    this.children,
    this.body,
    this.onBack,
    this.onNext,
    this.onSave,
    this.saveLabel,
    this.isSaveLoading = false,
    this.saveIcon = Icons.save,
  }) : assert(children != null || body != null, 'Either children or body must be provided');

  final List<String>? subTabLabels;
  final int? currentSubTabIndex;
  final ValueChanged<int>? onSubTabChanged;
  final List<Widget>? children;
  final Widget? body;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSave;
  final String? saveLabel;
  final bool isSaveLoading;
  final IconData saveIcon;

  @override
  Widget build(BuildContext context) {
    final bool hasSubNav = subTabLabels != null && 
                          currentSubTabIndex != null && 
                          onSubTabChanged != null;

    final Widget content = body ?? ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.settingsPagePadding,
        0, // Top padding is handled by Nav or SizedBox
        AppConstants.settingsPagePadding,
        AppConstants.settingsPagePadding,
      ),
      children: children!,
    );

    return Column(
      children: [
        if (hasSubNav)
          SettingsSubNavBar(
            items: subTabLabels!,
            currentIndex: currentSubTabIndex!,
            onTap: onSubTabChanged!,
          )
        else
          const SizedBox(height: AppConstants.spacingSmall),
          
        Expanded(child: content),
        
        AppSettingsNavBar(
          onBack: onBack,
          onNext: onNext,
          onSave: onSave,
          saveLabel: saveLabel,
          isSaveLoading: isSaveLoading,
          saveIcon: saveIcon,
        ),
      ],
    );
  }
}
