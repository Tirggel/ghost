// Ghost — Monolith Competency Tags Editor widget.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../engine/agent/ontology/agent_domain_taxonomy.dart';
import 'app_styles.dart';

/// Monolith-styled tag editor for selecting preset domain competencies and
/// adding custom competency tags, plus displaying automatically inferred tags.
class CompetencyTagsEditor extends StatefulWidget {
  const CompetencyTagsEditor({
    super.key,
    required this.selectedTags,
    required this.onChanged,
    this.derivedTags = const [],
    this.label = 'settings.agents.competencies_label',
    this.hint = 'settings.agents.competencies_custom_hint',
  });

  final List<String> selectedTags;
  final ValueChanged<List<String>> onChanged;
  final List<String> derivedTags;
  final String label;
  final String hint;

  @override
  State<CompetencyTagsEditor> createState() => _CompetencyTagsEditorState();
}

class _CompetencyTagsEditorState extends State<CompetencyTagsEditor> {
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  bool _containsEquivalent(Iterable<String> tags, String candidate) {
    final targetKey = AgentDomainTaxonomy.canonicalDomainKey(candidate);
    return tags.any((t) => AgentDomainTaxonomy.canonicalDomainKey(t) == targetKey);
  }

  void _toggleTag(String tag) {
    final targetKey = AgentDomainTaxonomy.canonicalDomainKey(tag);
    final next = List<String>.from(widget.selectedTags);
    final existingIndex = next.indexWhere(
      (t) => AgentDomainTaxonomy.canonicalDomainKey(t) == targetKey,
    );
    if (existingIndex != -1) {
      next.removeAt(existingIndex);
    } else {
      next.add(tag);
    }
    widget.onChanged(next);
  }

  void _addCustomTag() {
    final raw = _customCtrl.text.trim();
    if (raw.isEmpty) return;
    if (!_containsEquivalent(widget.selectedTags, raw)) {
      widget.onChanged([...widget.selectedTags, raw]);
    }
    _customCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode;
    final presets = AgentDomainTaxonomy.presetLabels(languageCode: lang);
    final customSelected = widget.selectedTags
        .where((tag) => !_containsEquivalent(presets, tag))
        .toList();
    final remainingDerived = widget.derivedTags
        .where((tag) => !_containsEquivalent(widget.selectedTags, tag))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.settingsElementSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormLabel(widget.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...presets.map((preset) {
                final active = _containsEquivalent(widget.selectedTags, preset);
                return _MonolithTagChip(
                  label: preset,
                  active: active,
                  onTap: () => _toggleTag(preset),
                );
              }),
              ...customSelected.map((custom) {
                return _MonolithTagChip(
                  label: custom,
                  active: true,
                  removable: true,
                  onTap: () => _toggleTag(custom),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: AppConstants.fontSizeSmall,
                  ),
                  decoration: AppInputDecoration.compact(
                    hint: widget.hint.tr(),
                  ),
                  onSubmitted: (_) => _addCustomTag(),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _addCustomTag,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (remainingDerived.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'settings.agents.competencies_derived_hint'.tr().toUpperCase(),
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: remainingDerived
                  .map(
                    (tag) => _MonolithTagChip(
                      label: tag,
                      active: false,
                      derived: true,
                      onTap: () => _toggleTag(tag),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonolithTagChip extends StatelessWidget {
  const _MonolithTagChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.removable = false,
    this.derived = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool removable;
  final bool derived;

  @override
  Widget build(BuildContext context) {
    final borderColor = active
        ? AppColors.primary
        : (derived ? AppColors.border.withValues(alpha: 0.6) : AppColors.border);
    final bgColor = active
        ? AppColors.primary.withValues(alpha: 0.14)
        : (derived ? AppColors.background : AppColors.surface);
    final textColor = active
        ? AppColors.primary
        : (derived ? AppColors.textDim : AppColors.textMain);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 1),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (derived) ...[
              const Icon(Icons.auto_awesome, size: 11, color: AppColors.textDim),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            if (removable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.close, size: 12, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}
