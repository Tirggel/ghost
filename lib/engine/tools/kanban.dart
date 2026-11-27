// Ghost — Kanban Board Tools for Agents.


import 'dart:async';

import '../tasks/task.dart';
import '../tasks/task_manager.dart';
import '../tasks/task_orchestrator.dart';
import 'registry.dart';

/// Tools for interacting with the Kanban board.
class KanbanTools {
  KanbanTools._();

  /// Register all Kanban tools to the registry.
  static void registerAll(
    ToolRegistry registry,
    TaskManager taskManager, {
    TaskOrchestrator? orchestrator,
  }) {
    registry.register(KanbanListTool(taskManager));
    registry.register(KanbanCreateTool(taskManager));
    registry.register(KanbanUpdateTool(taskManager));
    registry.register(KanbanDetailTool(taskManager));
    registry.register(KanbanAssignTool(taskManager));
    registry.register(KanbanSubtaskTool(taskManager));
    registry.register(KanbanCommentTool(taskManager));

    if (orchestrator != null) {
      registry.register(KanbanPipelineTool(orchestrator));
      registry.register(KanbanSuggestTool(orchestrator));
      registry.register(GhostDelegateTaskTool(orchestrator));
    }
  }
}

/// Tool allowing the main agent (or orchestrating agent) to delegate a complex
/// sub-task to the best-suited specialist determined by the Ontology Knowledge Graph.
class GhostDelegateTaskTool extends Tool {
  GhostDelegateTaskTool(this.orchestrator);
  final TaskOrchestrator orchestrator;

  static const int maxDelegationDepth = 2;

  @override
  String get name => 'ghost_delegate_task';

  @override
  String get label => 'Delegate Task (Ontology)';

  @override
  String get description =>
      'Delegate a complex sub-task to the best-suited specialist agent using the '
      'Ontology Knowledge Graph (HAT_KOMPETENZ, DARF_NUTZEN, GEHOERT_ZU_DOMAIN, and '
      'current agent workload). Set dry_run=true to preview the routing recommendation '
      'without creating or starting a Kanban task.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'Short, clear title of the sub-task.',
          },
          'description': {
            'type': 'string',
            'description':
                'Detailed instructions and required context for the specialist agent.',
          },
          'required_competencies': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional domain/competency hints (e.g. ["Recherche", "Finanzen", "Coding"]).',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'normal', 'high', 'urgent'],
            'description': 'Task priority (default: normal).',
          },
          'parent_task_id': {
            'type': 'string',
            'description':
                'Optional parent Kanban task ID for traceability and delegation depth guard.',
          },
          'execute_immediately': {
            'type': 'boolean',
            'description':
                'If true (default), starts autonomous execution by the routed specialist right away.',
            'default': true,
          },
          'dry_run': {
            'type': 'boolean',
            'description':
                'If true, only evaluates and returns the ontology routing recommendation without creating a task.',
            'default': false,
          },
        },
        'required': ['title', 'description'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      'Ontology routing for "${input['title']}"';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final title = (input['title'] as String? ?? '').trim();
    final description = (input['description'] as String? ?? '').trim();
    if (title.isEmpty || description.isEmpty) {
      return const ToolResult.error(
        'Parameters "title" and "description" are required and must be non-empty.',
      );
    }

    final competencies = (input['required_competencies'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    final priorityStr = input['priority'] as String? ?? 'normal';
    final priority = TaskPriority.values.firstWhere(
      (p) => p.name == priorityStr,
      orElse: () => TaskPriority.normal,
    );
    final parentTaskId = (input['parent_task_id'] as String?)?.trim();
    final executeImmediately = input['execute_immediately'] as bool? ?? true;
    final dryRun = input['dry_run'] as bool? ?? false;

    int parentDepth = 0;
    if (parentTaskId != null && parentTaskId.isNotEmpty) {
      final parentTask = orchestrator.taskManager.getTask(parentTaskId);
      if (parentTask != null) {
        parentDepth = (parentTask.metadata['delegationDepth'] as num?)?.toInt() ?? 0;
      }
    }
    if (!dryRun && parentDepth >= maxDelegationDepth) {
      return ToolResult.error(
        'Maximum delegation depth ($maxDelegationDepth) reached for parent task $parentTaskId. '
        'Complete this sub-task directly instead of delegating further.',
      );
    }

    try {
      final previewTask = KanbanTask(
        title: title,
        description: description,
        priority: priority,
        labels: competencies,
      );

      final excludeIds = context.agentId == 'default-agent'
          ? const <String>[]
          : <String>[context.agentId];

      final previewDecision = await orchestrator.evaluateAgentRouting(
        previewTask,
        excludeAgentIds: excludeIds,
      );

      if (dryRun) {
        final topList = previewDecision.candidates
            .take(3)
            .map(
              (c) =>
                  '- ${c.agentName} (${c.agentId}): ${c.totalScore.toStringAsFixed(1)} pts '
                  '[comp=${c.competencyScore.toStringAsFixed(1)}, '
                  'skill=${c.skillScore.toStringAsFixed(1)}, '
                  'load=-${c.loadPenalty.toStringAsFixed(1)}]',
            )
            .join('\n');
        return ToolResult(
          output: 'Ontology Routing Preview:\n'
              'Recommended Agent: ${previewDecision.selectedAgentName} (${previewDecision.selectedAgentId})\n'
              'Score: ${previewDecision.score.toStringAsFixed(1)} | Reason: ${previewDecision.reason}\n'
              'Top Candidates:\n$topList',
          metadata: previewDecision.toMetadataJson(),
        );
      }

      final task = await orchestrator.taskManager.createTask(
        title: title,
        description: description,
        priority: priority,
        status: TaskStatus.backlog,
        labels: competencies,
        createdByAgentId: context.agentId,
        metadata: {
          'delegationDepth': parentDepth + 1,
          'delegatedByAgentId': context.agentId,
          if (parentTaskId != null && parentTaskId.isNotEmpty)
            'parentTaskId': parentTaskId,
        },
      );

      final decision = await orchestrator.routeTask(
        task.id,
        force: true,
        excludeAgentIds: excludeIds,
      );
      final routedTask = orchestrator.taskManager.getTask(task.id) ?? task;
      final selectedId =
          decision?.selectedAgentId ?? previewDecision.selectedAgentId;
      final selectedName =
          decision?.selectedAgentName ?? previewDecision.selectedAgentName;
      final reason = decision?.reason ?? previewDecision.reason;
      final score = decision?.score ?? previewDecision.score;

      bool started = false;
      if (executeImmediately && selectedId != context.agentId) {
        await orchestrator.taskManager.moveTask(routedTask.id, TaskStatus.inProgress);
        final activeTask = orchestrator.taskManager.getTask(routedTask.id) ?? routedTask;
        unawaited(orchestrator.executeTask(activeTask));
        started = true;
      }

      final statusNote = started
          ? 'Execution started in background (In Progress).'
          : (selectedId == context.agentId
              ? 'Assigned to you (no external specialist scored significantly higher); execute directly or track on Kanban.'
              : 'Queued in Backlog for $selectedName.');

      return ToolResult(
        output: 'Delegated task "${routedTask.title}" [${routedTask.id.substring(0, 8)}] '
            'to $selectedName ($selectedId).\n'
            'Routing: $reason (score: ${score.toStringAsFixed(1)})\n'
            '$statusNote',
        metadata: {
          'taskId': routedTask.id,
          'assignedAgentId': selectedId,
          'assignedAgentName': selectedName,
          'score': double.parse(score.toStringAsFixed(2)),
          'reason': reason,
          'started': started,
        },
      );
    } catch (e) {
      return ToolResult.error('Failed to delegate task: $e');
    }
  }
}

/// Tool to suggest an agent for a task.
class KanbanSuggestTool extends Tool {
  KanbanSuggestTool(this.orchestrator);
  final TaskOrchestrator orchestrator;

  @override
  String get name => 'kanban_suggest';

  @override
  String get description =>
      'Suggest the best agent for a task based on ontology competencies, skills, and workload.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'The task ID.',
          },
        },
        'required': ['taskId'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final taskIdSearch = input['taskId'] as String;
    final task = orchestrator.taskManager.tasks.firstWhere(
      (t) => t.id == taskIdSearch || t.id.startsWith(taskIdSearch),
      orElse: () => throw 'Task not found: $taskIdSearch',
    );

    try {
      final decision = await orchestrator.evaluateAgentRouting(task);
      return ToolResult(
        output: 'Suggested agent: ${decision.selectedAgentName} (${decision.selectedAgentId}) '
            '— ${decision.reason} (score: ${decision.score.toStringAsFixed(1)})',
        metadata: {
          'agentId': decision.selectedAgentId,
          'agentName': decision.selectedAgentName,
          ...decision.toMetadataJson(),
        },
      );
    } catch (e) {
      return ToolResult.error('Failed to suggest agent: $e');
    }
  }
}

/// Tool to create a pipeline of tasks.
class KanbanPipelineTool extends Tool {
  KanbanPipelineTool(this.orchestrator);
  final TaskOrchestrator orchestrator;

  @override
  String get name => 'kanban_pipeline';

  @override
  String get description =>
      'Create a sequential pipeline of tasks where each task depends on the previous one.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'titles': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Ordered list of task titles (e.g. ["Research", "Write", "Review"]).',
          },
          'assign_to_me': {
            'type': 'boolean',
            'description': 'If true, assigns all tasks in the pipeline to the calling agent.',
          },
        },
        'required': ['titles'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final titles = List<String>.from(input['titles'] as List);
    if (titles.isEmpty) return ToolResult.error('Titles list cannot be empty.');

    try {
      final tasks = await orchestrator.createPipeline(
        titles: titles,
        assignedAgentId: input['assign_to_me'] == true ? context.agentId : null,
        assignedAgentName: input['assign_to_me'] == true ? 'Agent' : null,
      );

      final buffer = StringBuffer();
      buffer.writeln('Pipeline created with ${tasks.length} tasks:');
      for (var i = 0; i < tasks.length; i++) {
        final dep = i > 0 ? ' (depends on ${tasks[i - 1].id.substring(0, 8)})' : '';
        buffer.writeln('${i + 1}. ${tasks[i].title} [${tasks[i].id.substring(0, 8)}]$dep');
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Failed to create pipeline: $e');
    }
  }
}

/// Tool to list tasks on the board.
class KanbanListTool extends Tool {
  KanbanListTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_list';

  @override
  String get description => 'List tasks from the Kanban board with optional filters.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'enum': ['backlog', 'in_progress', 'review', 'done', 'cancelled'],
            'description': 'Filter by task status.',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'normal', 'high', 'urgent'],
            'description': 'Filter by task priority.',
          },
          'assigned_to_me': {
            'type': 'boolean',
            'description': 'If true, only show tasks assigned to the calling agent.',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    try {
      var tasks = taskManager.tasks;

      final statusStr = input['status'] as String?;
      if (statusStr != null) {
        final status = TaskStatus.values.firstWhere((s) => s.name == _toCamelCase(statusStr));
        tasks = tasks.where((t) => t.status == status).toList();
      }

      final priorityStr = input['priority'] as String?;
      if (priorityStr != null) {
        final priority = TaskPriority.values.firstWhere((p) => p.name == priorityStr);
        tasks = tasks.where((t) => t.priority == priority).toList();
      }

      if (input['assigned_to_me'] == true) {
        tasks = tasks.where((t) => t.assignedAgentId == context.agentId).toList();
      }

      if (tasks.isEmpty) {
        return const ToolResult(output: 'No tasks found matching the criteria.');
      }

      final buffer = StringBuffer();
      buffer.writeln('Kanban Tasks:');
      for (final t in tasks) {
        final assigned = t.assignedAgentName != null ? ' (Assigned to: ${t.assignedAgentName})' : '';
        buffer.writeln('- [${t.id.substring(0, 8)}] ${t.title} | Status: ${t.status.name} | Priority: ${t.priority.name}$assigned');
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Failed to list tasks: $e');
    }
  }

  String _toCamelCase(String s) {
    if (!s.contains('_')) return s;
    final parts = s.split('_');
    return parts[0] + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }
}

/// Tool to create a new task.
class KanbanCreateTool extends Tool {
  KanbanCreateTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_create';

  @override
  String get description => 'Create a new task on the Kanban board.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'The title of the task.',
          },
          'description': {
            'type': 'string',
            'description': 'A detailed description of what needs to be done.',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'normal', 'high', 'urgent'],
            'description': 'The priority of the task (default: normal).',
          },
          'labels': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional domain/competency labels for the task.',
          },
          'assign_to_me': {
            'type': 'boolean',
            'description': 'If true, assigns the task to the calling agent immediately.',
          },
          'auto_route': {
            'type': 'boolean',
            'description':
                'If true (default when assign_to_me is false), automatically routes the task via Ontology.',
            'default': true,
          },
        },
        'required': ['title'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final title = input['title'] as String;
    final description = input['description'] as String? ?? '';
    final priorityStr = input['priority'] as String? ?? 'normal';
    final priority = TaskPriority.values.firstWhere((p) => p.name == priorityStr);
    final labels = (input['labels'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final assignToMe = input['assign_to_me'] == true;
    final autoRoute = !assignToMe && (input['auto_route'] as bool? ?? true);

    try {
      final task = await taskManager.createTask(
        title: title,
        description: description,
        priority: priority,
        labels: labels,
        assignedAgentId: assignToMe
            ? context.agentId
            : (autoRoute ? KanbanTask.autoAgentId : null),
        assignedAgentName: assignToMe
            ? 'Agent'
            : (autoRoute ? 'Auto (Ontologie)' : null),
      );

      return ToolResult(
        output: 'Task created successfully with ID: ${task.id}',
        metadata: {'taskId': task.id},
      );
    } catch (e) {
      return ToolResult.error('Failed to create task: $e');
    }
  }
}

/// Tool to update a task.
class KanbanUpdateTool extends Tool {
  KanbanUpdateTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_update';

  @override
  String get description => 'Update a task\'s status, priority, or details.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'The full ID or the first 8 characters of the task ID.',
          },
          'status': {
            'type': 'string',
            'enum': ['backlog', 'in_progress', 'review', 'done', 'cancelled'],
            'description': 'Update the status.',
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'normal', 'high', 'urgent'],
            'description': 'Update the priority.',
          },
          'title': {
            'type': 'string',
            'description': 'Update the title.',
          },
          'description': {
            'type': 'string',
            'description': 'Update the description.',
          },
        },
        'required': ['taskId'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final taskIdSearch = input['taskId'] as String;
    final tasks = taskManager.tasks;
    final task = tasks.firstWhere(
      (t) => t.id == taskIdSearch || t.id.startsWith(taskIdSearch),
      orElse: () => throw 'Task not found: $taskIdSearch',
    );

    try {
      // Handle status move separately as it might have logic later
      final statusStr = input['status'] as String?;
      if (statusStr != null) {
        final status = TaskStatus.values.firstWhere((s) => s.name == _toCamelCase(statusStr));
        await taskManager.moveTask(task.id, status);
      }

      // Update other fields
      final updated = task.copyWith(
        title: input['title'] as String?,
        description: input['description'] as String?,
        priority: input['priority'] != null 
            ? TaskPriority.values.firstWhere((p) => p.name == input['priority']) 
            : null,
      );

      if (updated != task) {
        await taskManager.updateTask(updated);
      }

      return ToolResult(output: 'Task ${task.id.substring(0, 8)} updated successfully.');
    } catch (e) {
      return ToolResult.error('Failed to update task: $e');
    }
  }

  String _toCamelCase(String s) {
    if (!s.contains('_')) return s;
    final parts = s.split('_');
    return parts[0] + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }
}

/// Tool to get task details.
class KanbanDetailTool extends Tool {
  KanbanDetailTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_detail';

  @override
  String get description => 'Get full details of a specific task, including subtasks and comments.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'The full ID or the first 8 characters of the task ID.',
          },
        },
        'required': ['taskId'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final taskIdSearch = input['taskId'] as String;
    final tasks = taskManager.tasks;
    final task = tasks.firstWhere(
      (t) => t.id == taskIdSearch || t.id.startsWith(taskIdSearch),
      orElse: () => throw 'Task not found: $taskIdSearch',
    );

    final buffer = StringBuffer();
    buffer.writeln('Task Details [${task.id}]:');
    buffer.writeln('Title: ${task.title}');
    buffer.writeln('Status: ${task.status.name}');
    buffer.writeln('Priority: ${task.priority.name}');
    buffer.writeln('Assigned To: ${task.assignedAgentName ?? 'Unassigned'}');
    buffer.writeln('Description: ${task.description}');
    
    if (task.subtasks.isNotEmpty) {
      buffer.writeln('\nSubtasks:');
      for (final sub in task.subtasks) {
        final check = sub.done ? '[x]' : '[ ]';
        buffer.writeln('- $check ${sub.title}');
      }
    }

    if (task.comments.isNotEmpty) {
      buffer.writeln('\nComments:');
      for (final c in task.comments) {
        buffer.writeln('- ${c.authorName}: ${c.content} (${c.timestamp.toIso8601String()})');
      }
    }

    return ToolResult(output: buffer.toString());
  }
}

/// Tool to assign a task.
class KanbanAssignTool extends Tool {
  KanbanAssignTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_assign';

  @override
  String get description => 'Assign a task to an agent (or yourself).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'The task ID.',
          },
          'assign_to_me': {
            'type': 'boolean',
            'description': 'If true, assigns the task to the calling agent.',
          },
        },
        'required': ['taskId'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final taskIdSearch = input['taskId'] as String;
    final tasks = taskManager.tasks;
    final task = tasks.firstWhere(
      (t) => t.id == taskIdSearch || t.id.startsWith(taskIdSearch),
      orElse: () => throw 'Task not found: $taskIdSearch',
    );

    try {
      if (input['assign_to_me'] == true) {
        await taskManager.assignTask(task.id, context.agentId, 'Agent');
        return ToolResult(output: 'Task ${task.id.substring(0, 8)} assigned to you.');
      } else {
        return ToolResult.error('Please specify who to assign to (only assign_to_me supported for now).');
      }
    } catch (e) {
      return ToolResult.error('Failed to assign task: $e');
    }
  }
}

/// Tool to manage subtasks.
class KanbanSubtaskTool extends Tool {
  KanbanSubtaskTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_subtask';

  @override
  String get description => 'Add or toggle a subtask.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'The task ID.',
          },
          'action': {
            'type': 'string',
            'enum': ['add', 'toggle'],
            'description': 'Action to perform.',
          },
          'title': {
            'type': 'string',
            'description': 'The title of the subtask (required for "add").',
          },
          'subtaskId': {
            'type': 'string',
            'description': 'The subtask ID to toggle (required for "toggle").',
          },
        },
        'required': ['taskId', 'action'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final taskIdSearch = input['taskId'] as String;
    final tasks = taskManager.tasks;
    final task = tasks.firstWhere(
      (t) => t.id == taskIdSearch || t.id.startsWith(taskIdSearch),
      orElse: () => throw 'Task not found: $taskIdSearch',
    );

    final action = input['action'] as String;

    try {
      if (action == 'add') {
        final title = input['title'] as String?;
        if (title == null || title.isEmpty) return ToolResult.error('Title required for adding subtask.');
        await taskManager.addSubtask(task.id, title);
        return const ToolResult(output: 'Subtask added successfully.');
      } else if (action == 'toggle') {
        final subId = input['subtaskId'] as String?;
        if (subId == null || subId.isEmpty) return ToolResult.error('subtaskId required for toggling.');
        await taskManager.toggleSubtask(task.id, subId);
        return const ToolResult(output: 'Subtask toggled successfully.');
      }
      return ToolResult.error('Unknown action: $action');
    } catch (e) {
      return ToolResult.error('Failed to manage subtask: $e');
    }
  }
}

/// Tool to add a comment.
class KanbanCommentTool extends Tool {
  KanbanCommentTool(this.taskManager);
  final TaskManager taskManager;

  @override
  String get name => 'kanban_comment';

  @override
  String get description => 'Add a comment to a task.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'taskId': {
            'type': 'string',
            'description': 'The task ID.',
          },
          'content': {
            'type': 'string',
            'description': 'The content of the comment.',
          },
        },
        'required': ['taskId', 'content'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input, ToolContext context) async {
    final taskIdSearch = input['taskId'] as String;
    final tasks = taskManager.tasks;
    final task = tasks.firstWhere(
      (t) => t.id == taskIdSearch || t.id.startsWith(taskIdSearch),
      orElse: () => throw 'Task not found: $taskIdSearch',
    );

    final content = input['content'] as String;

    try {
      await taskManager.addComment(
        task.id,
        authorId: context.agentId,
        authorName: 'Agent', // We should ideally get agent name here
        content: content,
      );
      return const ToolResult(output: 'Comment added successfully.');
    } catch (e) {
      return ToolResult.error('Failed to add comment: $e');
    }
  }
}
