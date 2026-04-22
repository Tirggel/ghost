import 'package:test/test.dart';
import 'package:ghost/engine/gateway/protocol.dart';
import 'package:ghost/engine/infra/errors.dart';

void main() {
  group('RpcRequest', () {
    test('Valid request parsing', () {
      const raw =
          '{"jsonrpc": "2.0", "method": "test.echo", "params": {"msg": "hi"}, "id": 1}';
      final request = RpcRequest.fromJsonString(raw);

      expect(request.method, equals('test.echo'));
      expect(request.params?['msg'], equals('hi'));
      expect(request.id, equals(1));
      expect(request.isNotification, isFalse);
    });

    test('Notification parsing (no id)', () {
      const raw = '{"jsonrpc": "2.0", "method": "notify.event"}';
      final request = RpcRequest.fromJsonString(raw);
      expect(request.isNotification, isTrue);
    });

    test('Invalid request throws ProtocolError', () {
      expect(() => RpcRequest.fromJsonString('{"invalid": "json"}'),
          throwsA(isA<ProtocolError>()));
    });
  });

  group('RpcRegistry', () {
    test('Method registration and execution', () async {
      final registry = RpcRegistry();
      registry.register('math.add', (params, context) async {
        final a = params?['a'] as int;
        final b = params?['b'] as int;
        return a + b;
      });

      const raw =
          '{"jsonrpc": "2.0", "method": "math.add", "params": {"a": 2, "b": 3}, "id": 1}';
      final responseStr = await registry.handleRequest(raw, const RpcContext());

      expect(responseStr, contains('"id":1'));
      expect(responseStr, contains('"result":5'));
    });

    test('Handling method not found', () async {
      final registry = RpcRegistry();
      const raw = '{"jsonrpc": "2.0", "method": "unknown", "id": 1}';
      final responseStr = await registry.handleRequest(raw, const RpcContext());

      expect(responseStr, contains('"error"'));
      expect(responseStr, contains('"code":-32601')); // Method not found
    });
  });
}
