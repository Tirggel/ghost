// Ghost — JSON-RPC 2.0 based Gateway protocol.

import 'dart:convert';

import '../infra/errors.dart';

/// JSON-RPC 2.0 standard error codes.
class RpcErrorCodes {
  RpcErrorCodes._();

  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  // Custom error codes
  static const int authRequired = -32001;
  static const int authFailed = -32002;
  static const int configError = -32010;
  static const int sessionError = -32020;
  static const int channelError = -32030;
  static const int toolError = -32040;
}

/// A JSON-RPC 2.0 request.
class RpcRequest {
  const RpcRequest({required this.method, this.params, this.id});

  /// Parse a JSON-RPC request from a raw JSON string.
  factory RpcRequest.fromJsonString(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return RpcRequest.fromJson(json);
    } on FormatException {
      throw ProtocolError('Invalid JSON', rpcCode: RpcErrorCodes.parseError);
    }
  }

  /// Parse a JSON-RPC request from a decoded JSON map.
  factory RpcRequest.fromJson(Map<String, dynamic> json) {
    if (json['jsonrpc'] != '2.0') {
      throw ProtocolError(
        'Missing or invalid "jsonrpc" version (expected "2.0")',
        rpcCode: RpcErrorCodes.invalidRequest,
      );
    }

    final method = json['method'];
    if (method is! String || method.isEmpty) {
      throw ProtocolError(
        'Missing or invalid "method" field',
        rpcCode: RpcErrorCodes.invalidRequest,
      );
    }

    return RpcRequest(
      method: method,
      params: json['params'] as Map<String, dynamic>?,
      id: json['id'],
    );
  }

  final String method;
  final Map<String, dynamic>? params;

  /// Request ID. Null for notifications (no response expected).
  final Object? id;

  /// True if this is a notification (no response expected).
  bool get isNotification => id == null;

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'method': method,
        if (params != null) 'params': params,
        if (id != null) 'id': id,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// A JSON-RPC 2.0 success response.
class RpcResponse {
  const RpcResponse({required this.id, required this.result});

  final Object? id;
  final Object? result;

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'result': result,
        'id': id,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// A JSON-RPC 2.0 error response.
class RpcErrorResponse {
  const RpcErrorResponse({
    required this.id,
    required this.code,
    required this.message,
    this.data,
  });

  /// Create from a [ProtocolError].
  factory RpcErrorResponse.fromProtocolError(
    ProtocolError error, {
    Object? id,
  }) {
    return RpcErrorResponse(
      id: id,
      code: error.rpcCode ?? RpcErrorCodes.internalError,
      message: error.message,
    );
  }

  final Object? id;
  final int code;
  final String message;
  final Object? data;

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'error': {
          'code': code,
          'message': message,
          if (data != null) 'data': data
        },
        'id': id,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Type definition for RPC method handlers.
typedef RpcHandler = Future<Object?> Function(
    Map<String, dynamic>? params, RpcContext context);

/// Context passed to RPC handlers.
class RpcContext {
  const RpcContext({this.clientId, this.isAuthenticated = false});

  final String? clientId;
  final bool isAuthenticated;
}

/// Registry of RPC methods.
class RpcRegistry {
  final Map<String, RpcHandler> _handlers = {};

  /// Register an RPC method handler.
  void register(String method, RpcHandler handler) {
    _handlers[method] = handler;
  }

  /// Unregister an RPC method.
  void unregister(String method) {
    _handlers.remove(method);
  }

  /// Check if a method is registered.
  bool hasMethod(String method) => _handlers.containsKey(method);

  /// Get all registered method names.
  Set<String> get methods => _handlers.keys.toSet();

  /// Handle an RPC request and return the response as a JSON string.
  /// Returns null for notifications.
  Future<String?> handleRequest(String raw, RpcContext context) async {
    RpcRequest request;

    try {
      request = RpcRequest.fromJsonString(raw);
    } on ProtocolError catch (e) {
      return RpcErrorResponse(
        id: null,
        code: e.rpcCode ?? RpcErrorCodes.parseError,
        message: e.message,
      ).toJsonString();
    }

    // Notifications don't get responses
    if (request.isNotification) {
      await _executeHandler(request, context);
      return null;
    }

    try {
      final result = await _executeHandler(request, context);
      return RpcResponse(id: request.id, result: result).toJsonString();
    } on ProtocolError catch (e) {
      return RpcErrorResponse.fromProtocolError(
        e,
        id: request.id,
      ).toJsonString();
    } catch (e) {
      return RpcErrorResponse(
        id: request.id,
        code: RpcErrorCodes.internalError,
        message: 'Internal error: $e',
      ).toJsonString();
    }
  }

  Future<Object?> _executeHandler(
    RpcRequest request,
    RpcContext context,
  ) async {
    final handler = _handlers[request.method];
    if (handler == null) {
      throw ProtocolError(
        'Method not found: ${request.method}',
        rpcCode: RpcErrorCodes.methodNotFound,
      );
    }
    return handler(request.params, context);
  }
}
