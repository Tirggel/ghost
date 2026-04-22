// Ghost — Gateway authentication module.

import 'package:logging/logging.dart';

import '../config/config.dart';
import '../infra/crypto.dart';
import '../infra/errors.dart';

final _log = Logger('Ghost.Auth');

/// Handles Gateway authentication for WebSocket connections.
class GatewayAuth {
  GatewayAuth({required this.config});

  AuthConfig config;

  /// Update the auth config (e.g. after hot-reload).
  void updateConfig(AuthConfig newConfig) {
    config = newConfig;
  }

  /// Authenticate a client.
  ///
  /// Returns `true` if the client is authenticated.
  /// Throws [AuthError] if authentication fails.
  bool authenticate({String? token, String? password}) {
    switch (config.mode) {
      case AuthMode.none:
        _log.fine('Auth mode: none — allowing all connections');
        return true;

      case AuthMode.token:
        return _authenticateToken(token);

      case AuthMode.password:
        return _authenticatePassword(password);
    }
  }

  /// Hash a raw token for storage in config.
  static String hashToken(String rawToken) => sha256Hash(rawToken);

  /// Hash a raw password for storage in config.
  static String hashPassword(String rawPassword) => sha256Hash(rawPassword);

  /// Generate a new random auth token and return both raw and hash.
  static ({String raw, String hash}) generateAuthToken() {
    final raw = generateToken(byteLength: 32);
    final hash = hashToken(raw);
    return (raw: raw, hash: hash);
  }

  bool _authenticateToken(String? token) {
    if (token == null || token.isEmpty) {
      throw AuthError(
        'Authentication required — provide a token',
        code: 'AUTH_REQUIRED',
      );
    }

    final tokenHash = config.tokenHash;
    if (tokenHash == null) {
      // No token configured — generate guidance
      throw AuthError(
        'No auth token configured. Run: ghost config set-token',
        code: 'NO_TOKEN_CONFIGURED',
      );
    }

    final providedHash = sha256Hash(token.toLowerCase());
    if (!secureCompare(providedHash, tokenHash.toLowerCase())) {
      _log.warning('Authentication failed — invalid token. '
          'If you just updated the token via CLI, ensure the gateway was restarted or reloaded.');
      throw AuthError('Invalid authentication token', code: 'INVALID_TOKEN');
    }

    _log.fine('Token authentication successful');
    return true;
  }

  bool _authenticatePassword(String? password) {
    if (password == null || password.isEmpty) {
      throw AuthError(
        'Authentication required — provide a password',
        code: 'AUTH_REQUIRED',
      );
    }

    final passwordHash = config.passwordHash;
    if (passwordHash == null) {
      throw AuthError(
        'No password configured for gateway auth',
        code: 'NO_PASSWORD_CONFIGURED',
      );
    }

    final providedHash = sha256Hash(password);
    if (!secureCompare(providedHash, passwordHash)) {
      _log.warning('Authentication failed — invalid password');
      throw AuthError('Invalid password', code: 'INVALID_PASSWORD');
    }

    _log.fine('Password authentication successful');
    return true;
  }
}
