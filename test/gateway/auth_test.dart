import 'package:test/test.dart';
import 'package:ghost/engine/gateway/auth.dart';
import 'package:ghost/engine/config/config.dart';
import 'package:ghost/engine/infra/errors.dart';

void main() {
  group('GatewayAuth', () {
    test('Token authentication works', () {
      const token = 'secret-token';
      final hash = GatewayAuth.hashToken(token);
      final auth = GatewayAuth(
          config: AuthConfig(mode: AuthMode.token, tokenHash: hash));

      expect(auth.authenticate(token: token), isTrue);
      expect(() => auth.authenticate(token: 'wrong-token'),
          throwsA(isA<AuthError>()));
    });

    test('Password authentication works', () {
      const password = 'strong-password';
      final hash = GatewayAuth.hashPassword(password);
      final auth = GatewayAuth(
          config: AuthConfig(mode: AuthMode.password, passwordHash: hash));

      expect(auth.authenticate(password: password), isTrue);
      expect(() => auth.authenticate(password: 'wrong-pass'),
          throwsA(isA<AuthError>()));
    });

    test('None mode allows everything', () {
      final auth = GatewayAuth(config: const AuthConfig(mode: AuthMode.none));
      expect(auth.authenticate(), isTrue);
    });

    test('Token generation', () {
      final result = GatewayAuth.generateAuthToken();
      expect(result.raw.isNotEmpty, isTrue);
      expect(result.hash.length, equals(64));
    });
  });
}
