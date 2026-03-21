// Ghost — Config I/O: loading, saving, and file watching for hot-reload.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:watcher/watcher.dart';

import '../infra/errors.dart';
import 'config.dart';
import 'schema.dart';

final _log = Logger('Ghost.ConfigIO');

/// Loads configuration from a JSON file.
///
/// Returns [GhostConfig] with defaults for missing values.
/// Throws [ConfigError] if the file exists but contains invalid JSON.
Future<GhostConfig> loadConfig(String path) async {
  final file = File(path);

  if (!await file.exists()) {
    _log.info('Config file not found at $path — using defaults');
    return const GhostConfig();
  }

  try {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // Validate JSON structure
    final jsonErrors = validateConfigJson(json);
    if (jsonErrors.isNotEmpty) {
      _log.warning(
        'Config validation warnings:\n  - ${jsonErrors.join('\n  - ')}',
      );
    }

    final config = GhostConfig.fromJson(json);
    _log.fine('Config loaded from $path');
    return config;
  } on FormatException catch (e) {
    throw ConfigError(
      'Invalid JSON in config file: $path',
      code: 'INVALID_JSON',
      cause: e,
    );
  }
}

/// Saves configuration to a JSON file.
///
/// Creates parent directories if they don't exist.
Future<void> saveConfig(GhostConfig config, String path) async {
  final file = File(path);
  await file.parent.create(recursive: true);

  final json = const JsonEncoder.withIndent('  ')
      .convert(config.toJson(includeAgent: false));
  await file.writeAsString('$json\n');
  _log.info('Config saved to $path');
}

/// Watches a config file for changes and triggers a callback.
///
/// Returns a [StreamSubscription] that can be cancelled to stop watching.
StreamSubscription<WatchEvent> watchConfig(
  String path,
  void Function(GhostConfig config) onChanged, {
  void Function(Object error)? onError,
}) {
  final watcher = FileWatcher(path);

  return watcher.events.listen(
    (event) async {
      if (event.type == ChangeType.MODIFY || event.type == ChangeType.ADD) {
        _log.info('Config file changed: ${event.path}');
        try {
          final config = await loadConfig(event.path);
          onChanged(config);
        } catch (e) {
          _log.severe('Error reloading config: $e');
          onError?.call(e);
        }
      }
    },
    onError: (Object error) {
      _log.severe('Config watcher error: $error');
      onError?.call(error);
    },
  );
}

/// Returns the default config file path.
String defaultConfigPath() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  return '$home/.ghost/ghost.json';
}
