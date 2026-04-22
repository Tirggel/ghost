import 'package:test/test.dart';
import 'package:ghost/engine/config/config.dart';
import 'package:ghost/engine/config/schema.dart';
import 'package:ghost/engine/infra/errors.dart';

void main() {
  group('Config Validation', () {
    test('Default config is valid', () {
      const config = GhostConfig();
      final errors = validateConfig(config);
      expect(errors, isEmpty);
    });

    test('Invalid port is rejected', () {
      const config = GhostConfig(
        gateway: GatewayConfig(port: 70000),
      );
      final errors = validateConfig(config);
      expect(errors, contains(predicate((String s) => s.contains('port'))));
    });

    test('Password hash required for password auth mode', () {
      const config = GhostConfig(
        gateway: GatewayConfig(
          auth: AuthConfig(mode: AuthMode.password, passwordHash: null),
        ),
      );
      final errors = validateConfig(config);
      expect(
          errors,
          contains(
              predicate((String s) => s.contains('passwordHash is required'))));
    });

    test('Memory weights must sum to 1.0', () {
      const config = GhostConfig(
        memory: MemoryConfig(vectorWeight: 0.5, bm25Weight: 0.2),
      );
      final errors = validateConfig(config);
      expect(errors,
          contains(predicate((String s) => s.contains('must equal 1.0'))));
    });

    test('assertConfigValid throws on error', () {
      const config = GhostConfig(
        gateway: GatewayConfig(port: 0),
      );
      expect(() => assertConfigValid(config), throwsA(isA<ConfigError>()));
    });
  });
}
