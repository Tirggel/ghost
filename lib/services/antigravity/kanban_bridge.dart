// Ghost — Antigravity to Kanban Bridge.
// Maps Antigravity decomposed tasks, plans, and pipelines to Ghost's Kanban system.

import 'dart:async';
import 'package:logging/logging.dart';
import '../../engine/tasks/task.dart';
import '../../engine/tasks/task_manager.dart';
import '../../engine/tasks/task_orchestrator.dart';

final _log = Logger('Ghost.AntigravityKanbanBridge');

/// State representation for an Antigravity plan step.
class AntigravityStep {
  const AntigravityStep({
    required this.index,
    required this.title,
    this.description = '',
    this.status = 'pending',
  });

  final int index;
  final String title;
  final String description;
  final String status; // pending, running, completed, review_needed, failed

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'description': description,
        'status': status,
      };

  factory AntigravityStep.fromJson(Map<String, dynamic> json) {
    return AntigravityStep(
      index: json['index'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
    );
  }
}

/// Bridges Antigravity planning and multi-agent coordination with the Kanban board.
class AntigravityKanbanBridge {
  AntigravityKanbanBridge({
    required this.taskManager,
    required this.orchestrator,
  });

  final TaskManager taskManager;
  final TaskOrchestrator orchestrator;

  /// Decomposes an Antigravity plan into a linked Kanban pipeline.
  Future<List<KanbanTask>> createPipelineFromPlan({
    required String planTitle,
    required List<AntigravityStep> steps,
    String? assignedAgentId,
    String? assignedAgentName,
    String? sessionId,
  }) async {
    _log.info('Creating Kanban pipeline for plan: "$planTitle" with ${steps.length} steps');

    final titles = steps.map((s) => s.title).toList();
    final tasks = await orchestrator.createPipeline(
      titles: titles,
      assignedAgentId: assignedAgentId,
      assignedAgentName: assignedAgentName,
    );

    // Update descriptions, session IDs, and metadata
    for (int i = 0; i < tasks.length && i < steps.length; i++) {
      final task = tasks[i];
      final step = steps[i];

      final updated = task.copyWith(
        description: step.description.isNotEmpty
            ? step.description
            : 'Step ${step.index + 1} of Antigravity Plan: $planTitle',
        sessionId: sessionId,
        metadata: {
          ...task.metadata,
          'antigravity_plan': planTitle,
          'step_index': step.index,
        },
      );
      await taskManager.updateTask(updated);
      tasks[i] = updated;
    }

    return tasks;
  }

  /// Synchronize an Antigravity step status to the corresponding Kanban task.
  Future<void> syncStepStatus(
    String taskId,
    String antigravityStatus, {
    String? summary,
    String? authorId = 'antigravity_agent',
  }) async {
    final task = taskManager.getTask(taskId);
    if (task == null) {
      _log.warning('Task $taskId not found for Antigravity status sync');
      return;
    }

    TaskStatus newStatus;
    switch (antigravityStatus.toLowerCase()) {
      case 'running':
      case 'in_progress':
        newStatus = TaskStatus.inProgress;
        break;
      case 'completed':
      case 'done':
        newStatus = TaskStatus.done;
        break;
      case 'review_needed':
      case 'review':
      case 'failed':
        newStatus = TaskStatus.review;
        break;
      case 'cancelled':
        newStatus = TaskStatus.cancelled;
        break;
      default:
        newStatus = TaskStatus.backlog;
    }

    await taskManager.moveTask(taskId, newStatus);

    if (summary != null && summary.isNotEmpty) {
      await taskManager.addComment(
        taskId,
        authorId: authorId ?? 'antigravity_agent',
        authorName: 'Antigravity Agent',
        content: summary,
      );
    }

    _log.info('Synced Antigravity task $taskId to status ${newStatus.name}');
  }

  /// Generates a status summary of all tasks belonging to an Antigravity plan.
  List<Map<String, dynamic>> getPlanTasksSummary(String planTitle) {
    final matching = taskManager.tasks.where((t) {
      return t.metadata['antigravity_plan'] == planTitle;
    }).toList();

    matching.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return matching.map((t) => {
          'id': t.id,
          'title': t.title,
          'status': t.status.name,
          'assignedAgent': t.assignedAgentName,
          'stepIndex': t.metadata['step_index'],
        }).toList();
  }
}
