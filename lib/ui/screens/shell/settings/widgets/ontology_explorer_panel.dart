import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../../core/constants.dart';
import '../../../../../core/models/ontology_ui_models.dart';
import '../../../../widgets/app_styles.dart';

enum OntologyExplorerFilter { all, personal, governance, rules }

enum OntologyExplorerView { facts, nodes }

class OntologyExplorerPanel extends StatefulWidget {
  const OntologyExplorerPanel({
    super.key,
    required this.filter,
    required this.viewMode,
    required this.searchQuery,
    required this.loading,
    required this.listData,
    required this.onFilterChanged,
    required this.onViewModeChanged,
    required this.onSearchChanged,
    required this.onAddFactPressed,
    required this.onDeleteEdge,
    required this.onDeleteNode,
    required this.onInspectEntity,
  });

  final OntologyExplorerFilter filter;
  final OntologyExplorerView viewMode;
  final String searchQuery;
  final bool loading;
  final OntologyListResponseDto listData;
  final ValueChanged<OntologyExplorerFilter> onFilterChanged;
  final ValueChanged<OntologyExplorerView> onViewModeChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddFactPressed;
  final ValueChanged<OntologyTripleDto> onDeleteEdge;
  final ValueChanged<OntologyNodeDto> onDeleteNode;
  final ValueChanged<String> onInspectEntity;

  @override
  State<OntologyExplorerPanel> createState() => _OntologyExplorerPanelState();
}

class _OntologyExplorerPanelState extends State<OntologyExplorerPanel> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant OntologyExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchInput(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      widget.onSearchChanged(value);
    });
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    context.locale;
    final isRulesTab = widget.filter == OntologyExplorerFilter.rules;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Add Fact button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionLabel(
                      'settings.memory.ontology_explorer_title',
                    ),
                    Text(
                      'settings.memory.ontology_explorer_desc'.tr(),
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: widget.onAddFactPressed,
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'settings.memory.ontology_add_fact'.tr().toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Search + View Toggle
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchInput,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: AppConstants.fontSizeSmall,
                  ),
                  decoration: AppInputDecoration.compact(
                    hint: 'settings.memory.ontology_search_hint'.tr(),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 16,
                      color: AppColors.textDim,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.textDim,
                            ),
                            onPressed: () {
                              _debounce?.cancel();
                              _searchController.clear();
                              widget.onSearchChanged('');
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
              if (!isRulesTab) ...[
                const SizedBox(width: 10),
                _MonolithSegmentGroup<OntologyExplorerView>(
                  value: widget.viewMode,
                  onChanged: widget.onViewModeChanged,
                  items: [
                    (
                      value: OntologyExplorerView.facts,
                      label: 'settings.memory.ontology_view_facts'.tr(),
                    ),
                    (
                      value: OntologyExplorerView.nodes,
                      label: 'settings.memory.ontology_view_nodes'.tr(),
                    ),
                  ],
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // Filter Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FilterChip(
                label: 'settings.memory.ontology_filter_all'.tr(),
                count: widget.listData.stats.edges,
                selected: widget.filter == OntologyExplorerFilter.all,
                onTap: () => widget.onFilterChanged(OntologyExplorerFilter.all),
              ),
              _FilterChip(
                label: 'settings.memory.ontology_filter_personal'.tr(),
                count: widget.listData.stats.personalEdges,
                selected: widget.filter == OntologyExplorerFilter.personal,
                onTap: () =>
                    widget.onFilterChanged(OntologyExplorerFilter.personal),
              ),
              _FilterChip(
                label: 'settings.memory.ontology_filter_governance'.tr(),
                count: widget.listData.stats.governanceEdges,
                selected: widget.filter == OntologyExplorerFilter.governance,
                onTap: () =>
                    widget.onFilterChanged(OntologyExplorerFilter.governance),
              ),
              _FilterChip(
                label: 'settings.memory.ontology_filter_rules'.tr(),
                count: widget.listData.stats.relations,
                selected: widget.filter == OntologyExplorerFilter.rules,
                onTap: () =>
                    widget.onFilterChanged(OntologyExplorerFilter.rules),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else if (isRulesTab)
            _buildRelationsList()
          else if (widget.viewMode == OntologyExplorerView.nodes)
            _buildNodesList()
          else
            _buildFactsList(),
        ],
      ),
    );
  }

  Widget _buildFactsList() {
    final facts = widget.listData.facts;
    if (facts.isEmpty) {
      return _EmptyStateBox('settings.memory.ontology_empty'.tr());
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: facts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final fact = facts[index];
          return _FactRowTile(
            triple: fact,
            timestamp: _formatTimestamp(fact.createdAt),
            onInspectSubject: () => widget.onInspectEntity(
              fact.subjectKey.isNotEmpty ? fact.subjectKey : fact.subject,
            ),
            onDelete: fact.edgeId != null
                ? () => widget.onDeleteEdge(fact)
                : null,
          );
        },
      ),
    );
  }

  Widget _buildNodesList() {
    final nodes = widget.listData.nodes;
    if (nodes.isEmpty) {
      return _EmptyStateBox('settings.memory.ontology_empty_nodes'.tr());
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: nodes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final node = nodes[index];
          return _NodeRowTile(
            node: node,
            timestamp: _formatTimestamp(node.updatedAt),
            onInspect: () => widget.onInspectEntity(node.canonicalKey),
            onDelete: () => widget.onDeleteNode(node),
          );
        },
      ),
    );
  }

  Widget _buildRelationsList() {
    final relations = widget.listData.relations;
    if (relations.isEmpty) {
      return _EmptyStateBox('settings.memory.ontology_empty_rules'.tr());
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: relations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final rel = relations[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          rel.predicate,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMain,
                          ),
                        ),
                      ),
                      Text(
                        '${rel.domainType} → ${rel.rangeType}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    if (rel.isFunctional)
                      _MetaBadge(
                        label: 'settings.memory.ontology_rule_functional'
                            .tr()
                            .toUpperCase(),
                        highlight: true,
                      ),
                    if (rel.isTransitive)
                      _MetaBadge(
                        label: 'settings.memory.ontology_rule_transitive'
                            .tr()
                            .toUpperCase(),
                        highlight: true,
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FactRowTile extends StatelessWidget {
  const _FactRowTile({
    required this.triple,
    required this.timestamp,
    required this.onInspectSubject,
    this.onDelete,
  });

  final OntologyTripleDto triple;
  final String timestamp;
  final VoidCallback onInspectSubject;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // (Subject) —[PREDICATE]→ (Object)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Tooltip(
                      message: triple.subjectKey,
                      child: InkWell(
                        onTap: onInspectSubject,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '(${triple.subject})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMain,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 5),
                            _EntityTypeBadge(triple.subjectType),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '—[${triple.predicate}]→',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Tooltip(
                      message: triple.objectKey,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '(${triple.object})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 5),
                          _EntityTypeBadge(triple.objectType),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${(triple.confidence * 100).round()}% conf',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                    if (timestamp.isNotEmpty)
                      Text(
                        timestamp,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textDim,
                        ),
                      ),
                    if (triple.isGovernance)
                      _MetaBadge(
                        label: 'GOVERNANCE',
                        warning: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            _DeleteIconButton(onPressed: onDelete!),
          ],
        ],
      ),
    );
  }
}

class _NodeRowTile extends StatelessWidget {
  const _NodeRowTile({
    required this.node,
    required this.timestamp,
    required this.onInspect,
    required this.onDelete,
  });

  final OntologyNodeDto node;
  final String timestamp;
  final VoidCallback onInspect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      node.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                        fontSize: 13,
                      ),
                    ),
                    _EntityTypeBadge(node.entityType),
                    if (node.isGovernance)
                      const _MetaBadge(label: 'GOVERNANCE', warning: true),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      node.canonicalKey,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                    Text(
                      'settings.memory.ontology_node_edges'.tr(
                        namedArgs: {'count': '${node.edgeCount}'},
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                    if (timestamp.isNotEmpty)
                      Text(
                        timestamp,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textDim,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'settings.memory.ontology_inspector_run'.tr(),
            icon: const Icon(
              Icons.manage_search,
              size: 18,
              color: AppColors.textDim,
            ),
            onPressed: onInspect,
          ),
          _DeleteIconButton(onPressed: onDelete),
        ],
      ),
    );
  }
}

class _EntityTypeBadge extends StatelessWidget {
  const _EntityTypeBadge(this.type);
  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.textDim,
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.label,
    this.highlight = false,
    this.warning = false,
  });

  final String label;
  final bool highlight;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final borderColor = warning
        ? AppColors.warning.withValues(alpha: 0.5)
        : (highlight
            ? AppColors.primary.withValues(alpha: 0.5)
            : AppColors.border);
    final textColor = warning
        ? AppColors.warning
        : (highlight ? AppColors.primary : AppColors.textDim);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: textColor,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.background : AppColors.textMain,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.background.withValues(alpha: 0.75)
                    : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonolithSegmentGroup<T> extends StatelessWidget {
  const _MonolithSegmentGroup({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label})> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item.value == value;
          return InkWell(
            onTap: () => onChanged(item.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: isSelected ? AppColors.primary : AppColors.background,
              child: Text(
                item.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? AppColors.background : AppColors.textDim,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DeleteIconButton extends StatefulWidget {
  const _DeleteIconButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_DeleteIconButton> createState() => _DeleteIconButtonState();
}

class _DeleteIconButtonState extends State<_DeleteIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        color: _hovered ? Colors.redAccent : AppColors.textDim,
        onPressed: widget.onPressed,
      ),
    );
  }
}

class _EmptyStateBox extends StatelessWidget {
  const _EmptyStateBox(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      ),
    );
  }
}
