// Ghost — Kanban Board Screen.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../engine/tasks/task.dart';
import '../../../providers/kanban_provider.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/app_styles.dart';
import 'kanban_column.dart';
import 'kanban_task_detail.dart';

/// The main Kanban board screen.
class KanbanScreen extends ConsumerStatefulWidget {
  const KanbanScreen({super.key});

  @override
  ConsumerState<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends ConsumerState<KanbanScreen> {
  @override
  Widget build(BuildContext context) {
    context.locale;

    final backlog = ref.watch(kanbanBacklogProvider);
    final inProgress = ref.watch(kanbanInProgressProvider);
    final review = ref.watch(kanbanReviewProvider);
    final done = ref.watch(kanbanDoneProvider);
    final filter = ref.watch(kanbanFilterProvider);
    final config = ref.watch(configProvider);
    final agents = config.customAgents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.dashboard, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Text(
                'kanban.title_board'.tr().toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: AppConstants.fontSizeTitle,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 16),
              // Task count badge
              _CountBadge(
                count: backlog.length +
                    inProgress.length +
                    review.length +
                    done.length,
              ),
              const Spacer(),

              // Filter: by agent
              if (agents.isNotEmpty) ...[
                _FilterDropdown(
                  value: filter.agentId,
                  hint: 'kanban.filter_agent'.tr(),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'kanban.all_agents'.tr(),
                        style: const TextStyle(color: AppColors.textDim),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'default-agent',
                      child: Text(
                        '👻 ${config.identity.name}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    ...agents.map((a) => DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(
                            '🤖 ${a.name}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        )),
                  ],
                  onChanged: (v) => ref.read(kanbanFilterProvider.notifier).update(
                      filter.copyWith(agentId: v, clearAgent: v == null)),
                ),
                const SizedBox(width: 8),
              ],

              // Filter: by priority
              _FilterDropdown(
                value: filter.priority,
                hint: 'kanban.filter_priority'.tr(),
                items: [
                  DropdownMenuItem<TaskPriority?>(
                    value: null,
                    child: Text(
                      'kanban.all_priorities'.tr(),
                      style: const TextStyle(color: AppColors.textDim),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  ...TaskPriority.values.map((p) => DropdownMenuItem<TaskPriority?>(
                        value: p,
                        child: Text(
                          p.name.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      )),
                ],
                onChanged: (v) => ref.read(kanbanFilterProvider.notifier).update(
                    filter.copyWith(priority: v, clearPriority: v == null)),
              ),

              if (filter.isActive) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off,
                      size: 18, color: AppColors.textDim),
                  tooltip: 'kanban.clear_filters'.tr(),
                  onPressed: () =>
                      ref.read(kanbanFilterProvider.notifier).reset(),
                ),
              ],

              const SizedBox(width: 12),
              // Add task button
              AppNavButton(
                label: 'kanban.new_task',
                onPressed: () => _showCreateDialog(context),
                isPrimary: true,
                icon: Icons.add,
              ),
            ],
          ),
        ),

        // Board columns
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: KanbanColumn(
                    status: TaskStatus.backlog,
                    title: 'kanban.backlog',
                    icon: Icons.inbox,
                    tasks: backlog,
                    accentColor: AppColors.textDim,
                    onTaskTap: (task) => _showDetail(context, task),
                    onTaskDropped: _onTaskDropped,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KanbanColumn(
                    status: TaskStatus.inProgress,
                    title: 'kanban.in_progress',
                    icon: Icons.play_circle_outline,
                    tasks: inProgress,
                    accentColor: const Color(0xFF3B82F6), // Blue 500
                    onTaskTap: (task) => _showDetail(context, task),
                    onTaskDropped: _onTaskDropped,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KanbanColumn(
                    status: TaskStatus.review,
                    title: 'kanban.review',
                    icon: Icons.visibility,
                    tasks: review,
                    accentColor: const Color(0xFFF97316), // Orange 500
                    onTaskTap: (task) => _showDetail(context, task),
                    onTaskDropped: _onTaskDropped,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KanbanColumn(
                    status: TaskStatus.done,
                    title: 'kanban.done',
                    icon: Icons.check_circle_outline,
                    tasks: done,
                    accentColor: const Color(0xFF22C55E), // Green 500
                    onTaskTap: (task) => _showDetail(context, task),
                    onTaskDropped: _onTaskDropped,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _onTaskDropped(KanbanTask task, TaskStatus newStatus) {
    ref.read(kanbanTasksProvider.notifier).moveTask(task.id, newStatus);
  }

  void _showDetail(BuildContext context, KanbanTask task) {
    showDialog(
      context: context,
      builder: (_) => KanbanTaskDetailDialog(task: task),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _CreateTaskDialog(),
    );
  }
}

class _CreateTaskDialog extends ConsumerStatefulWidget {
  const _CreateTaskDialog();

  @override
  ConsumerState<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends ConsumerState<_CreateTaskDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  TaskPriority _priority = TaskPriority.normal;
  String? _selectedAgentId;
  bool _initialized = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final customAgents = config.customAgents.where((a) => a.enabled).toList();
    if (!_initialized) {
      _selectedAgentId =
          customAgents.isNotEmpty ? KanbanTask.autoAgentId : null;
      _initialized = true;
    }

    return Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'kanban.create_task'.tr().toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: AppConstants.fontSizeTitle,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),
              AppFormField.text(
                controller: _titleCtrl,
                label: 'kanban.title',
                hint: 'kanban.title_hint',
              ),
              AppFormField.text(
                controller: _descCtrl,
                label: 'kanban.description',
                hint: 'kanban.description_hint',
                maxLines: 3,
              ),
              const AppFormLabel('kanban.priority'),
              const SizedBox(height: 6),
              DropdownButtonFormField<TaskPriority>(
                initialValue: _priority,
                decoration: AppInputDecoration.compact(),
                dropdownColor: AppColors.surface,
                isExpanded: true,
                style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: AppConstants.fontSizeBody),
                items: TaskPriority.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p.name.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
              const SizedBox(height: 16),
              const AppFormLabel('kanban.assigned_agent'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _selectedAgentId,
                decoration: AppInputDecoration.compact(),
                dropdownColor: AppColors.surface,
                isExpanded: true,
                style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: AppConstants.fontSizeBody),
                items: [
                  DropdownMenuItem<String?>(
                    value: KanbanTask.autoAgentId,
                    child: Text(
                      '🧭 ${'kanban.auto_ontology'.tr()}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'kanban.unassigned'.tr(),
                      style: const TextStyle(color: AppColors.textDim),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'default-agent',
                    child: Text(
                      '👻 ${config.identity.name} (${'kanban.default_agent'.tr()})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  ...customAgents.map((a) => DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(
                          '🤖 ${a.name}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      )),
                ],
                onChanged: (v) => setState(() => _selectedAgentId = v),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppNavButton(
                    label: 'common.cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  AppNavButton(
                    label: 'kanban.create',
                    onPressed: () {
                      if (_titleCtrl.text.trim().isNotEmpty) {
                        String? agentName;
                        if (_selectedAgentId == KanbanTask.autoAgentId) {
                          agentName = 'kanban.auto_ontology'.tr();
                        } else if (_selectedAgentId == 'default-agent') {
                          agentName = config.identity.name;
                        } else if (_selectedAgentId != null) {
                          agentName = customAgents
                              .where((a) => a.id == _selectedAgentId)
                              .firstOrNull
                              ?.name;
                        }
                        ref.read(kanbanTasksProvider.notifier).createTask(
                              title: _titleCtrl.text.trim(),
                              description: _descCtrl.text.trim(),
                              priority: _priority,
                              assignedAgentId: _selectedAgentId,
                              assignedAgentName: agentName,
                            );
                        Navigator.pop(context);
                      }
                    },
                    isPrimary: true,
                    icon: Icons.add,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper Widgets
// ---------------------------------------------------------------------------

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T?>> items;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        decoration: AppInputDecoration.compact(hint: hint),
        dropdownColor: AppColors.surface,
        isDense: true,
        isExpanded: true,
        style: const TextStyle(
          color: AppColors.textMain,
          fontSize: AppConstants.fontSizeSmall,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}
