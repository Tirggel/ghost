// Ghost — Agent runtime.

import 'dart:async';
import 'package:logging/logging.dart';

import '../models/message.dart';
import '../models/provider.dart';
import '../sessions/manager.dart';
import '../tools/registry.dart';
import '../config/secure_storage.dart';
import '../config/config.dart';
import 'providers/factory.dart';
import 'memory_system.dart';

final _log = Logger('Ghost.Agent');

/// State of an active agent turn.
enum AgentState { idle, thinking, executingTools, finishing }

/// Agent runtime that coordinates models, tools, and memory.
class Agent {
  Agent({
    required this.id,
    required this.provider,
    required this.sessionManager,
    required this.toolRegistry,
    required this.storage,
    required this.memory,
    this.systemPrompt = 'You are a helpful AI assistant.',
    int? maxToolIterations,
    this.workspaceDir = '.',
    this.stateDir = '.ghost',
    this.browserHeadless = true,
    this.shouldSendChatHistory = true,
    this.security = const SecurityConfig(),
  }) : _maxToolIterationsOverride = maxToolIterations;

  final String id;
  AIModelProvider provider;
  final SessionManager sessionManager;
  final ToolRegistry toolRegistry;
  final SecureStorage storage;
  final MemorySystem memory;
  String systemPrompt;
  final int? _maxToolIterationsOverride;
  String workspaceDir;
  final String stateDir;
  bool browserHeadless;
  bool shouldSendChatHistory;
  SecurityConfig security;
  final Set<String> _stoppedSessions = {};

  int get maxToolIterations {
    if (_maxToolIterationsOverride != null) return _maxToolIterationsOverride!;
    switch (security.level) {
      case SecurityLevel.high:
        return 5;
      case SecurityLevel.medium:
        return 15;
      case SecurityLevel.low:
        return 25;
      case SecurityLevel.none:
        return 40;
    }
  }

  AgentState _state = AgentState.idle;
  AgentState get state => _state;

  /// Process an incoming message for a session.
  Future<void> processMessage({
    required String sessionId,
    required String content,
    List<MessageAttachment> attachments = const [],
    String? model,
    String? providerHint,
    Map<String, dynamic> metadata = const {},
    void Function(String chunk)? onPartialResponse,
    void Function(String activity)? onActivityUpdate,
  }) async {
    _stoppedSessions.remove(sessionId);
    _state = AgentState.thinking;
    _log.info('Processing message for session $sessionId');

    try {
      final history =
          await sessionManager.getHistory(sessionId, maxMessages: 20);
      // Filter out internal system messages (like session rename events)
      // which are not intended for the LLM.
      final fullHistory =
          history.where((m) => m.role != 'system').toList();

      final messages = shouldSendChatHistory
          ? fullHistory
          : (fullHistory.isNotEmpty ? [fullHistory.last] : <Message>[]);

      // --- Sentinel: HITL decline recorded silently, no LLM call needed ---
      if (content.trim() == '__HITL_DECLINED__') {
        _log.info('HITL declined sentinel received for session $sessionId');
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'user',
          content: '__HITL_DECLINED__',
          metadata: {'hitl_declined': true},
        );
        _state = AgentState.idle;
        onActivityUpdate?.call('');
        return;
      }

      // 2. Start the turn loop (to handle multiple tool calls)
      int iterations = 0;

      // Sanitize history: remove assistant+tool pairs from HITL-blocked turns.
      // Two cases:
      //   1. Null tool_call IDs (leftover in-memory turns, cause 400 errors)
      //   2. Tool results containing SECURITY ALERT (stored in DB, cause agent to retry blocked actions)
      final sanitized = <Message>[];
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.role == 'assistant' && m.metadata.containsKey('tool_calls')) {
          final calls = m.metadata['tool_calls'] as List<dynamic>;

          // Case 1: null IDs
          final hasNullId = calls.any((c) {
            final id = (c as Map<String, dynamic>)['id'];
            return id == null || id == 'null' || (id is String && id.isEmpty);
          });

          // Case 2: look ahead — any following tool message contains SECURITY ALERT?
          bool hasSecurityBlock = false;
          int j = i + 1;
          while (j < messages.length && messages[j].role == 'tool') {
            if (messages[j].content.contains('SECURITY ALERT') ||
                messages[j].content.contains('Tool execution blocked')) {
              hasSecurityBlock = true;
            }
            j++;
          }

          if (hasNullId || hasSecurityBlock) {
            // Scan forward past ALL tool/assistant messages until we reach
            // a user message. If it's __HITL_DECLINED__, include and skip it.
            // If it's a real user message, stop before it.
            while (j < messages.length) {
              if (messages[j].role == 'user') {
                if (messages[j].content.trim() == '__HITL_DECLINED__') {
                  j++; // include the sentinel in the removed range
                }
                break; // stop (next real user message stays in history)
              }
              j++; // skip tool, assistant, system messages
            }
            i = j - 1;
            _log.info(
              'Sanitized HITL-blocked turn (nullId=$hasNullId, '
              'securityBlock=$hasSecurityBlock)',
            );
            continue;
          }
        }
        sanitized.add(m);
      }

      final turnMessages = List<Message>.from(sanitized);

      // Resolve the provider to use (either override or global default)
      AIModelProvider activeProvider = provider;
      if (model != null || providerHint != null) {
        // If it's the SAME as default, just use default
        if (model == provider.modelId &&
            (providerHint == null || providerHint == provider.providerId)) {
          // No change needed
        } else if (model != null || providerHint != null) {
          _log.info(
              'Using session-specific model override: $model (hint: $providerHint)');
          activeProvider = await ProviderFactory.create(
            model: model ?? provider.modelId,
            provider: providerHint,
            storage: storage,
          );
        }
      }

      // 2.5 Query Memory (RAG) — never block chat if this fails
      List<String> memoryContext = [];
      try {
        _log.fine('Automatic memory retrieval for: $content');
        onActivityUpdate?.call('Memory: Searching...');
        memoryContext =
            await memory.query(content, activeProvider: activeProvider);
        if (memoryContext.isNotEmpty) {
          _log.info('Found ${memoryContext.length} relevant memory chunks:');
          for (var i = 0; i < memoryContext.length; i++) {
            _log.info('  Memory [$i]: ${memoryContext[i]}');
          }
          onActivityUpdate?.call('Memory: Found context');
        } else {
          _log.info('No relevant facts found in memory for query: "$content"');
          onActivityUpdate?.call('Memory: No relevant facts');
        }
      } catch (e) {
        _log.warning('Memory query failed (non-blocking): $e');
        onActivityUpdate?.call('');
      }

      // Wait a tiny bit so the user can see the memory status
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final List<Map<String, dynamic>> executedToolSummaries = [];
      final contentBuffer = StringBuffer();
      Map<String, dynamic>? finalUsage;
      bool hitlWasTriggered = false; // set true if any tool was HITL-blocked

      final totalToolsLimit = maxToolIterations * 2;
      var totalToolsExecuted = 0;

      while (iterations < maxToolIterations) {
        if (_stoppedSessions.contains(sessionId)) {
          _log.info('Session $sessionId stopped by user.');
          _stoppedSessions.remove(sessionId);
          break;
        }
        iterations++;
        _log.fine('Iteration $iterations for session $sessionId');

        onActivityUpdate?.call('AI: Processing turn $iterations...');

        // --- Model Execution ---
        final now = DateTime.now();
        final days = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday'
        ];
        final timeStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} '
            '(${days[now.weekday - 1]})';

        final contextString = memoryContext.isNotEmpty
            ? '\n\n[MEMORY CONTEXT]:\n${memoryContext.join('\n---\n')}'
            : '';

        const String memoryInstruction =
            '\nIf the [MEMORY CONTEXT] above is missing or insufficient, use the "memory_query" tool to search for specific past information.\n'
            'When you use "memory_add" for personal facts, use the category "user_profile".\n'
            'After adding a memory, use the tool output to see if related facts already exist, and acknowledge them in your response to the user.';

        final dynamicSystemPrompt =
            '$systemPrompt\n\n[SYSTEM: The current date and time is $timeStr]$contextString$memoryInstruction\n';

        final activeTools = toolRegistry
            .getToolDefinitions()
            .map((d) => ToolDefinition(
                  name: (d['name'] as String?) ?? '',
                  description: (d['description'] as String?) ?? '',
                  inputSchema: d['input_schema'] as Map<String, dynamic>? ?? {},
                ))
            .where((t) => t.name.isNotEmpty)
            .toList();

        final totalChars =
            turnMessages.fold<int>(0, (sum, m) => sum + m.content.length) +
                dynamicSystemPrompt.length;
        _log.info(
            'AI Turn $iterations: Sending request with ${turnMessages.length} messages (~$totalChars chars)');

        onActivityUpdate?.call('AI: Waiting for provider...');
        AIResponse response;
        try {
          response = await activeProvider.chat(
            messages: turnMessages,
            systemPrompt: dynamicSystemPrompt,
            tools: activeTools,
          );
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('context_length_exceeded') ||
              errorStr.contains('maximum context length') ||
              errorStr.contains('400')) {
            _log.warning(
                'Context length exceeded. Pruning history and retrying...');
            if (turnMessages.length > 2) {
              turnMessages.removeAt(0);
              iterations--;
              continue;
            }
          }
          rethrow;
        }

        if (response.content.isNotEmpty) {
          contentBuffer.write(response.content);
          if (onPartialResponse != null) {
            onPartialResponse(response.content);
          }
        }

        if (response.usage != null) {
          finalUsage = {
            'input': response.usage!.inputTokens,
            'output': response.usage!.outputTokens,
          };
        }

        // --- Handle Tool Calls ---
        if (!response.hasToolCalls) {
          _log.info('Agent achieved final response on iteration $iterations');
          break;
        }

        _state = AgentState.executingTools;

        // Add assistant turn to history
        turnMessages.add(Message(
          role: 'assistant',
          content: response.content,
          timestamp: DateTime.now(),
          metadata: {
            'tool_calls': response.toolCalls.map((tc) => tc.toJson()).toList(),
            if (response.content.contains('Tool execution blocked'))
              'hitl_blocked': true,
          },
        ));

        for (var i = 0; i < response.toolCalls.length; i++) {
          final call = response.toolCalls[i];

          if (totalToolsExecuted >= totalToolsLimit) {
            _log.warning(
                'Total tool limit reached ($totalToolsLimit). Stopping turn.');
            break;
          }
          totalToolsExecuted++;

          final progress = response.toolCalls.length > 1
              ? ' [${i + 1}/${response.toolCalls.length}]'
              : '';

          try {
            final tool = toolRegistry.getTool(call.name);
            final summary = tool?.getLogSummary(call.arguments);
            final label = tool?.label ?? call.name;

            onActivityUpdate?.call(
                '${summary != null ? '$label: $summary' : label}$progress');

            executedToolSummaries.add({
              'name': call.name,
              'label': label,
              'summary': summary,
              'arguments': call.arguments,
            });

            final result = await _executeToolWithHITL(
              call,
              sessionId,
              toolRegistry,
              activeProvider,
              turnMessages,
            );

            // Track if HITL actually blocked this tool
            if (result.isError && result.output.contains('SECURITY ALERT')) {
              hitlWasTriggered = true;
            }

            String output = result.output;
            if (output.length > 40000) {
              output =
                  '${output.substring(0, 40000)}\n\n(--- OUTPUT TRUNCATED ---)';
            }

            turnMessages.add(Message(
              role: 'tool',
              content: output,
              timestamp: DateTime.now(),
              metadata: {
                'tool_call_id': call.id,
                'tool_name': call.name,
                'is_error': result.isError,
                ...result.metadata,
              },
            ));
          } catch (e) {
            _log.warning('Tool execution failed: $e');
            turnMessages.add(Message(
              role: 'tool',
              content: 'Error: $e',
              timestamp: DateTime.now(),
              metadata: {
                'tool_call_id': call.id,
                'tool_name': call.name,
                'is_error': true
              },
            ));
          }
        }

        _state = AgentState.thinking;
        onActivityUpdate?.call('AI: Integrating results...');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      _state = AgentState.idle;
      onActivityUpdate?.call('');

      // --- Final Save ---
      if (contentBuffer.isNotEmpty) {
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'assistant',
          content: contentBuffer.toString(),
          metadata: {
            ...metadata,
            'agentId': id,
            'provider': activeProvider.providerId,
            'model': activeProvider.modelId,
            'usage': finalUsage,
            'tool_calls': executedToolSummaries,
            if (hitlWasTriggered) 'hitl_pending': true,
          },
        );
      }
    } catch (e) {
      _log.severe('Agent processing failed: $e');
      rethrow;
    } finally {
      _state = AgentState.idle;
    }
  }

  /// Interrupt processing for a specific session.
  void stop(String sessionId) {
    _stoppedSessions.add(sessionId);
    _log.info('Stop signal received for session $sessionId');
  }

  Future<ToolResult> _executeToolWithHITL(
    ToolCall call,
    String sessionId,
    ToolRegistry registry,
    AIModelProvider activeProvider,
    List<Message> turnMessages,
  ) async {
    final isCron = sessionId.startsWith('cron_');

    // Check if security dictates HITL for this tool
    if (security.humanInTheLoop && !isCron) {
      final sensitiveTools = [
        'bash',
        'terminal',
        'exec',
        'process',
        'write_file',
        'edit_file',
        'apply_patch',
        'delete_file',
        'github',
        'github_pr',
        'github_commit',
        'browser_open',
        'browser_click',
        'browser_type'
      ];
      if (sensitiveTools.contains(call.name)) {
        // Did the user already confirm in recent context?
        // simple heuristic: last user message contains confirmation words.
        Message? lastUser;
        for (var i = turnMessages.length - 1; i >= 0; i--) {
          if (turnMessages[i].role == 'user') {
            lastUser = turnMessages[i];
            break;
          }
        }

        bool isConfirmed = false;
        if (lastUser != null) {
          final text = lastUser.content.toLowerCase().trim();
          // Use whole-word matching to avoid false positives.
          // e.g. 'y' would match 'py', 'schreibe' contains 'y' etc.
          final confirmPattern = RegExp(
            r'\b(ja|yes|ok|okay|yep|sure|bestätige|bestätig|erlaubt|gerne|klar|natürlich|do it|go ahead|proceed|confirm|allow|weiter|mach es|mach das)\b',
            caseSensitive: false,
          );
          isConfirmed = confirmPattern.hasMatch(text);
        }

        if (!isConfirmed) {
          _log.info(
              'HITL intercepted tool execution for ${call.name} in session $sessionId');
          return ToolResult(
            output:
                'SECURITY ALERT: Tool execution blocked by Human-In-The-Loop policy.\n'
                'You MUST ask the user for explicit permission to execute "${call.name}".\n'
                'The user will see "YES" and "NO" buttons to confirm.\n'
                'Wait for the user to say "yes" (or click the button) before trying again.',
            isError: true,
          );
        }
      }
    }

    return registry.execute(
      call.name,
      call.arguments,
      ToolContext(
        sessionId: sessionId,
        agentId: id,
        workspaceDir: workspaceDir,
        stateDir: stateDir,
        activeProvider: activeProvider,
        browserHeadless: browserHeadless,
        restrictNetwork: security.restrictNetwork,
      ),
    );
  }
}
