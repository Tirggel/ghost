import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticated,
  error,
}

class GatewayClient {
  GatewayClient({required this.url});

  final String url;
  WebSocketChannel? _channel;
  final _uuid = const Uuid();

  final _pendingRequests = <String, Completer<dynamic>>{};

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get status async* {
    yield _currentStatus;
    yield* _statusController.stream;
  }

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  ConnectionStatus get currentStatus => _currentStatus;

  void _setStatus(ConnectionStatus s) {
    _currentStatus = s;
    _statusController.add(s);
  }

  Future<void> connect() async {
    if (_currentStatus == ConnectionStatus.connecting ||
        _currentStatus == ConnectionStatus.connected ||
        _currentStatus == ConnectionStatus.authenticated) {
      return; // Already connected or connecting
    }

    _setStatus(ConnectionStatus.connecting);
    print('[Ghost.Gateway] Connecting to $url...');
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;
      _setStatus(ConnectionStatus.connected);
      print('[Ghost.Gateway] Connected to $url');

      _channel!.stream.listen(
        (data) => _handleIncoming(data as String),
        onDone: () {
          print('[Ghost.Gateway] Connection closed');
          _setStatus(ConnectionStatus.disconnected);
        },
        onError: (e) {
          print('[Ghost.Gateway] Connection error: $e');
          _setStatus(ConnectionStatus.error);
        },
      );
    } catch (e) {
      print('[Ghost.Gateway] Connect failed: $e');
      _setStatus(ConnectionStatus.error);
    }
  }

  Future<bool> login(String token) async {
    print('[Ghost.Gateway] Attempting login...');
    try {
      final response = await call('auth.login', {'token': token});
      if (response['authenticated'] == true) {
        print('[Ghost.Gateway] Login successful');
        _setStatus(ConnectionStatus.authenticated);
        return true;
      }
      print('[Ghost.Gateway] Login failed (invalid response)');
      return false;
    } catch (e) {
      print('[Ghost.Gateway] Login error: $e');
      return false;
    }
  }

  Future<dynamic> call(String method, [Map<String, dynamic>? params]) {
    final id = _uuid.v4();
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final json = jsonEncode(request);
    if (method != 'gateway.status') {
      print('[Ghost.Gateway] SEND: $json');
    }
    _channel?.sink.add(json);
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void _handleIncoming(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;

    // Special handling for logs to make them more readable in terminal
    if (data['method'] == 'gateway.log') {
      final params = data['params'] as Map<String, dynamic>;
      final level = params['level'] as String? ?? 'INFO';
      final message = params['message'] as String? ?? '';
      final logger = params['logger'] as String? ?? 'Ghost';
      print('[$logger] $level: $message');
      _messageController.add(data);
      return;
    }

    if (!raw.contains('"method":"gateway.status"') &&
        !raw.contains('"result":{"status":"running"')) {
      print('[Ghost.Gateway] RECV: $raw');
    }

    if (data.containsKey('id') && _pendingRequests.containsKey(data['id'])) {
      final id = data['id'] as String;
      final completer = _pendingRequests.remove(id);

      if (data.containsKey('error')) {
        completer?.completeError(data['error']);
      } else {
        completer?.complete(data['result']);
      }
    } else if (data.containsKey('method')) {
      // It's a notification/broadcast from server
      _messageController.add(data);
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
  }
}
