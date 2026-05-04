// Ghost — WebSocket Gateway server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hive_ce/hive.dart';
import 'dart:typed_data';

import '../config/config.dart';
import '../config/secure_storage.dart';
import '../infra/errors.dart';
import 'auth.dart';
import 'protocol.dart';

final _log = Logger('Ghost.Gateway');

const _uuid = Uuid();

/// Represents a connected WebSocket client.
class GatewayClient {
  GatewayClient({
    required this.id,
    required this.channel,
    this.isAuthenticated = false,
  });

  final String id;
  final WebSocketChannel channel;
  bool isAuthenticated;
}

/// The Ghost Gateway WebSocket server.
///
/// Central control plane that handles:
/// - WebSocket connections with authentication
/// - JSON-RPC 2.0 method dispatch
/// - Client management
class GatewayServer {
  GatewayServer({
    required this.config,
    this.stateDir,
    this.storage,
    RpcRegistry? rpcRegistry,
    this.onRestart,
  }) : rpcRegistry = rpcRegistry ?? RpcRegistry() {
    _auth = GatewayAuth(config: config.auth);
    _registerBuiltinMethods();
  }

  GatewayConfig config;
  final String? stateDir;
  final SecureStorage? storage;
  final RpcRegistry rpcRegistry;
  final Future<void> Function()? onRestart;
  late GatewayAuth _auth;

  HttpServer? _server;
  final Map<String, GatewayClient> _clients = {};
  DateTime? _startedAt;

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// The actual port the server is listening on.
  int get port => _server?.port ?? config.port;

  /// Number of connected clients.
  int get clientCount => _clients.length;

  StreamSubscription<LogRecord>? _logSub;

  /// Start the Gateway server.
  ///
  /// If [isRestart] is true, it will strictly try to bind to the configured port
  /// and retry if it's currently busy (e.g. still closing from previous instance).
  Future<void> start({bool isRestart = false}) async {
    if (isRunning) {
      throw GhostError('Gateway is already running');
    }

    await Hive.openBox<Uint8List>('avatars');

    final handler = webSocketHandler(_handleWebSocket);

    // Subscribe to all system logs and broadcast them to authenticated clients
    _logSub = Logger.root.onRecord.listen((record) {
      // Prevent infinite loops: don't broadcast logs about broadcasting logs
      // or other high-frequency internal gateway noise if needed.
      final msg = record.message;
      if (record.loggerName == 'Ghost.Gateway' &&
          (msg.contains('JSON-RPC') ||
              msg.contains('RPC Request') ||
              msg.contains('RPC Response'))) {
        return;
      }

      broadcast('gateway.log', {
        'level': record.level.name,
        'message': record.message,
        'time': record.time.toIso8601String(),
        'logger': record.loggerName,
      });
    });

    // Add a health check endpoint for HTTP
    final cascade =
        const shelf.Pipeline().addMiddleware(_logMiddleware()).addHandler(
      (request) {
        // CORS headers for browser access
        final corsHeaders = {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        };

        // Handle CORS preflight
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: corsHeaders);
        }

        if (request.url.path == 'health') {
          return shelf.Response.ok(
            '{"status":"ok"}',
            headers: {...corsHeaders, 'content-type': 'application/json'},
          );
        }
        if (request.url.path == 'status') {
          return shelf.Response.ok(
            _getStatusJson(),
            headers: {...corsHeaders, 'content-type': 'application/json'},
          );
        }

        // Client token persistence endpoint
        if (request.url.path == 'client-token') {
          return _handleClientToken(request, corsHeaders);
        }

        // File server endpoint (for avatars on web)
        if (request.url.path == 'file') {
          return _handleFileRequest(request, corsHeaders);
        }

        // File upload endpoint (for avatars on web)
        if (request.url.path == 'upload') {
          return _handleUpload(request, corsHeaders);
        }

        // Default: upgrade to WebSocket
        return handler(request);
      },
    );

    const maxPortAttempts = 100;
    int chosenPort = config.port;

    if (isRestart) {
      // For restarts, we MUST stay on the same port, otherwise client loses us.
      // We try for up to 5 seconds.
      for (int i = 0; i < 20; i++) {
        try {
          _server = await shelf_io.serve(cascade, config.bindAddress, config.port);
          chosenPort = config.port;
          break;
        } on SocketException catch (e) {
          if (e.osError?.errorCode == 98 /* EADDRINUSE */ && i < 19) {
            _log.warning('Port ${config.port} still busy during restart, retrying in 250ms...');
            await Future<void>.delayed(const Duration(milliseconds: 250));
            continue;
          }
          rethrow;
        }
      }
    } else {
      for (int attempt = 0; attempt < maxPortAttempts; attempt++) {
        final tryPort = config.port + attempt;
        try {
          _server = await shelf_io.serve(cascade, config.bindAddress, tryPort);
          chosenPort = tryPort;
          break;
        } on SocketException catch (e) {
          if (e.osError?.errorCode == 98 /* EADDRINUSE */ && attempt < maxPortAttempts - 1) {
            _log.warning('Port $tryPort already in use, trying ${tryPort + 1}...');
            continue;
          }
          rethrow;
        }
      }
    }

    _startedAt = DateTime.now();
    if (chosenPort != config.port) {
      _log.warning('⚠️  Port ${config.port} was busy — gateway started on port $chosenPort instead.');
    }
    _log.info('Gateway started on ws://${config.bindAddress}:$chosenPort');
  }

  /// Handle POST /upload?name=... for saving images from the browser.
  Future<shelf.Response> _handleUpload(
    shelf.Request request,
    Map<String, String> corsHeaders,
  ) async {
    if (request.method != 'POST') {
      return shelf.Response(405, headers: corsHeaders);
    }

    final key = request.url.queryParameters['name'] ??
        'upload_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final bytes = await request.read().toList();
      final flatBytes = Uint8List.fromList(bytes.expand((x) => x).toList());

      final avatarsBox = Hive.box<Uint8List>('avatars');
      await avatarsBox.put(key, flatBytes);

      _log.info('Avatar uploaded and saved to box avatars with key: $key');
      return shelf.Response.ok(
        jsonEncode({'path': key}),
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    } catch (e) {
      _log.warning('Upload failed: $e');
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    }
  }

  /// Handle GET /file?path=... for serving local images to the browser.
  Future<shelf.Response> _handleFileRequest(
    shelf.Request request,
    Map<String, String> corsHeaders,
  ) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.isEmpty) {
      _log.warning('File request missing path parameter');
      return shelf.Response.notFound(
        '{"error":"missing path"}',
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    }

    // Determine content type heuristically or default to png
    String contentType = 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      contentType = 'image/jpeg';
    } else if (path.endsWith('.gif')) {
      contentType = 'image/gif';
    } else if (path.endsWith('.webp')) {
      contentType = 'image/webp';
    }

    final avatarsBox = Hive.box<Uint8List>('avatars');
    final bytes = avatarsBox.get(path);

    if (bytes == null) {
      _log.warning('Avatar key not found in Hive: $path');
      return shelf.Response.notFound(
        '{"error":"file not found"}',
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    }

    _log.info('Serving avatar from Hive box: $path ($contentType)');
    return shelf.Response.ok(
      bytes,
      headers: {
        ...corsHeaders,
        'Content-Type': contentType,
      },
    );
  }

  /// Stop the Gateway server.
  Future<void> stop() async {
    if (!isRunning) return;

    await _logSub?.cancel();
    _logSub = null;

    // Close all client connections
    // Note: Use a copy of values to avoid ConcurrentModificationError
    final clients = List<GatewayClient>.from(_clients.values);
    for (final client in clients) {
      try {
        await client.channel.sink.close();
      } catch (e) {
        _log.warning('Error closing client ${client.id}: $e');
      }
    }
    _clients.clear();

    await _server?.close(force: true);
    _server = null;
    _startedAt = null;

    try {
      if (Hive.isBoxOpen('avatars')) {
        await Hive.box<Uint8List>('avatars').close();
      }
    } catch (e) {
      _log.warning('Error closing avatars box: $e');
    }

    _log.info('Gateway stopped');
  }

  /// Update configuration (e.g. after hot-reload).
  void updateConfig(GatewayConfig newConfig) {
    config = newConfig;
    _auth.updateConfig(newConfig.auth);
    _log.info('Gateway config updated');
  }

  /// Broadcast a notification to all authenticated clients.
  void broadcast(String method, [Map<String, dynamic>? params]) {
    final request = RpcRequest(method: method, params: params);
    final json = request.toJsonString();

    for (final client in _clients.values) {
      if (client.isAuthenticated) {
        _send(client, json);
      }
    }
  }

  /// Safely send a message to a client, handling disconnections gracefully.
  void _send(GatewayClient client, String message) {
    if (!_clients.containsKey(client.id)) return;
    try {
      client.channel.sink.add(message);
    } catch (e) {
      _log.warning('Failed to send to client ${client.id} (likely disconnected): $e');
    }
  }

  void _handleWebSocket(WebSocketChannel webSocket) {
    final clientId = _uuid.v4();
    final client = GatewayClient(
      id: clientId,
      channel: webSocket,
      isAuthenticated: config.auth.mode == AuthMode.none,
    );

    _clients[clientId] = client;
    _log.info('Client connected: $clientId');

    webSocket.stream.listen(
      (data) => _handleMessage(client, data as String),
      onDone: () {
        _clients.remove(clientId);
        _log.info('Client disconnected: $clientId');
      },
      onError: (Object error) {
        _log.warning('Client $clientId error: $error');
        _clients.remove(clientId);
      },
    );
  }

  Future<void> _handleMessage(GatewayClient client, String raw) async {
    // If not authenticated, only allow auth methods
    if (!client.isAuthenticated) {
      try {
        final request = RpcRequest.fromJsonString(raw);
        if (request.method != 'auth.login' &&
            request.method != 'config.factoryReset') {
          final error = RpcErrorResponse(
            id: request.id,
            code: RpcErrorCodes.authRequired,
            message: 'Authentication required. Call auth.login first.',
          );
          _send(client, error.toJsonString());
          return;
        }
      } on ProtocolError catch (e) {
        final error = RpcErrorResponse(
          id: null,
          code: e.rpcCode ?? RpcErrorCodes.parseError,
          message: e.message,
        );
        _send(client, error.toJsonString());
        return;
      }
    }

    final context = RpcContext(
      clientId: client.id,
      isAuthenticated: client.isAuthenticated,
    );

    final isListModels = raw.contains('"method":"config.listModels"') ||
        raw.contains('"method":"config.listModelsDetailed"');

    if (!isListModels) {
      _log.info('RPC Request from ${client.id}: $raw');
    }

    final response = await rpcRegistry.handleRequest(raw, context);
    if (response != null) {
      if (!isListModels && !response.contains('"models":[')) {
        _log.info('RPC Response to ${client.id}: $response');
      }
      _send(client, response);
    }
  }

  void _registerBuiltinMethods() {
    // Auth
    rpcRegistry.register('auth.login', (params, context) async {
      final client = _clients[context.clientId];
      if (client == null) {
        throw ProtocolError(
          'Unknown client',
          rpcCode: RpcErrorCodes.internalError,
        );
      }

      try {
        _auth.authenticate(
          token: params?['token'] as String?,
          password: params?['password'] as String?,
        );
        client.isAuthenticated = true;
        return {'authenticated': true};
      } on AuthError catch (e) {
        throw ProtocolError(e.message, rpcCode: RpcErrorCodes.authFailed);
      }
    });

    // Health check
    rpcRegistry.register('gateway.health', (params, context) async {
      return {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()};
    });

    // Status
    rpcRegistry.register('gateway.status', (params, context) async {
      return {
        'status': 'running',
        'port': port,
        'bind': config.bindAddress,
        'clients': _clients.length,
        'authMode': config.auth.mode.name,
        'startedAt': _startedAt?.toIso8601String(),
        'uptime': _startedAt != null
            ? DateTime.now().difference(_startedAt!).inSeconds
            : 0,
      };
    });

    // List registered RPC methods
    rpcRegistry.register('gateway.methods', (params, context) async {
      return {'methods': rpcRegistry.methods.toList()..sort()};
    });

    // Restart the HTTP/WS server (keeps the same config/port)
    rpcRegistry.register('gateway.restart', (params, context) async {
      _log.info('Restart requested via RPC');
      broadcast('gateway.log', {
        'level': 'INFO',
        'message': '↺ Gateway restart requested — reconnecting in ~1 s…',
        'time': DateTime.now().toIso8601String(),
      });

      // Perform restart in background so the RPC response can still be sent
      unawaited(Future<void>.delayed(const Duration(milliseconds: 500)).then((_) async {
        if (onRestart != null) {
          _log.info('Performing full system restart via callback...');
          await onRestart!();
        } else {
          _log.info('Performing network-only restart...');
          await stop();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await start(isRestart: true);
        }
        _log.info('Gateway restarted on port $port');
        broadcast('gateway.log', {
          'level': 'INFO',
          'message': '✅ Gateway restarted on port $port',
          'time': DateTime.now().toIso8601String(),
        });
      }));

      return {'status': 'restarting', 'port': port};
    });
  }

  String _getStatusJson() {
    return '{'
        '"status":"running",'
        '"port":$port,'
        '"clients":${_clients.length},'
        '"startedAt":"${_startedAt?.toIso8601String()}"'
        '}';
  }

  /// Handle GET/POST/DELETE /client-token for browser token persistence.
  Future<shelf.Response> _handleClientToken(
    shelf.Request request,
    Map<String, String> corsHeaders,
  ) async {
    final dir = stateDir;
    if (dir == null) {
      return shelf.Response.internalServerError(
        body: '{"error":"no state dir"}',
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    }

    final tokenFile = File('$dir/client_token');

    // Migration logic: if plaintext file exists and we have storage, move it to storage
    if (storage != null && await tokenFile.exists()) {
      try {
        final oldToken = await tokenFile.readAsString();
        if (oldToken.trim().isNotEmpty) {
          await storage!.set('client_token', oldToken.trim());
          _log.info('Migrated plaintext client_token to secure storage');
        }
        await tokenFile.delete();
      } catch (e) {
        _log.warning('Failed to migrate/delete old client_token file: $e');
      }
    }

    if (request.method == 'GET') {
      String? token;
      if (storage != null) {
        token = await storage!.get('client_token');
      } else if (await tokenFile.exists()) {
        token = await tokenFile.readAsString();
      }

      return shelf.Response.ok(
        jsonEncode({'token': token?.trim()}),
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    }

    if (request.method == 'POST') {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final token = data['token'] as String?;

        if (token == null || token.isEmpty) {
          return shelf.Response(
            400,
            body: '{"error":"missing token"}',
            headers: {...corsHeaders, 'content-type': 'application/json'},
          );
        }

        if (storage != null) {
          await storage!.set('client_token', token);
        } else {
          await tokenFile.writeAsString(token);
        }
        return shelf.Response.ok(
          '{"status":"saved"}',
          headers: {...corsHeaders, 'content-type': 'application/json'},
        );
      } catch (e) {
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {...corsHeaders, 'content-type': 'application/json'},
        );
      }
    }

    if (request.method == 'DELETE') {
      if (storage != null) {
        await storage!.set('client_token', '');
        await storage!.remove('client_token');
      } else if (await tokenFile.exists()) {
        await tokenFile.delete();
      }
      return shelf.Response.ok(
        '{"status":"deleted"}',
        headers: {...corsHeaders, 'content-type': 'application/json'},
      );
    }

    return shelf.Response(
      405,
      headers: corsHeaders,
    );
  }

  shelf.Middleware _logMiddleware() {
    return (innerHandler) {
      return (request) async {
        final response = await innerHandler(request);
        _log.info(
          '${request.method} ${request.url.path}${request.url.query.isNotEmpty ? "?${request.url.query}" : ""} -> ${response.statusCode}',
        );
        return response;
      };
    };
  }
}
