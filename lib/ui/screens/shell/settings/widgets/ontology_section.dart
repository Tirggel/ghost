import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants.dart';
import '../../../../../core/gateway.dart';
import '../../../../../providers/gateway_provider.dart';
import '../../../../widgets/app_dialogs.dart';
import '../../../../widgets/app_snackbar.dart';
import '../../../../widgets/app_styles.dart';
import 'ontology_add_fact_dialog.dart';
import 'ontology_explorer_panel.dart';
import 'ontology_query_inspector.dart';

class OntologySection extends ConsumerStatefulWidget {
  const OntologySection({
    super.key,
    required this.ontologyEnabled,
    required this.ontologyAutoExtract,
    required this.onToggleEnabled,
    required this.onToggleAutoExtract,
    required this.onClearOntology,
  });

  final bool ontologyEnabled;
  final bool ontologyAutoExtract;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<bool> onToggleAutoExtract;
  final Future<void> Function() onClearOntology;

  @override
  ConsumerState<OntologySection> createState() => _OntologySectionState();
}

class _OntologySectionState extends ConsumerState<OntologySection> {
  OntologyExplorerFilter _filter = OntologyExplorerFilter.all;
  OntologyExplorerView _viewMode = OntologyExplorerView.facts;
  String _searchQuery = '';
  bool _loadingList = false;
  OntologyListResponseDto _listData = const OntologyListResponseDto();

  final TextEditingController _inspectorController = TextEditingController();
  int _inspectorDepth = 2;
  bool _loadingQuery = false;
  OntologyQueryResponseDto? _queryResult;

  StreamSubscription<Map<String, dynamic>>? _gatewaySub;

  @override
  void initState() {
    super.initState();
    _subscribeToGatewayEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.ontologyEnabled) {
        _loadOntologyData();
      }
    });
  }

  @override
  void didUpdateWidget(covariant OntologySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ontologyEnabled && !oldWidget.ontologyEnabled) {
      _loadOntologyData();
    }
  }

  void _subscribeToGatewayEvents() {
    final client = ref.read(gatewayClientProvider);
    _gatewaySub = client.messages.listen((msg) {
      final method = msg['method'];
      if (method == 'ontology.changed' || method == 'skills.changed') {
        if (mounted && widget.ontologyEnabled) {
          _loadOntologyData();
        }
      }
    });
  }

  @override
  void dispose() {
    _gatewaySub?.cancel();
    _inspectorController.dispose();
    super.dispose();
  }

  String _categoryParam(OntologyExplorerFilter filter) {
    switch (filter) {
      case OntologyExplorerFilter.all:
        return 'all';
      case OntologyExplorerFilter.personal:
        return 'personal';
      case OntologyExplorerFilter.governance:
        return 'governance';
      case OntologyExplorerFilter.rules:
        return 'rules';
    }
  }

  Future<void> _loadOntologyData() async {
    final status = ref.read(connectionStatusProvider).value;
    if (status != ConnectionStatus.authenticated) return;

    setState(() => _loadingList = true);
    try {
      final data = await ref.read(configProvider.notifier).listOntology(
            category: _categoryParam(_filter),
            query: _searchQuery,
          );
      if (!mounted) return;
      setState(() {
        _listData = data;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingList = false);
    }
  }

  Future<void> _backupOntology() async {
    try {
      final data = await ref.read(configProvider.notifier).backupOntology();
      if (data == null) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'settings.memory.save_dialog_ontology'.tr(),
        fileName: 'ghost_ontology.json',
      );
      if (path != null) {
        await File(path).writeAsString(data);
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.ontology_backup_success'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.ontology_backup_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _restoreOntology() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final data = await File(result.files.single.path!).readAsString();
        await ref.read(configProvider.notifier).restoreOntology(data);
        await _loadOntologyData();
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'settings.memory.ontology_restore_success'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(
          context,
          'settings.memory.ontology_restore_failed'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _openAddFactDialog() async {
    final userName = ref.read(configProvider).user.name;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => OntologyAddFactDialog(
        relations: _listData.relations,
        primaryUserName: userName,
        onAssertFact: ({
          required String subject,
          required String predicate,
          required String object,
          required String subjectType,
          required String objectType,
          String? subjectKey,
          required double confidence,
        }) {
          return ref.read(configProvider.notifier).assertOntologyFact(
                subject: subject,
                predicate: predicate,
                object: object,
                subjectType: subjectType,
                objectType: objectType,
                subjectKey: subjectKey,
                confidence: confidence,
              );
        },
      ),
    );
    if (added == true && mounted) {
      await _loadOntologyData();
    }
  }

  Future<void> _confirmDeleteEdge(OntologyTripleDto triple) async {
    final edgeId = triple.edgeId;
    if (edgeId == null) return;

    final baseMsg = 'settings.memory.ontology_delete_edge_content'.tr(
      namedArgs: {
        'triple':
            '(${triple.subject}) —[${triple.predicate}]→ (${triple.object})',
      },
    );
    final content = triple.isGovernance
        ? '$baseMsg\n\n${'settings.memory.ontology_governance_resync_note'.tr()}'
        : baseMsg;

    final confirm = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.memory.ontology_delete_edge_title'.tr(),
      content: content,
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(configProvider.notifier).deleteOntologyEdge(edgeId);
      await _loadOntologyData();
      if (_queryResult != null && _inspectorController.text.trim().isNotEmpty) {
        await _runQuery(_inspectorController.text);
      }
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.memory.ontology_edge_deleted'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(context, e.toString());
      }
    }
  }

  Future<void> _confirmDeleteNode(OntologyNodeDto node) async {
    final baseMsg = 'settings.memory.ontology_delete_node_content'.tr(
      namedArgs: {
        'label': node.label,
        'key': node.canonicalKey,
        'count': '${node.edgeCount}',
      },
    );
    final content = node.isGovernance
        ? '$baseMsg\n\n${'settings.memory.ontology_governance_resync_note'.tr()}'
        : baseMsg;

    final confirm = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.memory.ontology_delete_node_title'.tr(),
      content: content,
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;

    try {
      await ref
          .read(configProvider.notifier)
          .deleteOntologyNode(node.canonicalKey);
      await _loadOntologyData();
      if (_queryResult != null && _inspectorController.text.trim().isNotEmpty) {
        await _runQuery(_inspectorController.text);
      }
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.memory.ontology_node_deleted'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(context, e.toString());
      }
    }
  }

  Future<void> _runQuery(String rawEntity) async {
    final entity = rawEntity.trim();
    if (entity.isEmpty) return;

    setState(() => _loadingQuery = true);
    try {
      final result = await ref
          .read(configProvider.notifier)
          .queryOntologyEntity(entity, maxDepth: _inspectorDepth);
      if (!mounted) return;
      setState(() {
        _queryResult = result;
        _loadingQuery = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingQuery = false);
      showAppErrorDialog(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale;
    ref.listen(connectionStatusProvider, (prev, next) {
      if (next.value == ConnectionStatus.authenticated &&
          prev?.value != ConnectionStatus.authenticated &&
          widget.ontologyEnabled) {
        _loadOntologyData();
      }
    });
    final system1Active = ref.watch(
      configProvider.select((c) => c.security.system1Middleware),
    );
    final primaryUserName = ref.watch(
      configProvider.select((c) => c.user.name),
    );
    final stats = _listData.stats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader('settings.memory.ontology_section', large: true),
        Text(
          'settings.memory.ontology_desc'.tr(),
          style: const TextStyle(color: AppColors.textDim),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),

        // Toggle: ontologyEnabled
        AppSwitchListTile(
          title: Text(
            'settings.memory.ontology_enable'.tr().toUpperCase(),
            style: const TextStyle(
              fontSize: AppConstants.fontSizeLabelTiny,
              fontWeight: FontWeight.w900,
            ),
          ),
          value: widget.ontologyEnabled,
          onChanged: widget.onToggleEnabled,
        ),

        // Indented Toggle: ontologyAutoExtract + System-1 pause hint
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          child: Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.border, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSwitchListTile(
                  title: Text(
                    'settings.memory.ontology_auto_extract'.tr(),
                    style: TextStyle(
                      color: widget.ontologyEnabled
                          ? AppColors.textMain
                          : AppColors.textDim,
                      fontSize: AppConstants.fontSizeBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'settings.memory.ontology_auto_extract_desc'.tr(),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                  value: widget.ontologyEnabled && widget.ontologyAutoExtract,
                  onChanged: widget.ontologyEnabled
                      ? widget.onToggleAutoExtract
                      : null,
                ),
                if (widget.ontologyEnabled &&
                    widget.ontologyAutoExtract &&
                    !system1Active)
                  Container(
                    margin: const EdgeInsets.only(top: 6, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.45),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'settings.memory.ontology_system1_paused_hint'.tr(),
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppConstants.settingsElementSpacing),

        // Live Stats KPI Grid
        Row(
          children: [
            const Expanded(
              child: AppSectionLabel('settings.memory.ontology_stats_title'),
            ),
            IconButton(
              tooltip: 'common.refresh'.tr(),
              icon: const Icon(
                Icons.refresh,
                size: 16,
                color: AppColors.textDim,
              ),
              onPressed: widget.ontologyEnabled ? _loadOntologyData : null,
            ),
          ],
        ),
        _OntologyStatsGrid(stats: stats),

        const SizedBox(height: AppConstants.settingsElementSpacing),

        // Backup / Restore / Reset action row
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: widget.ontologyEnabled ? _backupOntology : null,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text('settings.memory.backup'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.border,
                      foregroundColor: AppColors.textMain,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: widget.ontologyEnabled ? _restoreOntology : null,
                    icon: const Icon(Icons.upload, size: 18),
                    label: Text('settings.memory.restore'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.border,
                      foregroundColor: AppColors.textMain,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: widget.ontologyEnabled
                    ? () async {
                        await widget.onClearOntology();
                        if (mounted) {
                          await _loadOntologyData();
                          if (_queryResult != null &&
                              _inspectorController.text.trim().isNotEmpty) {
                            await _runQuery(_inspectorController.text);
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_forever, size: 18),
                label: Text('settings.memory.ontology_reset_button'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.border,
                  foregroundColor: AppColors.textMain,
                ).copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                    states,
                  ) {
                    if (states.contains(WidgetState.hovered)) {
                      return Colors.red.withValues(alpha: 0.1);
                    }
                    return AppColors.border;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                    states,
                  ) {
                    if (states.contains(WidgetState.hovered)) {
                      return Colors.redAccent;
                    }
                    return AppColors.textMain;
                  }),
                  side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return BorderSide(
                        color: Colors.red.withValues(alpha: 0.2),
                      );
                    }
                    return const BorderSide(color: Colors.transparent);
                  }),
                ),
              ),
            ],
          ),
        ),

        if (widget.ontologyEnabled) ...[
          const SizedBox(height: AppConstants.settingsContentSpacing),

          // Explorer Panel
          OntologyExplorerPanel(
            filter: _filter,
            viewMode: _viewMode,
            searchQuery: _searchQuery,
            loading: _loadingList,
            listData: _listData,
            onFilterChanged: (next) {
              setState(() => _filter = next);
              _loadOntologyData();
            },
            onViewModeChanged: (next) {
              setState(() => _viewMode = next);
            },
            onSearchChanged: (q) {
              setState(() => _searchQuery = q);
              _loadOntologyData();
            },
            onAddFactPressed: _openAddFactDialog,
            onDeleteEdge: _confirmDeleteEdge,
            onDeleteNode: _confirmDeleteNode,
            onInspectEntity: (entity) {
              _inspectorController.text = entity;
              _runQuery(entity);
            },
          ),

          const SizedBox(height: AppConstants.settingsElementSpacing),

          // Interactive Multi-Hop Test (Query Inspector)
          OntologyQueryInspector(
            controller: _inspectorController,
            maxDepth: _inspectorDepth,
            loading: _loadingQuery,
            result: _queryResult,
            primaryUserName: primaryUserName,
            onMaxDepthChanged: (d) {
              setState(() => _inspectorDepth = d);
              if (_inspectorController.text.trim().isNotEmpty) {
                _runQuery(_inspectorController.text);
              }
            },
            onRunQuery: _runQuery,
          ),
        ],
      ],
    );
  }
}

class _OntologyStatsGrid extends StatelessWidget {
  const _OntologyStatsGrid({required this.stats});
  final OntologyStatsDto stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiCard(
        label: 'settings.memory.ontology_stats_nodes'.tr(),
        value: '${stats.nodes}',
        icon: Icons.circle_outlined,
      ),
      _KpiCard(
        label: 'settings.memory.ontology_stats_edges'.tr(),
        value: '${stats.edges}',
        icon: Icons.compare_arrows,
      ),
      _KpiCard(
        label: 'settings.memory.ontology_stats_relations'.tr(),
        value: '${stats.relations}',
        icon: Icons.rule,
      ),
      _KpiCard(
        label: 'settings.memory.ontology_stats_skills'.tr(),
        value: '${stats.linkedSkills}',
        sublabel: 'settings.memory.ontology_stats_skills_installed'.tr(
          namedArgs: {'count': '${stats.skills}'},
        ),
        icon: Icons.extension_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 560;
        if (isWide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 8),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 8),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 8),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.sublabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDim,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
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
