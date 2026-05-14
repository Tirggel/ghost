// Ghost — Kanban Task data model.

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Status of a Kanban task.
enum TaskStatus { backlog, inProgress, review, done, cancelled }

/// Priority level of a task.
enum TaskPriority { low, normal, high, urgent }

/// A comment on a task — from user or agent.
class TaskComment {
  TaskComment({
    String? id,
    required this.authorId,
    required this.authorName,
    required this.content,
    DateTime? timestamp,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    return TaskComment(
      id: json['id'] as String?,
      authorId: json['authorId'] as String? ?? 'user',
      authorName: json['authorName'] as String? ?? 'User',
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A single task on the Kanban board.
class KanbanTask {
  KanbanTask({
    String? id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.backlog,
    this.priority = TaskPriority.normal,
    this.assignedAgentId,
    this.assignedAgentName,
    this.createdByAgentId,
    this.sessionId,
    this.labels = const [],
    this.subtasks = const [],
    this.comments = const [],
    this.dependsOnIds = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.dueDate,
    this.sortOrder = 0,
    this.metadata = const {},
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory KanbanTask.fromJson(Map<String, dynamic> json) {
    return KanbanTask(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: TaskStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String?),
        orElse: () => TaskStatus.backlog,
      ),
      priority: TaskPriority.values.firstWhere(
        (p) => p.name == (json['priority'] as String?),
        orElse: () => TaskPriority.normal,
      ),
      assignedAgentId: json['assignedAgentId'] as String?,
      assignedAgentName: json['assignedAgentName'] as String?,
      createdByAgentId: json['createdByAgentId'] as String?,
      sessionId: json['sessionId'] as String?,
      labels: (json['labels'] as List<dynamic>?)?.cast<String>() ?? [],
      subtasks: (json['subtasks'] as List<dynamic>?)
              ?.map((e) => SubTask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      comments: (json['comments'] as List<dynamic>?)
              ?.map((e) => TaskComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dependsOnIds: (json['dependsOnIds'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  final String id;
  String title;
  String description;
  TaskStatus status;
  TaskPriority priority;
  String? assignedAgentId;
  String? assignedAgentName;
  String? createdByAgentId;
  String? sessionId;
  List<String> labels;
  List<SubTask> subtasks;
  List<TaskComment> comments;
  List<String> dependsOnIds;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? dueDate;
  int sortOrder;
  Map<String, dynamic> metadata;

  /// Completed subtasks count.
  int get completedSubtasks => subtasks.where((s) => s.done).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'priority': priority.name,
        if (assignedAgentId != null) 'assignedAgentId': assignedAgentId,
        if (assignedAgentName != null) 'assignedAgentName': assignedAgentName,
        if (createdByAgentId != null) 'createdByAgentId': createdByAgentId,
        if (sessionId != null) 'sessionId': sessionId,
        'labels': labels,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'comments': comments.map((c) => c.toJson()).toList(),
        'dependsOnIds': dependsOnIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
        'sortOrder': sortOrder,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  KanbanTask copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    String? assignedAgentId,
    String? assignedAgentName,
    String? createdByAgentId,
    String? sessionId,
    List<String>? labels,
    List<SubTask>? subtasks,
    List<TaskComment>? comments,
    List<String>? dependsOnIds,
    DateTime? updatedAt,
    DateTime? dueDate,
    int? sortOrder,
    Map<String, dynamic>? metadata,
    bool clearAssignedAgent = false,
    bool clearDueDate = false,
  }) {
    return KanbanTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      assignedAgentId:
          clearAssignedAgent ? null : (assignedAgentId ?? this.assignedAgentId),
      assignedAgentName: clearAssignedAgent
          ? null
          : (assignedAgentName ?? this.assignedAgentName),
      createdByAgentId: createdByAgentId ?? this.createdByAgentId,
      sessionId: sessionId ?? this.sessionId,
      labels: labels ?? this.labels,
      subtasks: subtasks ?? this.subtasks,
      comments: comments ?? this.comments,
      dependsOnIds: dependsOnIds ?? this.dependsOnIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      sortOrder: sortOrder ?? this.sortOrder,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// A subtask (checklist item) on a task.
class SubTask {
  SubTask({
    String? id,
    required this.title,
    this.done = false,
  }) : id = id ?? _uuid.v4();

  factory SubTask.fromJson(Map<String, dynamic> json) {
    return SubTask(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '',
      done: json['done'] as bool? ?? false,
    );
  }

  final String id;
  String title;
  bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
      };
}
