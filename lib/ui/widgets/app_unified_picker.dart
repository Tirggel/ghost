import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';
import 'app_styles.dart';

class AppUnifiedPicker<T> extends StatefulWidget {
  const AppUnifiedPicker({
    super.key,
    required this.items,
    required this.displayValue,
    this.value,
    this.values,
    this.multiSelect = false,
    this.label,
    this.hint,
    this.prefixIcon,
    this.itemPrefixIcon,
    this.onChanged,
    this.onMultiChanged,
    this.loading = false,
  });

  final List<T> items;
  final String Function(T) displayValue;
  final T? value;
  final Set<T>? values;
  final bool multiSelect;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget Function(T)? itemPrefixIcon;
  final ValueChanged<T?>? onChanged;
  final ValueChanged<Set<T>>? onMultiChanged;
  final bool loading;

  @override
  State<AppUnifiedPicker<T>> createState() => _AppUnifiedPickerState<T>();
}

class _AppUnifiedPickerState<T> extends State<AppUnifiedPicker<T>> {
  bool _hasFocus = false;

  void _openSearchDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _UnifiedSearchDialog<T>(
        items: widget.items,
        displayValue: widget.displayValue,
        multiSelect: widget.multiSelect,
        selectedValue: widget.value,
        selectedValues: widget.values,
        title: widget.label ?? widget.hint ?? '',
        itemPrefixIcon: widget.itemPrefixIcon,
        onSelected: (val) {
          if (widget.onChanged != null) widget.onChanged!(val);
        },
        onMultiSelected: (vals) {
          if (widget.onMultiChanged != null) widget.onMultiChanged!(vals);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // Rebuild on language change

    String displayStr = (widget.hint != null && widget.hint!.isNotEmpty) ? widget.hint!.tr() : '';
    
    if (widget.multiSelect) {
      final selected = (widget.values ?? {}).where((v) => widget.items.contains(v)).toSet();
      if (selected.isNotEmpty) {
        if (selected.length == 1) {
          displayStr = widget.displayValue(selected.first);
        } else {
          displayStr = 'settings.common.selected_count'.tr(namedArgs: {'count': selected.length.toString()});
        }
      }
    } else {
      if (widget.value != null) {
        displayStr = widget.displayValue(widget.value as T);
      }
    }

    Widget activeChild = Row(
      children: [
        if (widget.prefixIcon != null && !widget.multiSelect && widget.value == null) ...[
          widget.prefixIcon!,
          const SizedBox(width: 8),
        ],
        if (!widget.multiSelect && widget.value != null && widget.itemPrefixIcon != null) ...[
          widget.itemPrefixIcon!(widget.value as T),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            displayStr,
            style: TextStyle(
              color: (widget.multiSelect ? (widget.values?.isNotEmpty ?? false) : widget.value != null)
                  ? AppColors.white
                  : AppColors.textDim,
              fontSize: AppConstants.fontSizeBody,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.settingsElementSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null && widget.label!.isNotEmpty) ...[
            AppFormLabel(widget.label!),
            const SizedBox(height: 6),
          ],
          Focus(
            onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
            child: InkWell(
              onTap: widget.loading || widget.items.isEmpty ? null : _openSearchDialog,
              borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _hasFocus ? AppColors.primary : AppColors.white,
                    width: _hasFocus ? 1.5 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
                  color: AppColors.black,
                ),
                child: Row(
                  children: [
                    Expanded(child: activeChild),
                    if (widget.loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
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

class _UnifiedSearchDialog<T> extends StatefulWidget {
  const _UnifiedSearchDialog({
    required this.items,
    required this.displayValue,
    required this.multiSelect,
    this.selectedValue,
    this.selectedValues,
    required this.title,
    this.itemPrefixIcon,
    this.onSelected,
    this.onMultiSelected,
  });

  final List<T> items;
  final String Function(T) displayValue;
  final bool multiSelect;
  final T? selectedValue;
  final Set<T>? selectedValues;
  final String title;
  final Widget Function(T)? itemPrefixIcon;
  final ValueChanged<T?>? onSelected;
  final ValueChanged<Set<T>>? onMultiSelected;

  @override
  State<_UnifiedSearchDialog<T>> createState() => _UnifiedSearchDialogState<T>();
}

class _UnifiedSearchDialogState<T> extends State<_UnifiedSearchDialog<T>> {
  final _searchController = TextEditingController();
  List<T> _filteredItems = [];
  late Set<T> _currentSelections;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _currentSelections = Set<T>.from(widget.selectedValues ?? {});
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

  void _toggleSelection(T item) {
    setState(() {
      if (_currentSelections.contains(item)) {
        _currentSelections.remove(item);
      } else {
        _currentSelections.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
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
                  prefixIcon: const Icon(Icons.search, color: AppColors.textDim, size: 18),
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
                        final isSelected = widget.multiSelect 
                            ? _currentSelections.contains(item)
                            : item == widget.selectedValue;

                        Widget? prefix;
                        if (widget.itemPrefixIcon != null) {
                          prefix = widget.itemPrefixIcon!(item);
                        }

                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            leading: prefix,
                            title: Text(
                              widget.displayValue(item),
                              style: TextStyle(
                                color: isSelected ? AppColors.primary : AppColors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: AppColors.primary, size: 16)
                                : null,
                            onTap: () {
                              if (widget.multiSelect) {
                                _toggleSelection(item);
                              } else {
                                if (widget.onSelected != null) {
                                  widget.onSelected!(item);
                                }
                                Navigator.pop(context);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
            if (widget.multiSelect) ...[
              const SizedBox(height: 16),
              AppSaveButton(
                onPressed: () {
                  if (widget.onMultiSelected != null) {
                    widget.onMultiSelected!(_currentSelections);
                  }
                  Navigator.pop(context);
                },
                label: 'common.save',
                expand: true,
              )
            ]
          ],
        ),
      ),
    );
  }
}
