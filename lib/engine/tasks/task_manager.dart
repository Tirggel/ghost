// Ghost — Kanban Task Manager (business logic).

import 'dart:async';
import 'package:logging/logging.dart';

import 'task.dart';
import 'task_store.dart';

final _log = Logger('Ghost.TaskManager');

/// Event types for task changes.
enum TaskEventType { created, updated, deleted, moved, assigned }

/// Represents a task change event.
class TaskEvent {
  const TaskEvent({
    required this.type,
    required this.taskId,
    this.task,
    this.oldStatus,
    this.newStatus,
  });

  final TaskEventType type;
  final String taskId;
  final KanbanTask? task;
  final TaskStatus? oldStatus;
  final TaskStatus? newStatus;
}

/// Manages Kanban tasks: CRUD, status transitions, queries.
class TaskManager {
  TaskManager({required this.store});

  final TaskStore store;

  /// In-memory cache of all tasks.
  List<KanbanTask> _tasks = [];

  final _eventController = StreamController<TaskEvent>.broadcast();

  /// Stream of task change events.
  Stream<TaskEvent> get onTaskChanged => _eventController.stream;

  /// All tasks (read-only).
  List<KanbanTask> get tasks => List.unmodifiable(_tasks);

  /// Initialize: load all tasks from store.
  Future<void> initialize() async {
    await store.initialize();
    _tasks = await store.loadAll();
    _log.info('Loaded ${_tasks.length} tasks from store');
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Create a new task.
  Future<KanbanTask> createTask({
    required String title,
    String description = '',
    TaskPriority priority = TaskPriority.normal,
    TaskStatus status = TaskStatus.backlog,
    List<String> labels = const [],
    String? assignedAgentId,
    String? assignedAgentName,
    String? createdByAgentId,
    DateTime? dueDate,
    List<String> dependsOnIds = const [],
  }) async {
    // Compute sort order: place at the bottom of the column
    final tasksInColumn = getTasksByStatus(status);
    final maxSort = tasksInColumn.isEmpty
        ? 0
        : tasksInColumn
            .map((t) => t.sortOrder)
            .reduce((a, b) => a > b ? a : b);

    final task = KanbanTask(
      title: title,
      description: description,
      priority: priority,
      status: status,
      labels: labels,
      assignedAgentId: assignedAgentId,
      assignedAgentName: assignedAgentName,
      createdByAgentId: createdByAgentId,
      dueDate: dueDate,
      dependsOnIds: dependsOnIds,
      sortOrder: maxSort + 1,
    );

    _tasks.add(task);
    await store.save(task);
    _eventController.add(TaskEvent(
      type: TaskEventType.created,
      taskId: task.id,
      task: task,
    ));
    _log.info('Created task: ${task.title} (${task.id})');
    return task;
  }

  /// Update an existing task.
  Future<void> updateTask(KanbanTask task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      _log.warning('Task ${task.id} not found for update');
      return;
    }

    final updated = task.copyWith(updatedAt: DateTime.now());
    _tasks[index] = updated;
    await store.save(updated);
    _eventController.add(TaskEvent(
      type: TaskEventType.updated,
      taskId: updated.id,
      task: updated,
    ));
  }

  /// Delete a task.
  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    await store.delete(taskId);
    _eventController.add(TaskEvent(
      type: TaskEventType.deleted,
      taskId: taskId,
    ));
    _log.info('Deleted task: $taskId');
  }

  /// Get a task by ID.
  KanbanTask? getTask(String taskId) {
    try {
      return _tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Status Transitions
  // ---------------------------------------------------------------------------

  /// Move a task to a new status column.
  Future<void> moveTask(
    String taskId,
    TaskStatus newStatus, {
    int? insertAt,
  }) async {
    final task = getTask(taskId);
    if (task == null) return;

    final oldStatus = task.status;
    if (oldStatus == newStatus && insertAt == null) return;

    // Update sort orders in the new column
    final targetTasks = getTasksByStatus(newStatus)
      ..removeWhere((t) => t.id == taskId);

    final index = insertAt ?? targetTasks.length;
    for (var i = 0; i < targetTasks.length; i++) {
      if (i >= index) {
        targetTasks[i].sortOrder = i + 1;
        await store.save(targetTasks[i]);
      }
    }

    final updated = task.copyWith(
      status: newStatus,
      sortOrder: index,
      updatedAt: DateTime.now(),
    );

    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex != -1) _tasks[taskIndex] = updated;
    await store.save(updated);

    _eventController.add(TaskEvent(
      type: TaskEventType.moved,
      taskId: taskId,
      task: updated,
      oldStatus: oldStatus,
      newStatus: newStatus,
    ));
    _log.info('Moved task $taskId: ${oldStatus.name} → ${newStatus.name}');
  }

  /// Assign a task to an agent.
  Future<void> assignTask(
    String taskId,
    String? agentId,
    String? agentName,
  ) async {
    final task = getTask(taskId);
    if (task == null) return;

    final updated = agentId == null
        ? task.copyWith(clearAssignedAgent: true, updatedAt: DateTime.now())
        : task.copyWith(
            assignedAgentId: agentId,
            assignedAgentName: agentName,
            updatedAt: DateTime.now(),
          );

    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) _tasks[index] = updated;
    await store.save(updated);

    _eventController.add(TaskEvent(
      type: TaskEventType.assigned,
      taskId: taskId,
      task: updated,
    ));
    _log.info('Assigned task $taskId to agent: ${agentId ?? "unassigned"}');
  }

  // ---------------------------------------------------------------------------
  // Subtask management
  // ---------------------------------------------------------------------------

  /// Toggle a subtask's done state.
  Future<void> toggleSubtask(String taskId, String subtaskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    final subtasks = List<SubTask>.from(task.subtasks);
    final idx = subtasks.indexWhere((s) => s.id == subtaskId);
    if (idx == -1) return;

    subtasks[idx].done = !subtasks[idx].done;
    await updateTask(task.copyWith(subtasks: subtasks));
  }

  /// Add a subtask to a task.
  Future<void> addSubtask(String taskId, String title) async {
    final task = getTask(taskId);
    if (task == null) return;

    final subtasks = List<SubTask>.from(task.subtasks)
      ..add(SubTask(title: title));
    await updateTask(task.copyWith(subtasks: subtasks));
  }

  /// Remove a subtask from a task.
  Future<void> removeSubtask(String taskId, String subtaskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    final subtasks = List<SubTask>.from(task.subtasks)
      ..removeWhere((s) => s.id == subtaskId);
    await updateTask(task.copyWith(subtasks: subtasks));
  }

  // ---------------------------------------------------------------------------
  // Comments
  // ---------------------------------------------------------------------------

  /// Add a comment to a task.
  Future<void> addComment(
    String taskId, {
    required String authorId,
    required String authorName,
    required String content,
  }) async {
    final task = getTask(taskId);
    if (task == null) return;

    final comments = List<TaskComment>.from(task.comments)
      ..add(TaskComment(
        authorId: authorId,
        authorName: authorName,
        content: content,
      ));
    await updateTask(task.copyWith(comments: comments));
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Get tasks filtered by status.
  List<KanbanTask> getTasksByStatus(TaskStatus status) {
    return _tasks.where((t) => t.status == status).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Get tasks assigned to a specific agent.
  List<KanbanTask> getTasksByAgent(String agentId) {
    return _tasks.where((t) => t.assignedAgentId == agentId).toList();
  }

  /// Get tasks matching a search query.
  List<KanbanTask> search(String query) {
    final q = query.toLowerCase();
    return _tasks.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q) ||
          t.labels.any((l) => l.toLowerCase().contains(q));
    }).toList();
  }

  /// Task count by status.
  Map<TaskStatus, int> get statusCounts {
    final counts = <TaskStatus, int>{};
    for (final status in TaskStatus.values) {
      counts[status] = _tasks.where((t) => t.status == status).length;
    }
    return counts;
  }

  /// Reload from store.
  Future<void> reload() async {
    _tasks = await store.loadAll();
    _log.info('Reloaded ${_tasks.length} tasks');
  }

  void dispose() {
    _eventController.close();
    store.dispose();
  }
}
