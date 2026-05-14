// Ghost — Kanban Task Card widget.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../engine/tasks/task.dart';

/// A single task card displayed on the Kanban board.
class KanbanTaskCard extends StatefulWidget {
  const KanbanTaskCard({
    required this.task,
    required this.onTap,
    required this.onStatusChanged,
    super.key,
  });

  final KanbanTask task;
  final VoidCallback onTap;
  final void Function(TaskStatus status) onStatusChanged;

  @override
  State<KanbanTaskCard> createState() => _KanbanTaskCardState();
}

class _KanbanTaskCardState extends State<KanbanTaskCard> {
  bool _hovered = false;

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.urgent:
        return const Color(0xFFEF4444); // Red 500
      case TaskPriority.high:
        return const Color(0xFFF97316); // Orange 500
      case TaskPriority.normal:
        return AppColors.textDim;
      case TaskPriority.low:
        return AppColors.border;
    }
  }

  IconData _priorityIcon(TaskPriority p) {
    switch (p) {
      case TaskPriority.urgent:
        return Icons.keyboard_double_arrow_up;
      case TaskPriority.high:
        return Icons.keyboard_arrow_up;
      case TaskPriority.normal:
        return Icons.remove;
      case TaskPriority.low:
        return Icons.keyboard_arrow_down;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale;

    final task = widget.task;
    final priColor = _priorityColor(task.priority);
    final hasSubtasks = task.subtasks.isNotEmpty;
    final hasAgent = task.assignedAgentName != null;
    final hasLabels = task.labels.isNotEmpty;

    return Draggable<KanbanTask>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 260,
          child: _buildCard(priColor, task, hasSubtasks, hasAgent, hasLabels,
              isDragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCard(
            priColor, task, hasSubtasks, hasAgent, hasLabels),
      ),
      child:
          _buildCard(priColor, task, hasSubtasks, hasAgent, hasLabels),
    );
  }

  Widget _buildCard(
    Color priColor,
    KanbanTask task,
    bool hasSubtasks,
    bool hasAgent,
    bool hasLabels, {
    bool isDragging = false,
  }) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDragging
                ? AppColors.surfaceLight
                : (_hovered ? AppColors.surfaceLight : AppColors.surface),
            border: Border(
              left: BorderSide(
                color: priColor,
                width: 3,
              ),
            ),
            boxShadow: isDragging
                ? [
                    BoxShadow(
                      color: AppColors.pureBlack.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: AppConstants.fontSizeBody,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _priorityIcon(task.priority),
                    color: priColor,
                    size: 16,
                  ),
                ],
              ),

              // Labels
              if (hasLabels) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: task.labels
                      .take(3)
                      .map((label) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],

              // Footer: agent + subtask progress
              if (hasSubtasks || hasAgent) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Agent badge
                    if (hasAgent) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.smart_toy,
                                size: 10, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              task.assignedAgentName!,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Subtask count
                    if (hasSubtasks)
                      Text(
                        '${task.completedSubtasks}/${task.subtasks.length} ✓',
                        style: TextStyle(
                          color: task.completedSubtasks == task.subtasks.length
                              ? AppColors.primary
                              : AppColors.textDim,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
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
}
