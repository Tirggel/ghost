// Ghost — Structured logging with secret filtering.

import 'package:logging/logging.dart';

/// Initializes the Ghost logging system.
///
/// Call this once at startup before using any loggers.
void initLogging({Level level = Level.INFO, bool verbose = false}) {
  Logger.root.level = verbose ? Level.ALL : level;
  Logger.root.onRecord.listen(_handleLogRecord);
}

/// Patterns that are filtered from log output to prevent secret leakage.
final List<RegExp> _secretPatterns = [
  // API keys (generic patterns)
  RegExp(r'sk-[a-zA-Z0-9]{20,}'),
  RegExp(r'sk-ant-[a-zA-Z0-9\-]{20,}'),
  // Bearer tokens
  RegExp(r'Bearer\s+[a-zA-Z0-9\-._~+/]+=*', caseSensitive: false),
  // Generic long hex tokens
  RegExp(r'[a-fA-F0-9]{64,}'),
];

/// Replacement string for filtered secrets.
const String _redacted = '[REDACTED]';

/// Filter secrets from a log message.
String filterSecrets(String message) {
  var filtered = message;
  for (final pattern in _secretPatterns) {
    filtered = filtered.replaceAll(pattern, _redacted);
  }
  return filtered;
}

/// Add a custom secret pattern to the filter.
void addSecretPattern(RegExp pattern) {
  _secretPatterns.add(pattern);
}

void _handleLogRecord(LogRecord record) {
  final time = record.time.toIso8601String().substring(11, 23);
  final level = record.level.name.padRight(7);
  final name = record.loggerName;
  final message = filterSecrets(record.message);

  // ignore: avoid_print
  print('$time $level [$name] $message');

  if (record.error != null) {
    final errorStr = filterSecrets(record.error.toString());
    // ignore: avoid_print
    print('  Error: $errorStr');
  }
  if (record.stackTrace != null) {
    // ignore: avoid_print
    print('  ${record.stackTrace}');
  }
}

/// Creates a named logger for a Ghost module.
Logger createLogger(String name) => Logger('Ghost.$name');
