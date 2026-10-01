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

        // If it's already assigned, auto-start execution with the assigned agent
        if (dependent.assignedAgentId != null &&
            dependent.status == TaskStatus.backlog) {
          _log.info(
            'Auto-starting task ${dependent.id} with agent ${dependent.assignedAgentId}.',
          );
          await taskManager.moveTask(dependent.id, TaskStatus.inProgress);
          unawaited(_executeTaskWithAgent(dependent));
        }
      }
    }
  }

  /// Autonomously executes a Kanban task using its assigned agent.
  Future<void> _executeTaskWithAgent(KanbanTask task) async {
    final agentId = task.assignedAgentId;
    if (agentId == null) return;

    try {
      final agent = agentManager.getAgent(agentId);
      if (agent == null) {
        _log.warning('Agent $agentId not found for task ${task.id}');
        return;
      }

      final sessionId = task.sessionId ?? 'task_${task.id}';
      if (task.sessionId == null) {
        final updated = task.copyWith(sessionId: sessionId);
        await taskManager.updateTask(updated);
      }

      _log.info(
        'Orchestrator starting autonomous execution of "${task.title}" with agent $agentId in session $sessionId',
      );

      await taskManager.addComment(
        task.id,
        authorId: 'system',
        authorName: 'Ghost Orchestrator',
        content: '🤖 Agent "${agent.name}" führt die Aufgabe jetzt autonom aus...',
      );

      final goalPrompt = '/goal ${task.title}\n\n${task.description}';

      if (agentManager.sessionManager.getSession(sessionId) == null) {
        agentManager.sessionManager.createSession(
          id: sessionId,
          channelType: 'kanban',
          peerId: agentId,
        );
      }

      await agentManager.sessionManager.addMessage(
        sessionId: sessionId,
        role: 'user',
        content: goalPrompt,
      );

      await agent.processMessage(
        sessionId: sessionId,
        content: goalPrompt,
      );

      await taskManager.moveTask(task.id, TaskStatus.done);
      await taskManager.addComment(
        task.id,
        authorId: 'system',
        authorName: 'Ghost Orchestrator',
        content: '✅ Aufgabe erfolgreich abgeschlossen.',
      );
      _log.info('Task ${task.id} successfully completed by agent $agentId.');
    } catch (e) {
      _log.severe('Error executing task ${task.id} with agent $agentId: $e');
      await taskManager.moveTask(task.id, TaskStatus.review);
      await taskManager.addComment(
        task.id,
        authorId: 'system',
        authorName: 'Ghost Orchestrator',
        content: '⚠️ Ausführung fehlgeschlagen: $e',
      );
    }
  }

  /// Check whether adding dependencies to a task would create a circular dependency cycle.
  bool wouldCreateCycle(String taskId, List<String> newDependsOnIds) {
    final visited = <String>{};

    bool hasPath(String current, String target) {
      if (current == target) return true;
      if (!visited.add(current)) return false;
      final t = taskManager.getTask(current);
      if (t == null) return false;
      for (final dep in t.dependsOnIds) {
        if (hasPath(dep, target)) return true;
      }
      return false;
    }

    for (final depId in newDependsOnIds) {
      if (hasPath(depId, taskId)) {
        return true;
      }
    }
    return false;
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
