// Ghost — Persistent JSON Store for Automations and Run History.
// Pure Dart (no Flutter/dart:ui imports).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'automation_models.dart';

final _log = Logger('Ghost.AutomationStore');

/// Persists [Automation] definitions and [AutomationRun] logs under
/// `<stateDir>/automations/`.
class AutomationStore {
  AutomationStore({
    required this.stateDir,
    this.maxRunsPerAutomation = 100,
  });

  final String stateDir;
  final int maxRunsPerAutomation;

  String get rootDir => p.join(stateDir, 'automations');
  String get _definitionsDir => p.join(rootDir, 'definitions');
  String get _runsDir => p.join(rootDir, 'runs');

  final _changedController = StreamController<void>.broadcast();
  Stream<void> get onChanged => _changedController.stream;

  Future<void> initialize() async {
    await Directory(_definitionsDir).create(recursive: true);
    await Directory(_runsDir).create(recursive: true);
  }

  /// Load all automation definitions sorted by `createdAt` ascending.
  Future<List<Automation>> loadAll() async {
    final dir = Directory(_definitionsDir);
    if (!await dir.exists()) return [];

    final items = <Automation>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final raw = await entity.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          items.add(Automation.fromJson(json));
        } catch (e) {
          _log.warning('Failed to load automation ${entity.path}: $e');
        }
      }
    }

    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  Future<Automation?> load(String id) async {
    final file = File(p.join(_definitionsDir, '$id.json'));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return Automation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      _log.warning('Failed to load automation $id: $e');
      return null;
    }
  }

  Future<void> save(Automation automation) async {
    await initialize();
    final file = File(p.join(_definitionsDir, '${automation.id}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(automation.toJson()),
    );
    if (!_changedController.isClosed) {
      _changedController.add(null);
    }
  }

  /// Delete an automation definition and its run history file.
  Future<void> delete(String id) async {
    final defFile = File(p.join(_definitionsDir, '$id.json'));
    if (await defFile.exists()) {
      await defFile.delete();
    }
    final runsFile = File(p.join(_runsDir, '$id.json'));
    if (await runsFile.exists()) {
      await runsFile.delete();
    }
    if (!_changedController.isClosed) {
      _changedController.add(null);
    }
  }

  /// Load persisted run history for [automationId] (newest first).
  Future<List<AutomationRun>> loadRuns(
    String automationId, {
    int? limit,
  }) async {
    final file = File(p.join(_runsDir, '$automationId.json'));
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      final runs = list
          .map((e) => AutomationRun.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (limit != null && runs.length > limit) {
        return runs.sublist(0, limit);
      }
      return runs;
    } catch (e) {
      _log.warning('Failed to load runs for $automationId: $e');
      return [];
    }
  }

  /// Insert or update a single [AutomationRun] in `<automationId>.json`.
  Future<void> saveRun(AutomationRun run) async {
    await initialize();
    final runs = await loadRuns(run.automationId);
    final idx = runs.indexWhere((r) => r.id == run.id);
    if (idx >= 0) {
      runs[idx] = run;
    } else {
      runs.insert(0, run);
    }
    runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (runs.length > maxRunsPerAutomation) {
      runs.removeRange(maxRunsPerAutomation, runs.length);
    }

    final file = File(p.join(_runsDir, '${run.automationId}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(runs.map((r) => r.toJson()).toList()),
    );
  }

  /// Export all definitions and run histories as a single portable JSON string.
  Future<String> exportAll() async {
    final automations = await loadAll();
    final runsByAutomation = <String, List<Map<String, dynamic>>>{};
    for (final a in automations) {
      final runs = await loadRuns(a.id);
      runsByAutomation[a.id] = runs.map((r) => r.toJson()).toList();
    }
    return jsonEncode({
      'version': 1,
      'automations': automations.map((a) => a.toJson()).toList(),
      'runs': runsByAutomation,
    });
  }

  /// Import definitions and run histories from an exported JSON string.
  Future<void> importAll(String raw) async {
    await initialize();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['automations'] as List<dynamic>? ?? const [];
    final runsMap = decoded['runs'] as Map<String, dynamic>? ?? const {};

    for (final item in list) {
      final automation =
          Automation.fromJson(Map<String, dynamic>.from(item as Map));
      await save(automation);
      final rawRuns = runsMap[automation.id] as List<dynamic>?;
      if (rawRuns != null) {
        final runs = rawRuns
            .map((e) => AutomationRun.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        final file = File(p.join(_runsDir, '${automation.id}.json'));
        await file.writeAsString(
          const JsonEncoder.withIndent('  ')
              .convert(runs.map((r) => r.toJson()).toList()),
        );
      }
    }
  }

  void dispose() {
    _changedController.close();
  }
}
