// Ghost — Custom error types.

/// Base error class for all Ghost errors.
class GhostError implements Exception {
  GhostError(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('GhostError');
    if (code != null) buffer.write(' [$code]');
    buffer.write(': $message');
    if (cause != null) buffer.write(' (caused by: $cause)');
    return buffer.toString();
  }
}

/// Configuration-related errors.
class ConfigError extends GhostError {
  ConfigError(super.message, {super.code, super.cause});

  @override
  String toString() => 'ConfigError: $message';
}

/// AI Provider errors.
class ProviderError extends GhostError {
  ProviderError(super.message,
      {required this.provider, super.code, super.cause});

  final String provider;

  @override
  String toString() => 'ProviderError [$provider]: $message';
}

/// Authentication errors.
class AuthError extends GhostError {
  AuthError(super.message, {super.code, super.cause});

  @override
  String toString() => 'AuthError: $message';
}

/// Channel-related errors.
class ChannelError extends GhostError {
  ChannelError(super.message, {this.channelType, super.code, super.cause});

  final String? channelType;

  @override
  String toString() {
    final prefix =
        channelType != null ? 'ChannelError [$channelType]' : 'ChannelError';
    return '$prefix: $message';
  }
}

/// Gateway protocol errors.
class ProtocolError extends GhostError {
  ProtocolError(super.message, {this.rpcCode, super.code, super.cause});

  final int? rpcCode;

  @override
  String toString() => 'ProtocolError: $message';
}

/// Session-related errors.
class SessionError extends GhostError {
  SessionError(super.message, {super.code, super.cause});

  @override
  String toString() => 'SessionError: $message';
}

/// Tool execution errors.
class ToolError extends GhostError {
  ToolError(super.message, {this.toolName, super.code, super.cause});

  final String? toolName;

  @override
  String toString() {
    final prefix = toolName != null ? 'ToolError [$toolName]' : 'ToolError';
    return '$prefix: $message';
  }
}
