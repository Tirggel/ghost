// Ghost — Kanban Column widget.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../engine/tasks/task.dart';
import 'kanban_task_card.dart';

/// A single column on the Kanban board (e.g. Backlog, In Progress).
class KanbanColumn extends StatelessWidget {
  const KanbanColumn({
    required this.status,
    required this.title,
    required this.icon,
    required this.tasks,
    required this.onTaskTap,
    required this.onTaskDropped,
    required this.accentColor,
    super.key,
  });

  final TaskStatus status;
  final String title;
  final IconData icon;
  final List<KanbanTask> tasks;
  final void Function(KanbanTask task) onTaskTap;
  final void Function(KanbanTask task, TaskStatus newStatus) onTaskDropped;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    context.locale;

    return DragTarget<KanbanTask>(
      onAcceptWithDetails: (details) {
        onTaskDropped(details.data, status);
      },
      onWillAcceptWithDetails: (details) => details.data.status != status,
      builder: (context, candidateData, rejectedData) {
        final isHoveredWithCard = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isHoveredWithCard
                ? AppColors.surfaceLight.withValues(alpha: 0.5)
                : AppColors.background,
            border: Border.all(
              color: isHoveredWithCard ? accentColor : AppColors.border,
              width: isHoveredWithCard ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isHoveredWithCard
                          ? accentColor.withValues(alpha: 0.3)
                          : AppColors.border,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: accentColor),
                    const SizedBox(width: 8),
                    Text(
                      title.tr().toUpperCase(),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: AppConstants.fontSizeLabelTiny,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '${tasks.length}',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Task list
              Expanded(
                child: tasks.isEmpty
                    ? _buildEmptyState(isHoveredWithCard)
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          return KanbanTaskCard(
                            task: tasks[index],
                            onTap: () => onTaskTap(tasks[index]),
                            onStatusChanged: (newStatus) =>
                                onTaskDropped(tasks[index], newStatus),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isHovered) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isHovered ? Icons.add_circle_outline : icon,
              size: 28,
              color: isHovered
                  ? accentColor.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
            const SizedBox(height: 8),
            Text(
              isHovered ? 'kanban.drop_here'.tr() : 'kanban.empty_column'.tr(),
              style: TextStyle(
                color: isHovered
                    ? accentColor.withValues(alpha: 0.6)
                    : AppColors.textDim,
                fontSize: AppConstants.fontSizeSmall,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
