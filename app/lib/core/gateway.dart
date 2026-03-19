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
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;
      _setStatus(ConnectionStatus.connected);

      _channel!.stream.listen(
        (data) => _handleIncoming(data as String),
        onDone: () => _setStatus(ConnectionStatus.disconnected),
        onError: (e) => _setStatus(ConnectionStatus.error),
      );
    } catch (e) {
      _setStatus(ConnectionStatus.error);
    }
  }

  Future<bool> login(String token) async {
    try {
      final response = await call('auth.login', {'token': token});
      if (response['authenticated'] == true) {
        _setStatus(ConnectionStatus.authenticated);
        return true;
      }
      return false;
    } catch (e) {
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

    _channel?.sink.add(jsonEncode(request));
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void _handleIncoming(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;

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
