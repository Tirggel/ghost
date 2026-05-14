// Ghost — Kanban Task RPC Router.

import 'package:logging/logging.dart';

import '../infra/errors.dart';
import '../gateway/server.dart';
import '../tasks/task.dart';
import '../tasks/task_manager.dart';

final _log = Logger('Ghost.KanbanRouter');

/// Routes Kanban task requests from the Gateway.
class KanbanRouter {
  KanbanRouter({
    required this.gateway,
    required this.taskManager,
  });

  final GatewayServer gateway;
  final TaskManager taskManager;

  /// Register kanban-related RPC methods.
  void register() {
    // --- List all tasks ---
    gateway.rpcRegistry.register('kanban.list', (params, context) async {
      final statusFilter = params?['status'] as String?;
      final agentFilter = params?['agentId'] as String?;

      List<KanbanTask> tasks;
      if (statusFilter != null) {
        final status = TaskStatus.values.firstWhere(
          (s) => s.name == statusFilter,
          orElse: () => TaskStatus.backlog,
        );
        tasks = taskManager.getTasksByStatus(status);
      } else if (agentFilter != null) {
        tasks = taskManager.getTasksByAgent(agentFilter);
      } else {
        tasks = taskManager.tasks;
      }

      return {
        'status': 'ok',
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'counts': taskManager.statusCounts.map(
          (k, v) => MapEntry(k.name, v),
        ),
      };
    });

    // --- Get single task ---
    gateway.rpcRegistry.register('kanban.get', (params, context) async {
      final taskId = params?['id'] as String?;
      if (taskId == null) throw ProtocolError('Missing required parameter: id');

      final task = taskManager.getTask(taskId);
      if (task == null) throw ProtocolError('Task not found: $taskId');

      return {'status': 'ok', 'task': task.toJson()};
    });

    // --- Create task ---
    gateway.rpcRegistry.register('kanban.create', (params, context) async {
      final title = params?['title'] as String?;
      if (title == null || title.isEmpty) {
        throw ProtocolError('Missing required parameter: title');
      }

      final task = await taskManager.createTask(
        title: title,
        description: params?['description'] as String? ?? '',
        priority: TaskPriority.values.firstWhere(
          (p) => p.name == (params?['priority'] as String?),
          orElse: () => TaskPriority.normal,
        ),
        status: TaskStatus.values.firstWhere(
          (s) => s.name == (params?['status'] as String?),
          orElse: () => TaskStatus.backlog,
        ),
        labels: (params?['labels'] as List<dynamic>?)?.cast<String>() ?? [],
        assignedAgentId: params?['assignedAgentId'] as String?,
        assignedAgentName: params?['assignedAgentName'] as String?,
        createdByAgentId: params?['createdByAgentId'] as String?,
        dependsOnIds: (params?['dependsOnIds'] as List<dynamic>?)?.cast<String>() ?? [],
      );

      gateway.broadcast('kanban.changed');
      return {'status': 'ok', 'task': task.toJson()};
    });

    // --- Update task ---
    gateway.rpcRegistry.register('kanban.update', (params, context) async {
      final taskId = params?['id'] as String?;
      if (taskId == null) throw ProtocolError('Missing required parameter: id');

      final existing = taskManager.getTask(taskId);
      if (existing == null) throw ProtocolError('Task not found: $taskId');

      final updated = existing.copyWith(
        title: params?['title'] as String?,
        description: params?['description'] as String?,
        priority: params?['priority'] != null
            ? TaskPriority.values.firstWhere(
                (p) => p.name == (params!['priority'] as String),
                orElse: () => existing.priority,
              )
            : null,
        labels: (params?['labels'] as List<dynamic>?)?.cast<String>(),
        assignedAgentId: params?['assignedAgentId'] as String?,
        assignedAgentName: params?['assignedAgentName'] as String?,
        clearAssignedAgent: params?['clearAssignedAgent'] == true,
        dependsOnIds: (params?['dependsOnIds'] as List<dynamic>?)?.cast<String>(),
        dueDate: params?['dueDate'] != null
            ? DateTime.tryParse(params!['dueDate'] as String)
            : null,
        clearDueDate: params?['clearDueDate'] == true,
      );

      await taskManager.updateTask(updated);
      gateway.broadcast('kanban.changed');
      return {'status': 'ok', 'task': updated.toJson()};
    });

    // --- Move task (status change) ---
    gateway.rpcRegistry.register('kanban.move', (params, context) async {
      final taskId = params?['id'] as String?;
      final newStatusStr = params?['status'] as String?;
      if (taskId == null || newStatusStr == null) {
        throw ProtocolError('Missing required parameters: id, status');
      }

      final newStatus = TaskStatus.values.firstWhere(
        (s) => s.name == newStatusStr,
        orElse: () => throw ProtocolError('Invalid status: $newStatusStr'),
      );

      final insertAt = (params?['insertAt'] as num?)?.toInt();
      await taskManager.moveTask(taskId, newStatus, insertAt: insertAt);
      gateway.broadcast('kanban.changed');

      return {'status': 'ok'};
    });

    // --- Assign task to agent ---
    gateway.rpcRegistry.register('kanban.assign', (params, context) async {
      final taskId = params?['id'] as String?;
      if (taskId == null) throw ProtocolError('Missing required parameter: id');

      final agentId = params?['agentId'] as String?;
      final agentName = params?['agentName'] as String?;

      await taskManager.assignTask(taskId, agentId, agentName);
      gateway.broadcast('kanban.changed');
      return {'status': 'ok'};
    });

    // --- Delete task ---
    gateway.rpcRegistry.register('kanban.delete', (params, context) async {
      final taskId = params?['id'] as String?;
      if (taskId == null) throw ProtocolError('Missing required parameter: id');

      await taskManager.deleteTask(taskId);
      gateway.broadcast('kanban.changed');
      return {'status': 'ok'};
    });

    // --- Subtask management ---
    gateway.rpcRegistry.register('kanban.addSubtask', (params, context) async {
      final taskId = params?['taskId'] as String?;
      final title = params?['title'] as String?;
      if (taskId == null || title == null) {
        throw ProtocolError('Missing required parameters: taskId, title');
      }
      await taskManager.addSubtask(taskId, title);
      gateway.broadcast('kanban.changed');
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('kanban.toggleSubtask', (
      params,
      context,
    ) async {
      final taskId = params?['taskId'] as String?;
      final subtaskId = params?['subtaskId'] as String?;
      if (taskId == null || subtaskId == null) {
        throw ProtocolError('Missing required parameters: taskId, subtaskId');
      }
      await taskManager.toggleSubtask(taskId, subtaskId);
      gateway.broadcast('kanban.changed');
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('kanban.removeSubtask', (
      params,
      context,
    ) async {
      final taskId = params?['taskId'] as String?;
      final subtaskId = params?['subtaskId'] as String?;
      if (taskId == null || subtaskId == null) {
        throw ProtocolError('Missing required parameters: taskId, subtaskId');
      }
      await taskManager.removeSubtask(taskId, subtaskId);
      gateway.broadcast('kanban.changed');
      return {'status': 'ok'};
    });

    // --- Comment management ---
    gateway.rpcRegistry.register('kanban.addComment', (params, context) async {
      final taskId = params?['taskId'] as String?;
      final content = params?['content'] as String?;
      if (taskId == null || content == null) {
        throw ProtocolError('Missing required parameters: taskId, content');
      }
      await taskManager.addComment(
        taskId,
        authorId: params?['authorId'] as String? ?? 'user',
        authorName: params?['authorName'] as String? ?? 'User',
        content: content,
      );
      gateway.broadcast('kanban.changed');
      return {'status': 'ok'};
    });

    _log.info('Kanban RPC routes registered');
  }
}
