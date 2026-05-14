// Ghost — Kanban Task Detail dialog.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../engine/tasks/task.dart';
import '../../../providers/kanban_provider.dart';
import '../../../providers/gateway_provider.dart';
import '../../widgets/app_styles.dart';

/// Full detail dialog for a Kanban task.
class KanbanTaskDetailDialog extends ConsumerStatefulWidget {
  const KanbanTaskDetailDialog({required this.task, super.key});

  final KanbanTask task;

  @override
  ConsumerState<KanbanTaskDetailDialog> createState() =>
      _KanbanTaskDetailDialogState();
}

class _KanbanTaskDetailDialogState
    extends ConsumerState<KanbanTaskDetailDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _subtaskCtrl;
  late TextEditingController _commentCtrl;
  late TaskPriority _priority;
  late TaskStatus _status;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(text: widget.task.description);
    _subtaskCtrl = TextEditingController();
    _commentCtrl = TextEditingController();
    _priority = widget.task.priority;
    _status = widget.task.status;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _subtaskCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.urgent:
        return const Color(0xFFEF4444);
      case TaskPriority.high:
        return const Color(0xFFF97316);
      case TaskPriority.normal:
        return AppColors.textDim;
      case TaskPriority.low:
        return AppColors.border;
    }
  }

  String _statusLabel(TaskStatus s) {
    switch (s) {
      case TaskStatus.backlog:
        return 'Backlog';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.review:
        return 'Review';
      case TaskStatus.done:
        return 'Done';
      case TaskStatus.cancelled:
        return 'Cancelled';
    }
  }

  Future<void> _save() async {
    final notifier = ref.read(kanbanTasksProvider.notifier);
    final updated = widget.task.copyWith(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      priority: _priority,
    );

    await notifier.updateTask(updated);

    if (_status != widget.task.status) {
      await notifier.moveTask(widget.task.id, _status);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('kanban.delete_confirm_title'.tr(),
            style: const TextStyle(color: AppColors.textMain)),
        content: Text('kanban.delete_confirm_msg'.tr(),
            style: const TextStyle(color: AppColors.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(kanbanTasksProvider.notifier).deleteTask(widget.task.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale;

    // Re-fetch the task from provider to get latest subtasks/comments
    final tasks = ref.watch(kanbanTasksProvider);
    final currentTask = tasks.where((t) => t.id == widget.task.id).firstOrNull;
    if (currentTask == null) {
      return const SizedBox.shrink();
    }

    final config = ref.watch(configProvider);
    final agents = config.customAgents;

    return Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    color: _priorityColor(_priority),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'kanban.task_details'.tr().toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: AppConstants.fontSizeTitle,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error, size: 18),
                    onPressed: _delete,
                    tooltip: 'common.delete'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textDim, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    AppFormField.text(
                      controller: _titleCtrl,
                      label: 'kanban.title',
                      hint: 'kanban.title_hint',
                    ),

                    // Description
                    AppFormField.text(
                      controller: _descCtrl,
                      label: 'kanban.description',
                      hint: 'kanban.description_hint',
                      maxLines: 3,
                    ),

                    // Status + Priority row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppFormLabel('kanban.status'),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<TaskStatus>(
                                value: _status,
                                decoration: AppInputDecoration.compact(),
                                dropdownColor: AppColors.surface,
                                style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: AppConstants.fontSizeBody),
                                items: TaskStatus.values
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(_statusLabel(s)),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _status = v ?? _status),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppFormLabel('kanban.priority'),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<TaskPriority>(
                                value: _priority,
                                decoration: AppInputDecoration.compact(),
                                dropdownColor: AppColors.surface,
                                style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: AppConstants.fontSizeBody),
                                items: TaskPriority.values
                                    .map((p) => DropdownMenuItem(
                                          value: p,
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: _priorityColor(p),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(p.name.toUpperCase()),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _priority = v ?? _priority),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppConstants.settingsSectionSpacing),

                    // Agent assignment
                    if (agents.isNotEmpty) ...[
                      const AppFormLabel('kanban.assigned_agent'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String?>(
                        value: currentTask.assignedAgentId,
                        decoration: AppInputDecoration.compact(),
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: AppConstants.fontSizeBody),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('kanban.unassigned'.tr(),
                                style:
                                    const TextStyle(color: AppColors.textDim)),
                          ),
                          ...agents.map((a) => DropdownMenuItem<String?>(
                                value: a.id,
                                child: Row(
                                  children: [
                                    Text('🤖',
                                        style:
                                            const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Text(a.name),
                                  ],
                                ),
                              )),
                        ],
                        onChanged: (agentId) {
                          final agentName = agentId != null
                              ? agents
                                  .where((a) => a.id == agentId)
                                  .firstOrNull
                                  ?.name
                              : null;
                          ref.read(kanbanTasksProvider.notifier).assignTask(
                                currentTask.id,
                                agentId,
                                agentName,
                              );
                        },
                      ),
                      const SizedBox(
                          height: AppConstants.settingsSectionSpacing),
                    ],

                    // Subtasks
                    AppSectionHeader('kanban.subtasks'),
                    ...currentTask.subtasks.map((sub) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => ref
                                    .read(kanbanTasksProvider.notifier)
                                    .toggleSubtask(currentTask.id, sub.id),
                                child: Icon(
                                  sub.done
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  color: sub.done
                                      ? AppColors.primary
                                      : AppColors.textDim,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sub.title,
                                  style: TextStyle(
                                    color: sub.done
                                        ? AppColors.textDim
                                        : AppColors.textMain,
                                    fontSize: AppConstants.fontSizeBody,
                                    decoration: sub.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _subtaskCtrl,
                            decoration: AppInputDecoration.compact(
                              hint: 'kanban.add_subtask_hint'.tr(),
                            ),
                            style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: AppConstants.fontSizeBody),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                ref
                                    .read(kanbanTasksProvider.notifier)
                                    .addSubtask(currentTask.id, value.trim());
                                _subtaskCtrl.clear();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add,
                              color: AppColors.primary, size: 18),
                          onPressed: () {
                            if (_subtaskCtrl.text.trim().isNotEmpty) {
                              ref
                                  .read(kanbanTasksProvider.notifier)
                                  .addSubtask(
                                      currentTask.id, _subtaskCtrl.text.trim());
                              _subtaskCtrl.clear();
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(
                        height: AppConstants.settingsSectionSpacing),

                    // Comments
                    AppSectionHeader('kanban.comments'),
                    ...currentTask.comments.map((c) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    c.authorId == 'user'
                                        ? Icons.person
                                        : Icons.smart_toy,
                                    size: 12,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    c.authorName,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatTime(c.timestamp),
                                    style: const TextStyle(
                                      color: AppColors.textDim,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.content,
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontSize: AppConstants.fontSizeSmall,
                                ),
                              ),
                            ],
                          ),
                        )),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentCtrl,
                            decoration: AppInputDecoration.compact(
                              hint: 'kanban.add_comment_hint'.tr(),
                            ),
                            style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: AppConstants.fontSizeBody),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                ref
                                    .read(kanbanTasksProvider.notifier)
                                    .addComment(currentTask.id, value.trim());
                                _commentCtrl.clear();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send,
                              color: AppColors.primary, size: 18),
                          onPressed: () {
                            if (_commentCtrl.text.trim().isNotEmpty) {
                              ref
                                  .read(kanbanTasksProvider.notifier)
                                  .addComment(
                                      currentTask.id, _commentCtrl.text.trim());
                              _commentCtrl.clear();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer: Save button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppNavButton(
                    label: 'common.cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  AppNavButton(
                    label: 'common.save',
                    onPressed: _save,
                    isPrimary: true,
                    icon: Icons.save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
