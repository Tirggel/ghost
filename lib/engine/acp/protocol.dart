// Ghost — Agent Client Protocol (ACP) Protocol Specification.
// Compatible with Google Antigravity (AGY), Zed, and VS Code ACP integrations.

import '../gateway/protocol.dart';

/// Autopilot execution mode for agent actions.
enum AutopilotMode {
  /// Autonomous execution: tools, terminal commands, and file edits run automatically.
  autoAccept,

  /// Guarded Autopilot: sensitive actions require user confirmation or review before applying.
  reviewMode,
}

/// Standard ACP error codes.
class AcpErrorCodes {
  AcpErrorCodes._();

  static const int sessionNotFound = -32004;
  static const int reviewRejected = -32005;
  static const int contextError = -32006;
  static const int cancelled = -32007;
}

/// Client metadata provided during ACP handshake.
class AcpClientInfo {
  const AcpClientInfo({
    required this.name,
    this.version = '1.0.0',
  });

  factory AcpClientInfo.fromJson(Map<String, dynamic> json) {
    return AcpClientInfo(
      name: json['name'] as String? ?? 'unknown-client',
      version: json['version'] as String? ?? '1.0.0',
    );
  }

  final String name;
  final String version;

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
      };
}

/// Agent metadata returned by Ghost during initialization.
class AcpAgentInfo {
  const AcpAgentInfo({
    this.name = 'ghost',
    this.version = '0.1.0',
    this.description = 'Ghost Personal AI Assistant & Antigravity Coding Agent',
  });

  final String name;
  final String version;
  final String description;

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'description': description,
      };
}

/// Capabilities negotiated in ACP.
class AcpCapabilities {
  const AcpCapabilities({
    this.loadSession = true,
    this.streaming = true,
    this.tools = true,
    this.contextProviders = true,
    this.editReview = true,
    this.terminal = true,
  });

  factory AcpCapabilities.fromJson(Map<String, dynamic> json) {
    return AcpCapabilities(
      loadSession: json['loadSession'] as bool? ?? true,
      streaming: json['streaming'] as bool? ?? true,
      tools: json['tools'] as bool? ?? true,
      contextProviders: json['contextProviders'] as bool? ?? true,
      editReview: json['editReview'] as bool? ?? true,
      terminal: json['terminal'] as bool? ?? true,
    );
  }

  final bool loadSession;
  final bool streaming;
  final bool tools;
  final bool contextProviders;
  final bool editReview;
  final bool terminal;

  Map<String, dynamic> toJson() => {
        'loadSession': loadSession,
        'streaming': streaming,
        'tools': tools,
        'contextProviders': contextProviders,
        'editReview': editReview,
        'terminal': terminal,
      };
}

/// Session update event types emitted via `session/update`.
enum AcpUpdateType {
  textDelta,
  thoughtDelta,
  toolCall,
  toolResult,
  edit,
  terminal,
  plan,
  state,
  reviewRequest,
}

/// A structured update event sent to the ACP client.
class AcpSessionUpdate {
  const AcpSessionUpdate({
    required this.sessionId,
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? null;

  final String sessionId;
  final AcpUpdateType type;
  final Map<String, dynamic> data;
  final DateTime? timestamp;

  String get typeString {
    switch (type) {
      case AcpUpdateType.textDelta:
        return 'text_delta';
      case AcpUpdateType.thoughtDelta:
        return 'thought_delta';
      case AcpUpdateType.toolCall:
        return 'tool_call';
      case AcpUpdateType.toolResult:
        return 'tool_result';
      case AcpUpdateType.edit:
        return 'edit';
      case AcpUpdateType.terminal:
        return 'terminal';
      case AcpUpdateType.plan:
        return 'plan';
      case AcpUpdateType.state:
        return 'state';
      case AcpUpdateType.reviewRequest:
        return 'review_request';
    }
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'type': typeString,
        'data': data,
        'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      };

  RpcRequest toRpcNotification() {
    return RpcRequest(
      method: 'session/update',
      params: toJson(),
    );
  }
}

/// Review Request for Guarded Autopilot.
class AcpReviewRequest {
  const AcpReviewRequest({
    required this.reviewId,
    required this.sessionId,
    required this.actionType,
    required this.details,
  });

  final String reviewId;
  final String sessionId;
  /// e.g. "file_edit", "terminal_command", "sensitive_tool"
  final String actionType;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'sessionId': sessionId,
        'actionType': actionType,
        'details': details,
      };

  factory AcpReviewRequest.fromJson(Map<String, dynamic> json) {
    return AcpReviewRequest(
      reviewId: json['reviewId'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      actionType: json['actionType'] as String? ?? 'file_edit',
      details: (json['details'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// User's response to an ACP Review Request.
class AcpReviewResponse {
  const AcpReviewResponse({
    required this.reviewId,
    required this.approved,
    this.rejectionReason,
  });

  final String reviewId;
  final bool approved;
  final String? rejectionReason;

  factory AcpReviewResponse.fromJson(Map<String, dynamic> json) {
    return AcpReviewResponse(
      reviewId: json['reviewId'] as String? ?? '',
      approved: json['approved'] as bool? ?? false,
      rejectionReason: json['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'approved': approved,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      };
}

/// Context item returned by or provided to an ACP Context Provider.
class AcpContextItem {
  const AcpContextItem({
    required this.title,
    required this.content,
    this.source = 'workspace_rag',
    this.filePath,
    this.score,
  });

  final String title;
  final String content;
  final String source;
  final String? filePath;
  final double? score;

  factory AcpContextItem.fromJson(Map<String, dynamic> json) {
    return AcpContextItem(
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      source: json['source'] as String? ?? 'workspace_rag',
      filePath: json['filePath'] as String?,
      score: (json['score'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'source': source,
        if (filePath != null) 'filePath': filePath,
        if (score != null) 'score': score,
      };
}
