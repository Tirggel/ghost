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
    this.name = 'Agent',
    required this.provider,
    required this.sessionManager,
    required this.toolRegistry,
    required this.storage,
    required this.memory,
    this.skills = const [],
    this.systemPrompt = 'You are a helpful AI assistant.',
    int? maxToolIterations,
    this.workspaceDir = '.',
    this.stateDir = '.ghost',
    this.browserHeadless = true,
    this.shouldSendChatHistory = true,
    this.security = const SecurityConfig(),
    this.autonomousPayments = false,
  }) : _maxToolIterationsOverride = maxToolIterations;

  final String id;
  final String name;
  AIModelProvider provider;
  final SessionManager sessionManager;
  final ToolRegistry toolRegistry;
  final SecureStorage storage;
  final MemorySystem memory;
  List<String> skills;
  String systemPrompt;
  final int? _maxToolIterationsOverride;
  String workspaceDir;
  final String stateDir;
  bool browserHeadless;
  bool shouldSendChatHistory;
  SecurityConfig security;
  bool autonomousPayments;
  final Set<String> _stoppedSessions = {};

  int get maxToolIterations {
    if (_maxToolIterationsOverride != null) return _maxToolIterationsOverride;
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
      final history = await sessionManager.getHistory(
        sessionId,
        maxMessages: 20,
      );
      // Filter out internal system messages (like session rename events)
      // which are not intended for the LLM.
      final fullHistory = history.where((m) => m.role != 'system').toList();

      final isGoalMode = content.trim().startsWith('/goal') ||
          fullHistory.any((m) => m.role == 'user' && m.content.trim().startsWith('/goal'));

      String activeGoal = '';
      if (isGoalMode) {
        if (content.trim().startsWith('/goal')) {
          activeGoal = content.trim().substring(5).trim();
        } else {
          final firstGoalMsg = fullHistory.firstWhere(
            (m) => m.role == 'user' && m.content.trim().startsWith('/goal'),
            orElse: () => Message(role: 'user', content: content, timestamp: DateTime.now()),
          );
          final text = firstGoalMsg.content.trim();
          activeGoal = text.startsWith('/goal') ? text.substring(5).trim() : text;
        }
      }

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
            'Using session-specific model override: $model (hint: $providerHint)',
          );
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
        memoryContext = await memory.query(
          content,
          activeProvider: activeProvider,
        );
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
      String? lastReasoningContent;
      Map<String, dynamic>? finalUsage;
      bool hitlWasTriggered = false; // set true if any tool was HITL-blocked

      final effectiveMaxIterations = isGoalMode ? 100 : maxToolIterations;
      final totalToolsLimit = effectiveMaxIterations * 2;
      var totalToolsExecuted = 0;

      while (iterations < effectiveMaxIterations) {
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
          'Sunday',
        ];
        final timeStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} '
            '(${days[now.weekday - 1]})';

        // --- Context & Focus Refinement ---
        final contextString = memoryContext.isNotEmpty
            ? '\n\n[HISTORICAL CONTEXT (for reference only, do NOT repeat unless requested)]:\n${memoryContext.join('\n---\n')}'
            : '';

        const String memoryInstruction =
            '\nIf the [HISTORICAL CONTEXT] above is missing or insufficient, use the "memory_query" tool to search for specific past information.\n'
            'When you use "memory_add" for personal facts, use the category "user_profile".\n';

        const String vaultInstruction =
            '\n[VAULT NAMING CONVENTION]\n'
            'When accessing credentials from the Vault in skills or code:\n'
            '- Service names are used as prefixes (e.g., "SPOTIFY").\n'
            '- Keys like "Client ID" or "Client Secret" are appended as "_CLIENT_ID" or "_CLIENT_SECRET".\n'
            '- The resulting environment variables are in ALL CAPS (e.g., "SPOTIFY_CLIENT_ID").\n'
            '- Do NOT append "_API_KEY" to these variables unless explicitly required by the service.\n';

        const String focusInstruction =
            '\n[CRITICAL INSTRUCTION — MANDATORY]\n'
            'The conversation history provided above is ONLY for long-term reference and context for follow-up questions. '
            'The user can already see the entire chat history in their interface.\n'
            '1. Your SOLE task is to answer the SINGLE message marked "### ACTIVE REQUEST" below.\n'
            '2. NEVER repeat, re-answer, or summarize earlier questions or answers from the history.\n'
            '3. Do NOT provide "status updates" or "running summaries" of the chat.\n'
            '4. Treat every turn as a fresh, independent request unless it explicitly refers to a previous detail.\n';

        // Explicit instruction to use tools — critical for small local models
        // that otherwise claim they have no access to real-time information.
        const String toolUseInstruction =
            '\n[TOOL USE — CRITICAL]\n'
            'You have fully working tools available. ALWAYS use them proactively:\n'
            '- weather, news, prices, scores, or ANY real-time / current data → call web_search immediately. NEVER say you lack access to this data.\n'
            '- reading or writing files → use read_file / write_file / list_dir.\n'
            '- running commands or code → use bash.\n'
            '- finding past conversations or user facts → use memory_query.\n'
            'Do NOT apologize for missing tools. If the information requires the internet, call web_search.\n';

        final goalInstruction = isGoalMode
            ? '\n[AUTONOMOUS GOAL MODE ACTIVE (Google Antigravity 2.0)]\n'
                '1. The user initiated this request with `/goal`. Your active goal is: "$activeGoal"\n'
                '2. You must work autonomously to complete the task fully.\n'
                '3. Do NOT ask the user for confirmation, permission, or clarification. Assume approval for all tool and command executions.\n'
                '4. Do NOT output intermediate questions or requests for feedback. If you encounter a problem, find a workaround using your tools.\n'
                '5. Continue to execute tools and refine your work in subsequent iterations until the task is completely finished.\n'
                '6. Only produce your final response when the goal is fully achieved. Highlight what you did and show verification/testing results.'
            : '';

        final dynamicSystemPrompt =
            '$systemPrompt\n\n[SYSTEM: The current date and time is $timeStr]$contextString$memoryInstruction$vaultInstruction$focusInstruction$toolUseInstruction$goalInstruction\n';

        // For local providers (Ollama, vLLM, LM Studio), limit the tool set
        // to core tools only. Small models (2–4B) cannot reliably select from
        // 45+ tool definitions — it overloads their context and causes them to
        // ignore all tools. Core tools cover >90% of real-world use cases.
        const _localCoreTools = {
          'web_search', 'web_fetch',
          'bash', 'terminal',
          'read_file', 'write_file', 'list_dir', 'download_file',
          'memory_add', 'memory_query',
          'browser',
          'github',
          'store_api_key',
          'import_skill', 'list_skills',
          'sessions_list', 'sessions_history',
          'manage_agents',
        };

        final isLocalProvider = activeProvider.providerId == 'ollama' ||
            activeProvider.providerId == 'ipex-llm' ||
            activeProvider.providerId == 'lmstudio' ||
            activeProvider.providerId == 'vllm';

        final allTools = toolRegistry
            .getToolDefinitions()
            .map(
              (d) => ToolDefinition(
                name: (d['name'] as String?) ?? '',
                description: (d['description'] as String?) ?? '',
                inputSchema: d['input_schema'] as Map<String, dynamic>? ?? {},
              ),
            )
            .where((t) => t.name.isNotEmpty)
            .toList();

        final activeTools = isLocalProvider
            ? allTools.where((t) => _localCoreTools.contains(t.name)).toList()
            : allTools;

        // Inject focus marker into the last user message, and strip any
        // leftover markers from earlier messages so the LLM only sees one.
        final lastUserIdx = turnMessages.lastIndexWhere((m) => m.role == 'user');
        final processedMessages = <Message>[];
        for (int mi = 0; mi < turnMessages.length; mi++) {
          final msg = turnMessages[mi];
          final isLastUser = mi == lastUserIdx;

          if (msg.role == 'user') {
            // Strip old focus markers from previous turns using a robust regex
            var cleanContent = msg.content
                .replaceFirst(
                  RegExp(
                    r'^(?:###\s*(?:CURRENT TASK|ACTIVE REQUEST|FOCUS)[^\n]*\n|\[REMINDER:[^\]]*\]\s*)',
                    multiLine: true,
                  ),
                  '',
                )
                .trim();

            // Strip `/goal` prefix if present
            if (cleanContent.startsWith('/goal')) {
              cleanContent = cleanContent.substring(5).trim();
            }

            if (isLastUser) {
              // Mark only the newest user message as the active request
              processedMessages.add(
                Message(
                  role: 'user',
                  content:
                      '### ACTIVE REQUEST (Answer ONLY this and do NOT repeat previous turns):\n$cleanContent',
                  timestamp: msg.timestamp,
                  metadata: msg.metadata,
                ),
              );
            } else {
              // Previous user messages: strip marker, keep clean content
              processedMessages.add(
                Message(
                  role: 'user',
                  content: cleanContent,
                  timestamp: msg.timestamp,
                  metadata: msg.metadata,
                ),
              );
            }
          } else {
            processedMessages.add(msg);
          }
        }

        final totalChars =
            processedMessages.fold<int>(0, (sum, m) => sum + m.content.length) +
            dynamicSystemPrompt.length;
        _log.info(
          'AI Turn $iterations: Sending request with ${processedMessages.length} messages (~$totalChars chars)',
        );

        onActivityUpdate?.call('AI: Waiting for provider...');
        AIResponse response;
        try {
          response = await activeProvider.chat(
            messages: processedMessages,
            systemPrompt: dynamicSystemPrompt,
            tools: activeTools,
          );
          if (response.reasoningContent != null) {
            lastReasoningContent = response.reasoningContent;
          }
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('context_length_exceeded') ||
              errorStr.contains('maximum context length') ||
              errorStr.contains('400')) {
            _log.warning(
              'Context length exceeded. Pruning history and retrying...',
            );
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
        turnMessages.add(
          Message(
            role: 'assistant',
            content: response.content,
            timestamp: DateTime.now(),
            metadata: {
              'tool_calls': response.toolCalls
                  .map((tc) => tc.toJson())
                  .toList(),
              if (response.reasoningContent != null)
                'reasoning_content': response.reasoningContent,
              if (response.content.contains('Tool execution blocked'))
                'hitl_blocked': true,
            },
          ),
        );

        for (var i = 0; i < response.toolCalls.length; i++) {
          final call = response.toolCalls[i];

          if (totalToolsExecuted >= totalToolsLimit) {
            _log.warning(
              'Total tool limit reached ($totalToolsLimit). Stopping turn.',
            );
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
              '${summary != null ? '$label: $summary' : label}$progress',
            );

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
              isGoalMode: isGoalMode,
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

            turnMessages.add(
              Message(
                role: 'tool',
                content: output,
                timestamp: DateTime.now(),
                metadata: {
                  'tool_call_id': call.id,
                  'tool_name': call.name,
                  'is_error': result.isError,
                  ...result.metadata,
                },
              ),
            );
          } catch (e) {
            _log.warning('Tool execution failed: $e');
            turnMessages.add(
              Message(
                role: 'tool',
                content: 'Error: $e',
                timestamp: DateTime.now(),
                metadata: {
                  'tool_call_id': call.id,
                  'tool_name': call.name,
                  'is_error': true,
                },
              ),
            );
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
            if (lastReasoningContent != null)
              'reasoning_content': lastReasoningContent,
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
    List<Message> turnMessages, {
    bool isGoalMode = false,
  }) async {
    final isCron = sessionId.startsWith('cron_');

    bool requiresHitl = false;

    // Check if security dictates HITL for this tool
    if (security.humanInTheLoop && !isCron && !isGoalMode) {
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
        'browser_type',
        'binance_create_order',
        'binance_demo_create_order',
        'execute_blockchain_payment',
        'execute_token_swap',
      ];
      if (sensitiveTools.contains(call.name)) {
        requiresHitl = true;
      }
    }

    // Check if autonomous payments are disabled
    if (call.name == 'execute_blockchain_payment' && !autonomousPayments) {
      requiresHitl = true;
    }

    if (requiresHitl) {
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
            'HITL intercepted tool execution for ${call.name} in session $sessionId',
          );
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
