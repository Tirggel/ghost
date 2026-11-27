import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../engine/automations/automation_models.dart';
import '../../../providers/automations_provider.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_styles.dart';
import 'widgets/create_automation_dialog.dart';
import 'widgets/create_with_prompt_dialog.dart';

/// Main Automations overview screen ("The Monolith" tabular/list layout).
class AutomationsOverview extends ConsumerStatefulWidget {
  const AutomationsOverview({super.key});

  @override
  ConsumerState<AutomationsOverview> createState() =>
      _AutomationsOverviewState();
}

class _AutomationsOverviewState extends ConsumerState<AutomationsOverview> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(automationsSearchQueryProvider);
    _searchCtrl.addListener(() {
      if (mounted) {
        ref
            .read(automationsSearchQueryProvider.notifier)
            .setQuery(_searchCtrl.text);
      }
    });
    Future.microtask(() {
      ref.read(automationsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreateWithPrompt() async {
    final createdId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateWithPromptDialog(),
    );
    if (createdId != null && mounted) {
      ref.read(selectedAutomationIdProvider.notifier).select(createdId);
      ref.read(automationsProvider.notifier).loadDetail(createdId);
    }
  }

  Future<void> _openCreateManual() async {
    final createdId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateAutomationDialog(),
    );
    if (createdId != null && mounted) {
      ref.read(selectedAutomationIdProvider.notifier).select(createdId);
      ref.read(automationsProvider.notifier).loadDetail(createdId);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale;
    final state = ref.watch(automationsProvider);
    final filtered = ref.watch(filteredAutomationsProvider);
    final query = ref.watch(automationsSearchQueryProvider);
    final config = ref.watch(configProvider);
    final localeCode = context.locale.languageCode;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bolt_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'automations.title'.tr().toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: AppConstants.fontSizeTitle,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${filtered.length}',
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: AppConstants.fontSizeLabelTiny,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                // Search bar
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                      ),
                      decoration: AppInputDecoration.compact(
                        hint: 'automations.search_hint'.tr(),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 18,
                          color: AppColors.textDim,
                        ),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: AppColors.textDim,
                                ),
                                onPressed: () => _searchCtrl.clear(),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const Spacer(),

                // Two primary actions top-right
                AppActionButton(
                  label: 'automations.create_with_prompt',
                  icon: Icons.auto_awesome_outlined,
                  isPrimary: false,
                  onPressed: _openCreateWithPrompt,
                ),
                const SizedBox(width: 10),
                AppActionButton(
                  label: 'automations.new_button',
                  icon: Icons.add,
                  isPrimary: true,
                  onPressed: _openCreateManual,
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: state.isLoading && state.items.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : filtered.isEmpty
                    ? _buildEmptyState(hasQuery: query.isNotEmpty)
                    : _buildTable(filtered, config, localeCode),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required bool hasQuery}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.bolt_outlined,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                (hasQuery
                        ? 'automations.empty_search_title'
                        : 'automations.empty_title')
                    .tr()
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: AppConstants.fontSizeTitle,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                (hasQuery
                        ? 'automations.empty_search_desc'
                        : 'automations.empty_desc')
                    .tr(),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: AppConstants.fontSizeBody,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (!hasQuery) ...[
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    AppActionButton(
                      label: 'automations.create_with_prompt',
                      icon: Icons.auto_awesome_outlined,
                      isPrimary: false,
                      onPressed: _openCreateWithPrompt,
                    ),
                    AppActionButton(
                      label: 'automations.new_button',
                      icon: Icons.add,
                      isPrimary: true,
                      onPressed: _openCreateManual,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable(
    List<AutomationListItem> items,
    AppConfig config,
    String localeCode,
  ) {
    return Column(
      children: [
        // Table Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  'automations.col_title'.tr().toUpperCase(),
                  style: _headerTextStyle,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'automations.col_schedule'.tr().toUpperCase(),
                  style: _headerTextStyle,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'automations.col_next_run'.tr().toUpperCase(),
                  style: _headerTextStyle,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'automations.col_last_run'.tr().toUpperCase(),
                  style: _headerTextStyle,
                ),
              ),
              SizedBox(
                width: 80,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'automations.col_active'.tr().toUpperCase(),
                    style: _headerTextStyle,
                  ),
                ),
              ),
            ],
          ),
        ),

        // List rows
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _AutomationRow(
                item: item,
                config: config,
                localeCode: localeCode,
                onTap: () {
                  ref
                      .read(selectedAutomationIdProvider.notifier)
                      .select(item.automation.id);
                  ref
                      .read(automationsProvider.notifier)
                      .loadDetail(item.automation.id);
                },
                onToggle: (val) async {
                  try {
                    await ref
                        .read(automationsProvider.notifier)
                        .toggle(item.automation.id, val);
                  } catch (e) {
                    if (context.mounted) {
                      AppSnackBar.showError(context, e.toString());
                    }
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static const TextStyle _headerTextStyle = TextStyle(
    color: AppColors.textDim,
    fontSize: AppConstants.fontSizeLabelTiny,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.8,
  );
}

class _AutomationRow extends StatelessWidget {
  const _AutomationRow({
    required this.item,
    required this.config,
    required this.localeCode,
    required this.onTap,
    required this.onToggle,
  });

  final AutomationListItem item;
  final AppConfig config;
  final String localeCode;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  String _agentLabel() {
    final a = item.automation;
    if (a.isAutoRouting) {
      return '🧭 ${'automations.auto_ontology'.tr()}';
    }
    if (a.agentId == 'default-agent') {
      return '👻 ${config.identity.name}';
    }
    final custom = config.customAgents
        .where((c) => c.id == a.agentId)
        .firstOrNull;
    return '🤖 ${custom?.name ?? a.agentName ?? a.agentId}';
  }

  @override
  Widget build(BuildContext context) {
    final a = item.automation;
    final nextRunText = !a.enabled
        ? 'automations.status_paused'.tr()
        : (item.nextRunAt != null
            ? _formatNextRun(item.nextRunAt!, localeCode)
            : '—');

    return AppHoverCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Title + instruction snippet + agent badge
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (item.isRunning) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          a.title,
                          style: TextStyle(
                            color: a.enabled
                                ? AppColors.textMain
                                : AppColors.textDim,
                            fontSize: AppConstants.fontSizeSubhead,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        color: AppColors.primary.withValues(alpha: 0.08),
                        child: Text(
                          _agentLabel(),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (a.instructions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.instructions.replaceAll(RegExp(r'\s+'), ' '),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: AppConstants.fontSizeSmall,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Human-readable schedule
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                item.humanSchedule,
                style: TextStyle(
                  color: a.enabled ? AppColors.textMain : AppColors.textDim,
                  fontSize: AppConstants.fontSizeBody,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ),

          // Next run
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                nextRunText,
                style: TextStyle(
                  color: a.enabled ? AppColors.textMain : AppColors.textDim,
                  fontSize: AppConstants.fontSizeSmall,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Last run
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildLastRunCell(a, localeCode),
            ),
          ),

          // Active switch (isolated tap area)
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: AppSwitch(
                  value: a.enabled,
                  onChanged: onToggle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastRunCell(Automation a, String localeCode) {
    if (a.lastRunAt == null) {
      return Text(
        'automations.never_run'.tr(),
        style: const TextStyle(
          color: AppColors.textDim,
          fontSize: AppConstants.fontSizeSmall,
        ),
      );
    }

    final statusIcon = switch (a.lastRunStatus) {
      AutomationRunStatus.success => const Icon(
          Icons.check_circle_outline,
          size: 15,
          color: AppColors.success,
        ),
      AutomationRunStatus.failed => const Icon(
          Icons.error_outline,
          size: 15,
          color: AppColors.error,
        ),
      AutomationRunStatus.running => const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      AutomationRunStatus.cancelled || null => const Icon(
          Icons.cancel_outlined,
          size: 15,
          color: AppColors.textDim,
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        statusIcon,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            formatRelativePast(a.lastRunAt!, localeCode),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: AppConstants.fontSizeSmall,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatNextRun(DateTime nextRun, String localeCode) {
    final now = DateTime.now();
    final diff = nextRun.toLocal().difference(now);
    final isDe = localeCode.toLowerCase().startsWith('de');
    final timeStr = DateFormat('HH:mm', localeCode).format(nextRun.toLocal());

    if (diff.inMinutes < 1) {
      return isDe ? 'Jetzt ($timeStr)' : 'Now ($timeStr)';
    }
    if (diff.inMinutes < 60) {
      return isDe
          ? 'In ${diff.inMinutes} Min. · $timeStr'
          : 'In ${diff.inMinutes}m · $timeStr';
    }
    if (diff.inHours < 24 && nextRun.toLocal().day == now.day) {
      return isDe
          ? 'Heute · $timeStr'
          : 'Today · $timeStr';
    }
    return DateFormat('EEE · HH:mm', localeCode).format(nextRun.toLocal());
  }
}

/// Shared relative-past formatter used by both Overview and Detail View.
String formatRelativePast(DateTime time, String localeCode) {
  final diff = DateTime.now().difference(time.toLocal());
  final isDe = localeCode.toLowerCase().startsWith('de');

  if (diff.inSeconds < 45) {
    return isDe ? 'Gerade eben' : 'Just now';
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return isDe ? 'vor $m Min.' : '${m}m ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return isDe ? 'vor $h Std.' : '${h}h ago';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return isDe ? 'vor ${d}T' : '${d}d ago';
  }
  return DateFormat('dd.MM.yyyy', localeCode).format(time.toLocal());
}
