// Ghost — Task Orchestrator (Phase 3).
// Handles dependencies, pipelines, and automated task transitions.

import 'dart:async';
import 'package:logging/logging.dart';

import '../agent/manager.dart';
import 'task.dart';
import 'task_manager.dart';

final _log = Logger('Ghost.TaskOrchestrator');

class TaskOrchestrator {
  TaskOrchestrator({
    required this.taskManager,
    required this.agentManager,
  });

  final TaskManager taskManager;
  final AgentManager agentManager;
  StreamSubscription<TaskEvent>? _subscription;

  /// Initialize the orchestrator by listening to task events.
  void initialize() {
    _subscription = taskManager.onTaskChanged.listen(_handleTaskEvent);
    _log.info('TaskOrchestrator initialized');
  }

  void dispose() {
    _subscription?.cancel();
  }

  /// Suggest the best agent for a task based on skills.
  Future<String?> suggestAgent(KanbanTask task) async {
    final agents = agentManager.agents;
    if (agents.isEmpty) return null;

    final query = (task.title + ' ' + task.description).toLowerCase();
    
    String? bestAgentId;
    int maxMatches = -1;

    for (final agent in agents) {
      int matches = 0;
      // Simple keyword matching against skills and name
      final agentTerms = [
        agent.name,
        ...agent.skills,
      ].map((s) => s.toLowerCase()).toList();

      for (final term in agentTerms) {
        if (query.contains(term)) {
          matches++;
        }
      }

      if (matches > maxMatches) {
        maxMatches = matches;
        bestAgentId = agent.id;
      }
    }

    return bestAgentId;
  }

  void _handleTaskEvent(TaskEvent event) {
    // When a task moves to 'done', check for dependents.
    if (event.type == TaskEventType.updated || event.type == TaskEventType.moved) {
      final task = event.task;
      if (task != null && task.status == TaskStatus.done) {
        _log.info('Task ${task.id} is DONE. Checking for dependents...');
        _processDependents(task.id);
      }
    }
  }

  /// Check all tasks that depend on the completed task.
  Future<void> _processDependents(String completedTaskId) async {
    final allTasks = taskManager.tasks;
    final dependents = allTasks.where((t) => t.dependsOnIds.contains(completedTaskId)).toList();

    for (final dependent in dependents) {
      _log.info('Checking dependent task: ${dependent.title} (${dependent.id})');
      
      // Check if ALL dependencies are met
      bool allMet = true;
      for (final depId in dependent.dependsOnIds) {
        final depTask = taskManager.getTask(depId);
        if (depTask == null || depTask.status != TaskStatus.done) {
          allMet = false;
          _log.info('Dependency $depId not met yet for ${dependent.id}');
          break;
        }
      }

      if (allMet) {
        _log.info('All dependencies met for ${dependent.id}. Auto-starting or moving to backlog.');
        
        // If it was in backlog, and we have an assigned agent, maybe move to inProgress?
        // For now, let's just ensure it's in a "ready" state if we had a "blocked" state.
        // Since we don't have "blocked", we might just add a comment or log it.
        // Or we could move it from a custom metadata status.
        
        await taskManager.addComment(
          dependent.id,
          authorId: 'system',
          authorName: 'Ghost Orchestrator',
          content: 'All dependencies met. Task is now ready for execution.',
        );

        // If it's already assigned, we could auto-start it?
        if (dependent.assignedAgentId != null && dependent.status == TaskStatus.backlog) {
           _log.info('Auto-starting task ${dependent.id} as it is already assigned.');
           await taskManager.moveTask(dependent.id, TaskStatus.inProgress);
        }
      }
    }
  }

  /// Create a pipeline of tasks.
  /// Each task in the list depends on the previous one.
  Future<List<KanbanTask>> createPipeline({
    required List<String> titles,
    String? assignedAgentId,
    String? assignedAgentName,
  }) async {
    final createdTasks = <KanbanTask>[];
    String? lastTaskId;

    for (final title in titles) {
      final task = await taskManager.createTask(
        title: title,
        assignedAgentId: assignedAgentId,
        assignedAgentName: assignedAgentName,
      );

      if (lastTaskId != null) {
        final updated = task.copyWith(dependsOnIds: [lastTaskId]);
        await taskManager.updateTask(updated);
        createdTasks.add(updated);
      } else {
        createdTasks.add(task);
      }

      lastTaskId = task.id;
    }

    return createdTasks;
  }
}
