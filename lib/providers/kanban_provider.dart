// Ghost — Kanban Board Riverpod Provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/gateway.dart';
import '../engine/tasks/task.dart';
import 'gateway_provider.dart';

// ---------------------------------------------------------------------------
// Filter State
// ---------------------------------------------------------------------------

/// Filter options for the Kanban board.
class KanbanFilter {
  const KanbanFilter({
    this.agentId,
    this.priority,
    this.searchQuery = '',
    this.showCancelled = false,
  });

  final String? agentId;
  final TaskPriority? priority;
  final String searchQuery;
  final bool showCancelled;

  KanbanFilter copyWith({
    String? agentId,
    TaskPriority? priority,
    String? searchQuery,
    bool? showCancelled,
    bool clearAgent = false,
    bool clearPriority = false,
  }) {
    return KanbanFilter(
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      priority: clearPriority ? null : (priority ?? this.priority),
      searchQuery: searchQuery ?? this.searchQuery,
      showCancelled: showCancelled ?? this.showCancelled,
    );
  }

  bool get isActive =>
      agentId != null ||
      priority != null ||
      searchQuery.isNotEmpty ||
      showCancelled;
}

final kanbanFilterProvider =
    NotifierProvider<KanbanFilterNotifier, KanbanFilter>(() {
  return KanbanFilterNotifier();
});

class KanbanFilterNotifier extends Notifier<KanbanFilter> {
  @override
  KanbanFilter build() => const KanbanFilter();

  void update(KanbanFilter filter) => state = filter;
  void reset() => state = const KanbanFilter();
}

// ---------------------------------------------------------------------------
// Tasks Provider (fetches from Gateway)
// ---------------------------------------------------------------------------

final kanbanTasksProvider =
    NotifierProvider<KanbanTasksNotifier, List<KanbanTask>>(() {
  return KanbanTasksNotifier();
});

class KanbanTasksNotifier extends Notifier<List<KanbanTask>> {
  @override
  List<KanbanTask> build() {
    // Auto-refresh when authenticated
    ref.listen(connectionStatusProvider, (prev, next) {
      if (next.value == ConnectionStatus.authenticated) {
        refresh();
      }
    });

    // Listen for kanban changes from gateway
    final sub = ref.read(gatewayClientProvider).messages.listen((msg) {
      if (msg['method'] == 'kanban.changed') {
        refresh();
      }
    });
    ref.onDispose(() => sub.cancel());

    // Initial load
    final status = ref.read(connectionStatusProvider).value;
    if (status == ConnectionStatus.authenticated) {
      Future.microtask(() => refresh());
    }

    return [];
  }

  Future<void> refresh() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('kanban.list');
      final tasks = (result['tasks'] as List<dynamic>)
          .map((t) => KanbanTask.fromJson(t as Map<String, dynamic>))
          .toList();
      state = tasks;
    } catch (_) {}
  }

  Future<KanbanTask?> createTask({
    required String title,
    String description = '',
    TaskPriority priority = TaskPriority.normal,
    List<String> labels = const [],
  }) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('kanban.create', {
        'title': title,
        'description': description,
        'priority': priority.name,
        'labels': labels,
      });
      final task =
          KanbanTask.fromJson(result['task'] as Map<String, dynamic>);
      await refresh();
      return task;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateTask(KanbanTask task) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.update', {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'priority': task.priority.name,
        'labels': task.labels,
      });
      await refresh();
    } catch (_) {}
  }

  Future<void> moveTask(String taskId, TaskStatus newStatus, {int? insertAt}) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.move', {
        'id': taskId,
        'status': newStatus.name,
        if (insertAt != null) 'insertAt': insertAt,
      });
      await refresh();
    } catch (_) {}
  }

  Future<void> assignTask(String taskId, String? agentId, String? agentName) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.assign', {
        'id': taskId,
        'agentId': agentId,
        'agentName': agentName,
      });
      await refresh();
    } catch (_) {}
  }

  Future<void> deleteTask(String taskId) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.delete', {'id': taskId});
      await refresh();
    } catch (_) {}
  }

  Future<void> addSubtask(String taskId, String title) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.addSubtask', {
        'taskId': taskId,
        'title': title,
      });
      await refresh();
    } catch (_) {}
  }

  Future<void> toggleSubtask(String taskId, String subtaskId) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.toggleSubtask', {
        'taskId': taskId,
        'subtaskId': subtaskId,
      });
      await refresh();
    } catch (_) {}
  }

  Future<void> addComment(String taskId, String content) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('kanban.addComment', {
        'taskId': taskId,
        'content': content,
        'authorId': 'user',
        'authorName': 'User',
      });
      await refresh();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Filtered column providers
// ---------------------------------------------------------------------------

List<KanbanTask> _filteredByStatus(
  List<KanbanTask> tasks,
  TaskStatus status,
  KanbanFilter filter,
) {
  var result = tasks.where((t) => t.status == status);

  if (filter.agentId != null) {
    result = result.where((t) => t.assignedAgentId == filter.agentId);
  }
  if (filter.priority != null) {
    result = result.where((t) => t.priority == filter.priority);
  }
  if (filter.searchQuery.isNotEmpty) {
    final q = filter.searchQuery.toLowerCase();
    result = result.where(
      (t) =>
          t.title.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q) ||
          t.labels.any((l) => l.toLowerCase().contains(q)),
    );
  }

  return result.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

final kanbanBacklogProvider = Provider<List<KanbanTask>>((ref) {
  final tasks = ref.watch(kanbanTasksProvider);
  final filter = ref.watch(kanbanFilterProvider);
  return _filteredByStatus(tasks, TaskStatus.backlog, filter);
});

final kanbanInProgressProvider = Provider<List<KanbanTask>>((ref) {
  final tasks = ref.watch(kanbanTasksProvider);
  final filter = ref.watch(kanbanFilterProvider);
  return _filteredByStatus(tasks, TaskStatus.inProgress, filter);
});

final kanbanReviewProvider = Provider<List<KanbanTask>>((ref) {
  final tasks = ref.watch(kanbanTasksProvider);
  final filter = ref.watch(kanbanFilterProvider);
  return _filteredByStatus(tasks, TaskStatus.review, filter);
});

final kanbanDoneProvider = Provider<List<KanbanTask>>((ref) {
  final tasks = ref.watch(kanbanTasksProvider);
  final filter = ref.watch(kanbanFilterProvider);
  return _filteredByStatus(tasks, TaskStatus.done, filter);
});

final kanbanCancelledProvider = Provider<List<KanbanTask>>((ref) {
  final tasks = ref.watch(kanbanTasksProvider);
  final filter = ref.watch(kanbanFilterProvider);
  return _filteredByStatus(tasks, TaskStatus.cancelled, filter);
});
