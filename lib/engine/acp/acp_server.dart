// Ghost — ACP (Agent Client Protocol) Server Implementation.
// Coordinates ACP requests, sessions, streaming deltas, and review-gated execution.

import 'dart:async';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../agent/manager.dart';
import '../gateway/protocol.dart';
import '../infra/errors.dart';
import '../tasks/task_manager.dart';
import 'acp_context_provider.dart';
import 'protocol.dart';

final _log = Logger('Ghost.AcpServer');
const _uuid = Uuid();

/// State tracked for each ACP session.
class AcpSession {
  AcpSession({
    required this.sessionId,
    required this.workspaceRoot,
    this.autopilotMode = AutopilotMode.reviewMode,
  });

  final String sessionId;
  String workspaceRoot;
  AutopilotMode autopilotMode;
  final Map<String, Completer<bool>> pendingReviews = {};
}

/// Core ACP server implementation.
class AcpServer {
  AcpServer({
    required this.agentManager,
    this.taskManager,
    this.contextProvider,
    this.defaultAutopilotMode = AutopilotMode.reviewMode,
    this.onNotification,
  }) {
    _registerMethods();
  }

  final AgentManager agentManager;
  final TaskManager? taskManager;
  final AcpContextProvider? contextProvider;
  final AutopilotMode defaultAutopilotMode;

  /// Callback to send JSON-RPC notifications to the connected client.
  void Function(RpcRequest notification)? onNotification;

  final Map<String, AcpSession> _sessions = {};
  final RpcRegistry rpcRegistry = RpcRegistry();
  AcpClientInfo? _clientInfo;

  AcpClientInfo? get clientInfo => _clientInfo;
  List<String> get activeSessionIds => _sessions.keys.toList();

  AcpSession? getSession(String sessionId) => _sessions[sessionId];

  /// Register all standard ACP methods.
  void _registerMethods() {
    // 1. initialize
    rpcRegistry.register('initialize', (params, context) async {
      final clientJson = params?['clientInfo'] as Map<String, dynamic>?;
      if (clientJson != null) {
        _clientInfo = AcpClientInfo.fromJson(clientJson);
        _log.info('ACP Client connected: ${_clientInfo!.name} v${_clientInfo!.version}');
      }

      return {
        'protocolVersion': 1,
        'agentInfo': const AcpAgentInfo().toJson(),
        'capabilities': const AcpCapabilities().toJson(),
      };
    });

    // 2. authenticate
    rpcRegistry.register('authenticate', (params, context) async {
      return {'authenticated': true};
    });

    // 3. session/new
    rpcRegistry.register('session/new', (params, context) async {
      final workspaceRoot = params?['workspaceRoot'] as String? ?? '.';
      final modeStr = params?['autopilotMode'] as String?;
      final requestedId = params?['sessionId'] as String? ?? 'acp_${_uuid.v4()}';

      final mode = modeStr == 'autoAccept'
          ? AutopilotMode.autoAccept
          : defaultAutopilotMode;

      // Create engine session
      if (agentManager.sessionManager.getSession(requestedId) == null) {
        agentManager.sessionManager.createSession(
          id: requestedId,
          channelType: 'acp',
          peerId: _clientInfo?.name ?? 'acp-client',
        );
      }

      final session = AcpSession(
        sessionId: requestedId,
        workspaceRoot: workspaceRoot,
        autopilotMode: mode,
      );
      _sessions[requestedId] = session;

      // Trigger workspace RAG indexing in the background if contextProvider is attached
      if (contextProvider != null && workspaceRoot != '.') {
        unawaited(contextProvider!.syncWorkspace(workspaceRoot));
      }

      _log.info('New ACP session created: $requestedId (Workspace: $workspaceRoot, Mode: ${mode.name})');
      return {
        'sessionId': requestedId,
        'autopilotMode': mode.name,
      };
    });

    // 4. session/load
    rpcRegistry.register('session/load', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }

      final history = await agentManager.sessionManager.getHistory(sessionId);
      final session = _sessions[sessionId];

      return {
        'sessionId': sessionId,
        'workspaceRoot': session?.workspaceRoot ?? '.',
        'autopilotMode': session?.autopilotMode.name ?? defaultAutopilotMode.name,
        'messages': history.map((m) => m.toJson()).toList(),
      };
    });

    // 5. session/prompt
    rpcRegistry.register('session/prompt', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      final promptText = params?['prompt'] as String?;
      final agentId = params?['agentId'] as String?;

      if (sessionId == null || promptText == null) {
        throw ProtocolError('Missing required parameters: sessionId and prompt');
      }

      final session = _sessions[sessionId];
      if (session == null) {
        throw ProtocolError('Session not found: $sessionId', rpcCode: AcpErrorCodes.sessionNotFound);
      }

      // Start processing in background and stream updates
      unawaited(_executePrompt(session, promptText, agentId: agentId));

      return {
        'sessionId': sessionId,
        'status': 'processing',
      };
    });

    // 6. session/cancel
    rpcRegistry.register('session/cancel', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }

      final agent = agentManager.getAgent(null);
      agent.stop(sessionId);

      emitUpdate(
        AcpSessionUpdate(
          sessionId: sessionId,
          type: AcpUpdateType.state,
          data: {'status': 'cancelled'},
        ),
      );

      _log.info('ACP session cancelled: $sessionId');
      return {'sessionId': sessionId, 'status': 'cancelled'};
    });

    // 7. session/review_response
    rpcRegistry.register('session/review_response', (params, context) async {
      final reviewId = params?['reviewId'] as String?;
      final approved = params?['approved'] as bool? ?? false;
      final sessionId = params?['sessionId'] as String?;

      if (reviewId == null) {
        throw ProtocolError('Missing required parameter: reviewId');
      }

      bool found = false;
      for (final s in _sessions.values) {
        if (sessionId != null && s.sessionId != sessionId) continue;
        final completer = s.pendingReviews[reviewId];
        if (completer != null && !completer.isCompleted) {
          completer.complete(approved);
          s.pendingReviews.remove(reviewId);
          found = true;
          break;
        }
      }

      if (!found) {
        _log.warning('No pending review found for reviewId: $reviewId');
      }

      return {'reviewId': reviewId, 'processed': found};
    });

    // 8. context/providers
    rpcRegistry.register('context/providers', (params, context) async {
      final providers = <Map<String, dynamic>>[];
      if (contextProvider != null) {
        providers.add(contextProvider!.getProviderMetadata());
      }
      return {'providers': providers};
    });

    // 9. context/query
    rpcRegistry.register('context/query', (params, context) async {
      final query = params?['query'] as String?;
      final workspacePath = params?['workspacePath'] as String?;
      if (query == null || contextProvider == null) {
        return {'items': []};
      }

      final items = await contextProvider!.query(
        query,
        workspacePath: workspacePath,
      );
      return {'items': items.map((i) => i.toJson()).toList()};
    });

    // 10. session/set_autopilot_mode
    rpcRegistry.register('session/set_autopilot_mode', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      final modeStr = params?['mode'] as String?;
      if (sessionId == null || modeStr == null) {
        throw ProtocolError('Missing sessionId or mode');
      }
      final session = _sessions[sessionId];
      if (session == null) {
        throw ProtocolError('Session not found: $sessionId');
      }

      session.autopilotMode = modeStr == 'autoAccept'
          ? AutopilotMode.autoAccept
          : AutopilotMode.reviewMode;

      return {'sessionId': sessionId, 'autopilotMode': session.autopilotMode.name};
    });
  }

  /// Sends an ACP update notification to the client.
  void emitUpdate(AcpSessionUpdate update) {
    onNotification?.call(update.toRpcNotification());
  }

  /// Requests a user review when running in Review-Mode (Guarded Autopilot).
  Future<bool> requestReview(
    String sessionId, {
    required String actionType,
    required Map<String, dynamic> details,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final session = _sessions[sessionId];
    if (session == null || session.autopilotMode == AutopilotMode.autoAccept) {
      // Auto-Accept: immediately approved
      return true;
    }

    final reviewId = 'rev_${_uuid.v4()}';
    final completer = Completer<bool>();
    session.pendingReviews[reviewId] = completer;

    _log.info('Emitting review request $reviewId for $actionType in session $sessionId');

    emitUpdate(
      AcpSessionUpdate(
        sessionId: sessionId,
        type: AcpUpdateType.reviewRequest,
        data: {
          'reviewId': reviewId,
          'actionType': actionType,
          'details': details,
        },
      ),
    );

    emitUpdate(
      AcpSessionUpdate(
        sessionId: sessionId,
        type: AcpUpdateType.state,
        data: {'status': 'review_required', 'reviewId': reviewId},
      ),
    );

    try {
      final approved = await completer.future.timeout(
        timeout,
        onTimeout: () {
          session.pendingReviews.remove(reviewId);
          _log.warning('Review $reviewId timed out after ${timeout.inSeconds}s');
          return false;
        },
      );
      return approved;
    } catch (e) {
      session.pendingReviews.remove(reviewId);
      return false;
    }
  }

  /// Executes prompt in agent runtime with ACP event streaming.
  Future<void> _executePrompt(
    AcpSession session,
    String promptText, {
    String? agentId,
  }) async {
    final sessionId = session.sessionId;
    final agent = agentManager.getAgent(agentId);

    // Apply workspace directory to agent
    if (session.workspaceRoot.isNotEmpty && session.workspaceRoot != '.') {
      agent.workspaceDir = session.workspaceRoot;
    }

    // Context enrichment via Context Provider
    String enrichedPrompt = promptText;
    if (contextProvider != null) {
      final contextBlock = await contextProvider!.buildEnrichedPromptContext(
        promptText,
        workspacePath: session.workspaceRoot,
      );
      if (contextBlock.isNotEmpty) {
        enrichedPrompt = '$promptText\n$contextBlock';
      }
    }

    // Add user message to history
    await agentManager.sessionManager.addMessage(
      sessionId: sessionId,
      role: 'user',
      content: promptText,
    );

    emitUpdate(
      AcpSessionUpdate(
        sessionId: sessionId,
        type: AcpUpdateType.state,
        data: {'status': 'thinking'},
      ),
    );

    try {
      await agent.processMessage(
        sessionId: sessionId,
        content: enrichedPrompt,
        onPartialResponse: (chunk) {
          emitUpdate(
            AcpSessionUpdate(
              sessionId: sessionId,
              type: AcpUpdateType.textDelta,
              data: {'delta': chunk},
            ),
          );
        },
        onActivityUpdate: (activity) {
          emitUpdate(
            AcpSessionUpdate(
              sessionId: sessionId,
              type: AcpUpdateType.thoughtDelta,
              data: {'delta': activity},
            ),
          );
        },
      );

      emitUpdate(
        AcpSessionUpdate(
          sessionId: sessionId,
          type: AcpUpdateType.state,
          data: {'status': 'idle'},
        ),
      );
    } catch (e) {
      _log.severe('Error processing ACP prompt in session $sessionId: $e');
      emitUpdate(
        AcpSessionUpdate(
          sessionId: sessionId,
          type: AcpUpdateType.state,
          data: {'status': 'error', 'error': e.toString()},
        ),
      );
    }
  }

  /// Process an incoming JSON-RPC raw string from any transport.
  Future<String?> handleRawMessage(String raw) async {
    const context = RpcContext(isAuthenticated: true);
    return rpcRegistry.handleRequest(raw, context);
  }
}
