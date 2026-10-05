// Ghost — System-1 Decision Service (ModernBERT INT8 ONNX Engine)
// High-performance, non-autoregressive decision middleware for Ghost.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../infra/env.dart';

final _log = Logger('Ghost.System1Service');

/// Result of a categorical choice decision.
class ChoiceResult {
  const ChoiceResult({
    required this.winner,
    required this.confidence,
    required this.rawScores,
    this.elapsedMs,
  });

  factory ChoiceResult.fromJson(Map<String, dynamic> json) {
    return ChoiceResult(
      winner: json['winner'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      rawScores: (json['raw_scores'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          {},
      elapsedMs: (json['elapsed_ms'] as num?)?.toDouble(),
    );
  }

  final String winner;
  final double confidence;
  final Map<String, double> rawScores;
  final double? elapsedMs;

  @override
  String toString() =>
      'ChoiceResult(winner: $winner, confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Service managing the lifecycle and IPC communication with the
/// `scripts/system1_daemon.py` background worker.
class System1Service {
  System1Service._();
  static final System1Service instance = System1Service._();

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _requestIdCounter = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  bool _isStarting = false;

  /// Check whether the ONNX model file exists on disk.
  bool isModelAvailable() {
    final modelPath = getModelPath();
    return File(modelPath).existsSync();
  }

  /// Get the absolute path to the ONNX model.
  String getModelPath() {
    return p.join(Env.scriptsDir, 'models', 'ghost_system1_int8.onnx');
  }

  /// Check whether the daemon script exists on disk.
  bool isDaemonScriptAvailable() {
    final scriptPath = getDaemonScriptPath();
    return File(scriptPath).existsSync();
  }

  /// Get the absolute path to `system1_daemon.py`.
  String getDaemonScriptPath() {
    return p.join(Env.scriptsDir, 'system1_daemon.py');
  }

  /// Resolves the most appropriate python binary, prioritizing local venv.
  String resolvePythonExecutable() {
    final scriptsDir = Env.scriptsDir;
    
    // 1. Check venv inside scripts directory
    final venvBin = Platform.isWindows
        ? p.join(scriptsDir, '.venv', 'Scripts', 'python.exe')
        : p.join(scriptsDir, '.venv', 'bin', 'python');
    if (File(venvBin).existsSync()) {
      _log.fine('Found virtualenv python at: $venvBin');
      return venvBin;
    }

    // 2. Check root workspace venv if running in development
    final rootVenv = Platform.isWindows
        ? p.join(Directory.current.path, '.venv', 'Scripts', 'python.exe')
        : p.join(Directory.current.path, '.venv', 'bin', 'python');
    if (File(rootVenv).existsSync()) {
      _log.fine('Found root virtualenv python at: $rootVenv');
      return rootVenv;
    }

    // 3. Fallback to system python
    return Platform.isWindows ? 'python' : 'python3';
  }

  /// Check whether the daemon process is alive and running.
  bool get isRunning => _process != null;

  /// Start the background daemon if not already running.
  Future<bool> start() async {
    if (_process != null) return true;
    if (_isStarting) return false;

    if (!isModelAvailable()) {
      _log.warning('Cannot start System1Service: Model missing at ${getModelPath()}');
      return false;
    }

    if (!isDaemonScriptAvailable()) {
      _log.warning('Cannot start System1Service: Script missing at ${getDaemonScriptPath()}');
      return false;
    }

    _isStarting = true;
    try {
      final pythonExe = resolvePythonExecutable();
      final scriptPath = getDaemonScriptPath();

      _log.info('Starting System-1 daemon: $pythonExe $scriptPath');
      final proc = await Process.start(
        pythonExe,
        [scriptPath],
        workingDirectory: Env.scriptsDir,
      );

      _process = proc;

      // Handle stdout lines
      _stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleStdoutLine,
        onError: (err) => _log.warning('System-1 stdout error: $err'),
        onDone: () {
          _log.info('System-1 daemon stdout closed.');
          _cleanupProcess();
        },
      );

      // Handle stderr lines (logs / readiness signals)
      _stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.contains('SYSTEM1_READY')) {
          _log.info('System-1 Daemon is READY (ModernBERT INT8 loaded).');
        } else if (line.contains('ERROR:')) {
          _log.severe('System-1 Daemon error: $line');
        } else {
          _log.fine('System-1 stderr: $line');
        }
      });

      proc.exitCode.then((code) {
        _log.info('System-1 daemon exited with code: $code');
        _cleanupProcess();
      });

      // Quick ping test
      final pong = await ping();
      if (!pong) {
        _log.warning('System-1 ping failed after startup. Process might have crashed.');
        stop();
        return false;
      }

      _log.info('System-1 Service started successfully.');
      return true;
    } catch (e) {
      _log.severe('Failed to launch System-1 daemon: $e');
      _cleanupProcess();
      return false;
    } finally {
      _isStarting = false;
    }
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final id = json['id'] as int?;
      if (id != null && _pendingRequests.containsKey(id)) {
        final completer = _pendingRequests.remove(id);
        completer?.complete(json);
      }
    } catch (e) {
      _log.warning('Failed to parse System-1 response line: "$trimmed" ($e)');
    }
  }

  void _cleanupProcess() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _process = null;

    // Fail all pending completers
    for (final entry in _pendingRequests.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
          StateError('System-1 daemon exited unexpectedly'),
        );
      }
    }
    _pendingRequests.clear();
  }

  /// Sends a raw JSON request to the daemon and returns the parsed response.
  Future<Map<String, dynamic>?> _sendRequest(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    if (_process == null) {
      final started = await start();
      if (!started || _process == null) return null;
    }

    final id = ++_requestIdCounter;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final fullPayload = {...payload, 'id': id};
    try {
      _process!.stdin.writeln(jsonEncode(fullPayload));
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _log.warning('System-1 request #$id timed out after ${timeout.inMilliseconds}ms');
          _pendingRequests.remove(id);
          return {};
        },
      );
    } catch (e) {
      _log.warning('System-1 IPC write failed: $e');
      _pendingRequests.remove(id);
      return null;
    }
  }

  /// Ping the daemon to test liveness.
  Future<bool> ping() async {
    final res = await _sendRequest(
      {'method': 'ping'},
      timeout: const Duration(milliseconds: 3000),
    );
    return res != null && res['status'] == 'pong';
  }

  /// Noul: Binary probability decision (0.0 to 1.0).
  /// Returns `null` if the model or daemon is unavailable.
  Future<double?> noul({
    required String premise,
    required String hypothesis,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final res = await _sendRequest(
      {
        'method': 'noul',
        'premise': premise,
        'hypothesis': hypothesis,
      },
      timeout: timeout,
    );

    if (res != null && res['status'] == 'ok' && res['score'] is num) {
      return (res['score'] as num).toDouble();
    }
    return null;
  }

  /// Score: Continuous rating decision (0.0 to 1.0).
  /// Returns `null` if the model or daemon is unavailable.
  Future<double?> score({
    required String premise,
    required String hypothesis,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final res = await _sendRequest(
      {
        'method': 'score',
        'premise': premise,
        'hypothesis': hypothesis,
      },
      timeout: timeout,
    );

    if (res != null && res['status'] == 'ok' && res['score'] is num) {
      return (res['score'] as num).toDouble();
    }
    return null;
  }

  /// Choice: Categorical option selection from a list of strings.
  /// Returns `null` if the model or daemon is unavailable.
  Future<ChoiceResult?> choice({
    required String premise,
    required List<String> options,
    double temperature = 0.15,
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    if (options.isEmpty) return null;

    final res = await _sendRequest(
      {
        'method': 'choice',
        'premise': premise,
        'options': options,
        'temperature': temperature,
      },
      timeout: timeout,
    );

    if (res != null && res['status'] == 'ok' && res['winner'] is String) {
      return ChoiceResult.fromJson(res);
    }
    return null;
  }

  /// Safely stops the daemon process and releases memory (Zombie protection).
  Future<void> stop() async {
    if (_process == null) return;
    _log.info('Stopping System-1 daemon...');
    try {
      await _process!.stdin.close();
    } catch (_) {}

    try {
      _process!.kill(ProcessSignal.sigterm);
    } catch (_) {}

    // Allow a brief moment for clean exit before SIGKILL
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }

    _cleanupProcess();
    _log.info('System-1 daemon stopped.');
  }

  /// Dispose the service on app termination.
  void dispose() {
    stop();
  }
}
