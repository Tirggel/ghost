import 'package:test/test.dart';
import 'package:ghost/config/config.dart';

void main() {
  group('Config Parsing', () {
    test('Default config has expected values', () {
      const config = GhostConfig();
      expect(config.gateway.port, equals(3000));
      expect(config.gateway.bind, equals(BindMode.loopback));
      expect(config.agent.model, isEmpty);
      expect(config.memory.enabled, isTrue);
    });

    test('JSON round-trip preserves values', () {
      const config = GhostConfig(
        gateway: GatewayConfig(port: 9999, verbose: true),
        agent: AgentConfig(model: 'custom-model'),
      );

      final json = config.toJson();
      final restored = GhostConfig.fromJson(json);

      expect(restored.gateway.port, equals(9999));
      expect(restored.gateway.verbose, isTrue);
      expect(restored.agent.model, equals('custom-model'));
    });

    test('copyWith creates new instance with updated values', () {
      const config = GhostConfig();
      final updated = config.copyWith(
        gateway: config.gateway.copyWith(port: 1234),
      );

      expect(config.gateway.port, equals(3000));
      expect(updated.gateway.port, equals(1234));
      expect(updated.agent.model, equals(config.agent.model));
    });
  });

  group('Gateway Config', () {
    test('bindAddress reflects bind mode', () {
      expect(const GatewayConfig(bind: BindMode.loopback).bindAddress,
          equals('127.0.0.1'));
      expect(const GatewayConfig(bind: BindMode.all).bindAddress,
          equals('0.0.0.0'));
    });
  });
}
