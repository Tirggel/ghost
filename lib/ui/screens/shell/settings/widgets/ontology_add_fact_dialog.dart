import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../../core/constants.dart';
import '../../../../../core/models/ontology_ui_models.dart';
import '../../../../widgets/app_dialogs.dart';
import '../../../../widgets/app_snackbar.dart';
import '../../../../widgets/app_styles.dart';

typedef OntologyAssertCallback = Future<Map<String, dynamic>> Function({
  required String subject,
  required String predicate,
  required String object,
  required String subjectType,
  required String objectType,
  String? subjectKey,
  required double confidence,
});

class OntologyAddFactDialog extends StatefulWidget {
  const OntologyAddFactDialog({
    super.key,
    required this.relations,
    required this.primaryUserName,
    required this.onAssertFact,
  });

  final List<OntologyRelationDto> relations;
  final String primaryUserName;
  final OntologyAssertCallback onAssertFact;

  @override
  State<OntologyAddFactDialog> createState() => _OntologyAddFactDialogState();
}

class _OntologyAddFactDialogState extends State<OntologyAddFactDialog> {
  final _subjectController = TextEditingController();
  final _predicateController = TextEditingController();
  final _objectController = TextEditingController();

  String? _explicitSubjectKey;
  String _subjectType = 'Entity';
  String _objectType = 'Entity';
  double _confidence = 1.0;
  bool _showAdvanced = false;
  bool _submitting = false;

  static const List<String> _entityTypes = [
    'Entity',
    'Person',
    'Place',
    'Project',
    'Organization',
    'Technology',
    'Role',
    'Language',
    'Text',
  ];

  static const List<String> _fallbackPredicates = [
    'WOHNT_IN',
    'ARBEITET_AN',
    'ARBEITET_BEI',
    'LIEGT_IN',
    'MAG',
    'BENUTZT',
    'HAT_BERUF',
    'SPRICHT',
    'KENNT',
  ];

  @override
  void dispose() {
    _subjectController.dispose();
    _predicateController.dispose();
    _objectController.dispose();
    super.dispose();
  }

  String _normalizePredicate(String raw) {
    var s = raw.trim().toUpperCase();
    s = s
        .replaceAll('Ä', 'AE')
        .replaceAll('Ö', 'OE')
        .replaceAll('Ü', 'UE')
        .replaceAll('ß', 'SS');
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  void _applyPrimaryUserShortcut() {
    final label = widget.primaryUserName.trim().isNotEmpty
        ? widget.primaryUserName.trim()
        : 'user:primary';
    setState(() {
      _subjectController.text = label;
      _explicitSubjectKey = 'user:primary';
      _subjectType = 'Person';
    });
  }

  void _applyPredicatePreset(String predicate) {
    final def = widget.relations
        .where((r) => r.predicate == predicate)
        .firstOrNull;
    setState(() {
      _predicateController.text = predicate;
      if (def != null) {
        if (_explicitSubjectKey != 'user:primary') {
          _subjectType = def.domainType;
        }
        _objectType = def.rangeType;
      }
    });
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final predicate = _normalizePredicate(_predicateController.text);
    final object = _objectController.text.trim();

    if (subject.isEmpty || predicate.isEmpty || object.isEmpty) {
      AppSnackBar.showError(
        context,
        'settings.memory.ontology_dialog_validation'.tr(),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await widget.onAssertFact(
        subject: subject,
        predicate: predicate,
        object: object,
        subjectType: _subjectType,
        objectType: _objectType,
        subjectKey: _explicitSubjectKey,
        confidence: _confidence,
      );
      if (!mounted) return;
      final replaced =
          (res['result'] is Map ? (res['result'] as Map)['replacedCount'] : 0)
                  as num? ??
              0;
      Navigator.of(context).pop(true);
      AppSnackBar.showSuccess(
        context,
        replaced > 0
            ? 'settings.memory.ontology_fact_replaced'.tr(
                namedArgs: {'count': '$replaced'},
              )
            : 'settings.memory.ontology_fact_added'.tr(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppErrorDialog(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final presetSet = <String>{
      ...widget.relations
          .where(
            (r) => !const {
              'DARF_NUTZEN',
              'GEHOERT_ZU_DOMAIN',
              'BENOETIGT_SKILL',
              'ERFORDERT_HITL',
            }.contains(r.predicate),
          )
          .map((r) => r.predicate),
      ..._fallbackPredicates,
    };
    final presetPredicates = presetSet.take(9).toList();

    final normalizedPreview = _normalizePredicate(_predicateController.text);

    return AppAlertDialog(
      title: Row(
        children: [
          const Icon(Icons.hub_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Text('settings.memory.ontology_add_fact'.tr()),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subject + Quick user:primary chip
              AppFormField.text(
                controller: _subjectController,
                label: 'settings.memory.ontology_dialog_subject',
                hint: 'settings.memory.ontology_dialog_subject_hint',
                onChanged: (_) {
                  if (_explicitSubjectKey != null) {
                    setState(() => _explicitSubjectKey = null);
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MonolithQuickChip(
                      label: widget.primaryUserName.trim().isNotEmpty
                          ? 'user:primary (${widget.primaryUserName.trim()})'
                          : 'user:primary',
                      isActive: _explicitSubjectKey == 'user:primary',
                      onTap: _applyPrimaryUserShortcut,
                    ),
                  ],
                ),
              ),

              // Predicate + T-Box preset chips
              AppFormField.text(
                controller: _predicateController,
                label: 'settings.memory.ontology_dialog_predicate',
                hint: 'settings.memory.ontology_dialog_predicate_hint',
                onChanged: (_) => setState(() {}),
              ),
              if (normalizedPreview.isNotEmpty &&
                  normalizedPreview != _predicateController.text.trim())
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '→ $normalizedPreview',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presetPredicates
                      .map(
                        (p) => _MonolithQuickChip(
                          label: p,
                          monospace: true,
                          isActive: normalizedPreview == p,
                          onTap: () => _applyPredicatePreset(p),
                        ),
                      )
                      .toList(),
                ),
              ),

              // Object
              AppFormField.text(
                controller: _objectController,
                label: 'settings.memory.ontology_dialog_object',
                hint: 'settings.memory.ontology_dialog_object_hint',
                onSubmitted: (_) => _submitting ? null : _submit(),
              ),

              // Advanced toggle
              InkWell(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 16,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'settings.memory.ontology_dialog_advanced'
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
              ),
              if (_showAdvanced) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppFormLabel('settings.memory.ontology_dialog_subject_type'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _entityTypes
                            .map(
                              (t) => _MonolithQuickChip(
                                label: t,
                                isActive: _subjectType == t,
                                onTap: () => setState(() => _subjectType = t),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      AppFormLabel('settings.memory.ontology_dialog_object_type'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _entityTypes
                            .map(
                              (t) => _MonolithQuickChip(
                                label: t,
                                isActive: _objectType == t,
                                onTap: () => setState(() => _objectType = t),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const AppFormLabel(
                            'settings.memory.ontology_dialog_confidence',
                          ),
                          Text(
                            '${(_confidence * 100).round()}%',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AppColors.textMain,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _confidence,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.surfaceLight,
                        onChanged: (v) => setState(() => _confidence = v),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'common.cancel'.tr(),
            style: const TextStyle(color: AppColors.textDim),
          ),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.background,
                  ),
                )
              : Text(
                  'common.save'.tr().toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
        ),
      ],
    );
  }
}

class _MonolithQuickChip extends StatelessWidget {
  const _MonolithQuickChip({
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.monospace = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surface,
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: monospace ? 'monospace' : null,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppColors.background : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
