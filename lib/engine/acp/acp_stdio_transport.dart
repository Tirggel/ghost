// Ghost — ACP STDIO Transport.
// Newline-delimited JSON-RPC 2.0 communication over stdin/stdout.
// Diagnostic logs are explicitly routed to stderr to keep stdout strictly protocol-compliant.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'acp_server.dart';
import '../gateway/protocol.dart';

/// Connects an ACP Server to standard I/O streams.
class AcpStdioTransport {
  AcpStdioTransport({
    required this.server,
    Stream<List<int>>? stdinStream,
    IOSink? stdoutSink,
    IOSink? stderrSink,
  })  : _stdinStream = stdinStream ?? stdin,
        _stdoutSink = stdoutSink ?? stdout,
        _stderrSink = stderrSink ?? stderr;

  final AcpServer server;
  final Stream<List<int>> _stdinStream;
  final IOSink _stdoutSink;
  final IOSink _stderrSink;

  StreamSubscription<String>? _sub;
  bool _running = false;
  final Completer<void> _doneCompleter = Completer<void>();

  bool get isRunning => _running;
  Future<void> get done => _doneCompleter.future;

  /// Start listening on stdin and responding on stdout.
  void start() {
    if (_running) return;
    _running = true;

    // Attach notification listener
    server.onNotification = (RpcRequest notification) {
      _sendOutput(notification.toJsonString());
    };

    _sub = _stdinStream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      _handleLine,
      onError: (Object error) {
        _logToStderr('STDIO Stream Error: $error');
      },
      onDone: () {
        _logToStderr('STDIO Stream closed (EOF)');
        stop();
      },
    );

    _logToStderr('Ghost ACP Server started on STDIO');
  }

  Future<void> _handleLine(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    try {
      final response = await server.handleRawMessage(trimmed);
      if (response != null) {
        _sendOutput(response);
      }
    } catch (e, st) {
      _logToStderr('Error handling ACP line: $e\n$st');
      final errorResponse = RpcErrorResponse(
        id: null,
        code: RpcErrorCodes.internalError,
        message: 'Internal ACP error: $e',
      );
      _sendOutput(errorResponse.toJsonString());
    }
  }

  void _sendOutput(String jsonLine) {
    try {
      _stdoutSink.writeln(jsonLine);
    } catch (e) {
      _logToStderr('Failed to write to stdout: $e');
    }
  }

  void _logToStderr(String message) {
    try {
      _stderrSink.writeln('[ACP] $message');
    } catch (_) {}
  }

  /// Stop the transport.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    _logToStderr('Ghost ACP Server stopped on STDIO');
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}
