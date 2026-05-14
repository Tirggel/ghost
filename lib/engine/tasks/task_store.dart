// Ghost — Kanban Task Store (JSON file-based persistence).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'task.dart';

final _log = Logger('Ghost.TaskStore');

/// Persists Kanban tasks as JSON files in `<stateDir>/tasks/`.
class TaskStore {
  TaskStore({required this.stateDir});

  final String stateDir;

  String get _tasksDir => p.join(stateDir, 'tasks');

  final _changedController = StreamController<void>.broadcast();

  /// Notifies listeners when the task data changes on disk.
  Stream<void> get onChanged => _changedController.stream;

  /// Ensure the tasks directory exists.
  Future<void> initialize() async {
    final dir = Directory(_tasksDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      _log.info('Created tasks directory: $_tasksDir');
    }
  }

  /// Load all tasks from disk.
  Future<List<KanbanTask>> loadAll() async {
    final dir = Directory(_tasksDir);
    if (!await dir.exists()) return [];

    final tasks = <KanbanTask>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          tasks.add(KanbanTask.fromJson(json));
        } catch (e) {
          _log.warning('Failed to load task from ${entity.path}: $e');
        }
      }
    }

    // Sort by sortOrder, then by createdAt
    tasks.sort((a, b) {
      final orderCmp = a.sortOrder.compareTo(b.sortOrder);
      if (orderCmp != 0) return orderCmp;
      return a.createdAt.compareTo(b.createdAt);
    });

    return tasks;
  }

  /// Save (create or update) a single task.
  Future<void> save(KanbanTask task) async {
    await initialize();
    final file = File(p.join(_tasksDir, '${task.id}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(task.toJson()),
    );
    _changedController.add(null);
    _log.fine('Saved task ${task.id}: ${task.title}');
  }

  /// Delete a task by ID.
  Future<void> delete(String taskId) async {
    final file = File(p.join(_tasksDir, '$taskId.json'));
    if (await file.exists()) {
      await file.delete();
      _changedController.add(null);
      _log.info('Deleted task $taskId');
    }
  }

  /// Load a single task by ID.
  Future<KanbanTask?> load(String taskId) async {
    final file = File(p.join(_tasksDir, '$taskId.json'));
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return KanbanTask.fromJson(json);
    } catch (e) {
      _log.warning('Failed to load task $taskId: $e');
      return null;
    }
  }

  /// Export all tasks as a JSON string (for backup).
  Future<String> export() async {
    final tasks = await loadAll();
    return jsonEncode(tasks.map((t) => t.toJson()).toList());
  }

  /// Import tasks from a JSON string (for restore).
  Future<void> import_(String data) async {
    await initialize();
    final list = jsonDecode(data) as List<dynamic>;
    for (final item in list) {
      final task = KanbanTask.fromJson(item as Map<String, dynamic>);
      await save(task);
    }
    _log.info('Imported ${list.length} tasks');
  }

  void dispose() {
    _changedController.close();
  }
}
