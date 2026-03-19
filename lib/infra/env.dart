// Ghost — Environment variable access with fallback chains.

import 'dart:io';

/// Provides access to environment variables with defaults and config
/// fallback chains: Config → Env Variable → Default.
class Env {
  Env._();

  /// Environment variable prefix for Ghost.
  static const String prefix = 'FLUTTERGHOST_';

  /// Get an environment variable with optional default.
  static String? get(String key, {String? defaultValue}) {
    return Platform.environment[key] ?? defaultValue;
  }

  /// Get a prefixed Ghost environment variable.
  static String? getGhost(String key, {String? defaultValue}) {
    return get('$prefix$key', defaultValue: defaultValue);
  }

  /// Check if an environment variable is set.
  static bool has(String key) {
    return Platform.environment.containsKey(key);
  }

  // --- Well-known environment variables ---

  /// Anthropic API key.
  static String? get anthropicKey =>
      getGhost('ANTHROPIC_KEY') ?? get('ANTHROPIC_API_KEY');

  /// OpenAI API key.
  static String? get openaiKey =>
      getGhost('OPENAI_KEY') ?? get('OPENAI_API_KEY');

  /// State directory override.
  static String? get stateDir => getGhost('STATE_DIR');

  /// Workspace directory override.
  static String? get workspaceDir => getGhost('WORKSPACE_DIR');

  /// Gateway port override.
  static int? get gatewayPort {
    final raw = getGhost('GATEWAY_PORT');
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// Gateway auth token override.
  static String? get authToken => getGhost('AUTH_TOKEN');

  /// Home directory.
  static String get homeDir {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
  }

  /// Default Ghost state directory.
  static String get defaultStateDir {
    return stateDir ?? '$homeDir/.ghost';
  }

  /// Default workspace directory.
  static String get defaultWorkspaceDir {
    return workspaceDir ?? '$defaultStateDir/workspace';
  }
}
