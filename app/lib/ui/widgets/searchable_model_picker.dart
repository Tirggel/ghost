import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';
import 'app_styles.dart';

class SearchableModelPicker extends StatefulWidget {
  final String? selectedModel;
  final List<String> models;
  final Function(String) onSelected;
  final String label;
  final String hint;
  final bool loading;

  const SearchableModelPicker({
    super.key,
    required this.selectedModel,
    required this.models,
    required this.onSelected,
    required this.label,
    required this.hint,
    this.loading = false,
  });

  @override
  State<SearchableModelPicker> createState() => _SearchableModelPickerState();
}

class _SearchableModelPickerState extends State<SearchableModelPicker> {
  bool _hasFocus = false;

  void _openSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => _ModelSearchDialog(
        models: widget.models,
        selectedModel: widget.selectedModel,
        onSelected: widget.onSelected,
        title: widget.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayModel = widget.selectedModel != null
        ? (widget.selectedModel!.contains('/')
              ? widget.selectedModel!.split('/').last
              : widget.selectedModel)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 2,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 2,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            ),
          ),
        Focus(
          onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
          child: GestureDetector(
            onTap: widget.loading || widget.models.isEmpty
                ? null
                : _openSearchDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _hasFocus ? AppColors.primary : AppColors.white,
                  width: _hasFocus ? 1.5 : 1.0,
                ),
                borderRadius: BorderRadius.circular(
                  AppConstants.buttonBorderRadius,
                ),
                color: AppColors.black,
              ),
              child: Row(
                children: [
                  if (widget.selectedModel != null &&
                      widget.selectedModel!.contains('/'))
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Image.asset(
                        AppConstants.getProviderIcon(
                          widget.selectedModel!.split('/').first,
                        ),
                        width: 18,
                        height: 18,
                        errorBuilder: (_, _, _) =>
                            const SizedBox(width: 18, height: 18),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      displayModel ?? widget.hint.tr(),
                      style: TextStyle(
                        color: displayModel != null
                            ? AppColors.white
                            : AppColors.textDim,
                        fontSize: AppConstants.fontSizeBody,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textDim,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelSearchDialog extends StatefulWidget {
  final List<String> models;
  final String? selectedModel;
  final Function(String) onSelected;
  final String title;

  const _ModelSearchDialog({
    required this.models,
    required this.selectedModel,
    required this.onSelected,
    required this.title,
  });

  @override
  State<_ModelSearchDialog> createState() => _ModelSearchDialogState();
}

class _ModelSearchDialogState extends State<_ModelSearchDialog> {
  final _searchController = TextEditingController();
  List<String> _filteredModels = [];

  @override
  void initState() {
    super.initState();
    _sortAndFilter();
    _searchController.addListener(_sortAndFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Patterns that identify embedding-only models (not suitable for chat).
  static const _embeddingModelPatterns = [
    //'embed', // mistral-embed, mistral-embed-2312
    //'text-embedding', // text-embedding-3-small, text-embedding-004
    //'embedding', // deepseek-embedding
    //'ada-002', // text-ada-002 (old OpenAI embed)
  ];

  static bool _isEmbeddingModel(String modelId) {
    final lower = modelId.toLowerCase();
    return _embeddingModelPatterns.any((p) => lower.contains(p));
  }

  void _sortAndFilter() {
    final query = _searchController.text.toLowerCase();
    final List<String> filtered = widget.models.where((m) {
      // Always exclude known embedding-only models from the chat picker
      if (_isEmbeddingModel(m)) return false;
      final label = m.contains('/') ? m.split('/').last : m;
      return label.toLowerCase().contains(query) ||
          m.toLowerCase().contains(query);
    }).toList();

    // Sort alphabetically by display label
    filtered.sort((a, b) {
      final labelA = a.contains('/') ? a.split('/').last : a;
      final labelB = b.contains('/') ? b.split('/').last : b;
      return labelA.toLowerCase().compareTo(labelB.toLowerCase());
    });

    setState(() {
      _filteredModels = filtered;
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
                    widget.title.tr(),
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
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: AppColors.white, fontSize: 13),
              decoration:
                  AppInputDecoration.compact(
                    hint: 'sidebar.search_placeholder',
                  ).copyWith(
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textDim,
                      size: 18,
                    ),
                    fillColor: AppColors.surface,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredModels.isEmpty
                  ? Center(
                      child: Text(
                        'common.no_results'.tr(),
                        style: const TextStyle(color: AppColors.textDim),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredModels.length,
                      itemBuilder: (context, index) {
                        final m = _filteredModels[index];
                        final isSelected = m == widget.selectedModel;
                        final label = m.contains('/') ? m.split('/').last : m;

                        final providerId = m.contains('/')
                            ? m.split('/').first
                            : null;

                        return ListTile(
                          leading: providerId != null
                              ? Image.asset(
                                  AppConstants.getProviderIcon(providerId),
                                  width: 20,
                                  height: 20,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.cloud_queue,
                                    size: 20,
                                    color: AppColors.textDim,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_queue,
                                  size: 20,
                                  color: AppColors.textDim,
                                ),
                          title: Text(
                            label,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: m.contains('/')
                              ? Text(
                                  m.split('/').first,
                                  style: const TextStyle(
                                    color: AppColors.textDim,
                                    fontSize: 10,
                                  ),
                                )
                              : null,
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                  size: 16,
                                )
                              : null,
                          onTap: () {
                            widget.onSelected(m);
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
