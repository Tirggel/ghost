import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../../core/constants.dart';
import '../../../../../core/models/ontology_ui_models.dart';
import '../../../../widgets/app_styles.dart';

class OntologyQueryInspector extends StatefulWidget {
  const OntologyQueryInspector({
    super.key,
    required this.controller,
    required this.maxDepth,
    required this.loading,
    required this.result,
    required this.primaryUserName,
    required this.onMaxDepthChanged,
    required this.onRunQuery,
  });

  final TextEditingController controller;
  final int maxDepth;
  final bool loading;
  final OntologyQueryResponseDto? result;
  final String primaryUserName;
  final ValueChanged<int> onMaxDepthChanged;
  final ValueChanged<String> onRunQuery;

  @override
  State<OntologyQueryInspector> createState() => _OntologyQueryInspectorState();
}

class _OntologyQueryInspectorState extends State<OntologyQueryInspector> {
  bool _showPromptPreview = true;

  @override
  Widget build(BuildContext context) {
    context.locale;
    final res = widget.result;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionLabel('settings.memory.ontology_inspector_title'),
          Text(
            'settings.memory.ontology_inspector_desc'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // Input + Depth + Run button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  onSubmitted: (v) => widget.onRunQuery(v),
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: AppConstants.fontSizeSmall,
                  ),
                  decoration: AppInputDecoration.compact(
                    hint: 'settings.memory.ontology_inspector_hint'.tr(),
                    prefixIcon: const Icon(
                      Icons.manage_search,
                      size: 16,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _DepthSelector(
                depth: widget.maxDepth,
                onChanged: widget.onMaxDepthChanged,
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: widget.loading
                    ? null
                    : () => widget.onRunQuery(widget.controller.text),
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
                child: widget.loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : Text(
                        'settings.memory.ontology_inspector_run'
                            .tr()
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick test chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickQueryChip(
                label: 'user:primary',
                onTap: () {
                  widget.controller.text = 'user:primary';
                  widget.onRunQuery('user:primary');
                },
              ),
              if (widget.primaryUserName.trim().isNotEmpty)
                _QuickQueryChip(
                  label: widget.primaryUserName.trim(),
                  onTap: () {
                    final name = widget.primaryUserName.trim();
                    widget.controller.text = name;
                    widget.onRunQuery(name);
                  },
                ),
            ],
          ),

          if (res != null) ...[
            const SizedBox(height: 14),
            if (res.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  'settings.memory.ontology_inspector_empty'.tr(
                    namedArgs: {'query': res.query},
                  ),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              )
            else ...[
              // Matched root nodes
              if (res.rootNodes.isNotEmpty) ...[
                Text(
                  'settings.memory.ontology_inspector_roots'
                      .tr()
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeLabelTiny,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: res.rootNodes
                      .map(
                        (n) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '${n.label} [${n.entityType}] (${n.canonicalKey})',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppColors.textMain,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Direct facts
              if (res.directFacts.isNotEmpty) ...[
                Text(
                  'settings.memory.ontology_inspector_direct'
                      .tr(namedArgs: {'count': '${res.directFacts.length}'})
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeLabelTiny,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                ...res.directFacts.map(
                  (f) => _InspectorTripleLine(triple: f),
                ),
                const SizedBox(height: 10),
              ],

              // Transitive / Inferred facts
              if (res.inferredFacts.isNotEmpty) ...[
                Text(
                  'settings.memory.ontology_inspector_inferred'
                      .tr(namedArgs: {'count': '${res.inferredFacts.length}'})
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeLabelTiny,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                ...res.inferredFacts.map(
                  (f) => _InspectorTripleLine(triple: f, isInferred: true),
                ),
                const SizedBox(height: 10),
              ],

              // Pre-turn prompt context preview
              if (res.promptPreview.isNotEmpty) ...[
                InkWell(
                  onTap: () =>
                      setState(() => _showPromptPreview = !_showPromptPreview),
                  child: Row(
                    children: [
                      Icon(
                        _showPromptPreview
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 16,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'settings.memory.ontology_inspector_prompt_preview'
                            .tr()
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: AppConstants.fontSizeLabelTiny,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showPromptPreview) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: SelectableText(
                      res.promptPreview,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.45,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _InspectorTripleLine extends StatelessWidget {
  const _InspectorTripleLine({
    required this.triple,
    this.isInferred = false,
  });

  final OntologyTripleDto triple;
  final bool isInferred;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isInferred)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Text(
                    '${triple.hopDepth}-HOP',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              Text(
                '(${triple.subject}) —[${triple.predicate}]→ (${triple.object})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                ),
              ),
              Text(
                '${(triple.confidence * 100).round()}%',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
          if (isInferred && triple.pathChain.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'via ${triple.pathChain.join(' -> ')}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DepthSelector extends StatelessWidget {
  const _DepthSelector({required this.depth, required this.onChanged});
  final int depth;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [1, 2, 3, 4].map((d) {
          final active = depth == d;
          return InkWell(
            onTap: () => onChanged(d),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              color: active ? AppColors.primary : AppColors.background,
              child: Text(
                '${d}H',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: active ? AppColors.background : AppColors.textDim,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _QuickQueryChip extends StatelessWidget {
  const _QuickQueryChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
