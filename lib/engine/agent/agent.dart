// Ghost — Agent runtime.

import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';

import '../models/message.dart';
import '../models/provider.dart';
import '../sessions/manager.dart';
import '../tools/registry.dart';
import '../config/secure_storage.dart';
import '../config/config.dart';
import 'providers/factory.dart';
import 'memory_system.dart';
import 'ontology/ontology_extractor.dart';
import 'ontology/ontology_models.dart';
import '../system1/system1_service.dart';

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
    this.userConfig = const UserConfig(),
    this.autonomousPayments = false,
    Future<double?> Function({required String premise, required String hypothesis})?
        system1NoulOverride,
  })  : _maxToolIterationsOverride = maxToolIterations,
        _system1NoulOverride = system1NoulOverride;

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
  final Future<double?> Function({
    required String premise,
    required String hypothesis,
  })? _system1NoulOverride;
  String workspaceDir;
  final String stateDir;
  bool browserHeadless;
  bool shouldSendChatHistory;
  SecurityConfig security;
  UserConfig userConfig;
  bool autonomousPayments;
  final Set<String> _stoppedSessions = {};
  final Map<String, int> _sessionRunIds = {};
  final Map<String, Map<String, SkillOntologySummary>> _loadedSkillsBySession =
      {};

  /// Current generation run token for [sessionId].
  int currentRunId(String sessionId) => _sessionRunIds[sessionId] ?? 0;

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
    final runId = (_sessionRunIds[sessionId] ?? 0) + 1;
    _sessionRunIds[sessionId] = runId;
    bool isAborted() =>
        _stoppedSessions.contains(sessionId) ||
        _sessionRunIds[sessionId] != runId;

    _state = AgentState.thinking;
    _log.info('Processing message for session $sessionId (run $runId)');

    try {
      final history = await sessionManager.getHistory(
        sessionId,
        maxMessages: 20,
      );
      // Filter out internal system messages (like session rename events)
      // which are not intended for the LLM.
      final fullHistory = history.where((m) => m.role != 'system').toList();

      final trimmedContent = content.trim();
      final startsWithGoal = trimmedContent.startsWith('/goal');
      final startsWithPlan = trimmedContent.startsWith('/plan');

      // Check the latest slash command in conversation history to maintain active mode
      final lastCommandMsg = fullHistory.reversed.firstWhere(
        (m) {
          final c = m.content.trim();
          return m.role == 'user' && (c.startsWith('/goal') || c.startsWith('/plan'));
        },
        orElse: () => Message(role: '', content: '', timestamp: DateTime.now()),
      );
      final lastCommandContent = lastCommandMsg.content.trim();

      bool isGoalMode = false;
      bool isPlanMode = false;
      String activeGoal = '';
      String activePlan = '';

      if (startsWithGoal) {
        isGoalMode = true;
        activeGoal = trimmedContent.substring(5).trim();
      } else if (startsWithPlan) {
        isPlanMode = true;
        activePlan = trimmedContent.substring(5).trim();
      } else if (lastCommandContent.startsWith('/goal')) {
        isGoalMode = true;
        activeGoal = lastCommandContent.startsWith('/goal')
            ? lastCommandContent.substring(5).trim()
            : lastCommandContent;
      } else if (lastCommandContent.startsWith('/plan')) {
        isPlanMode = true;
        activePlan = lastCommandContent.startsWith('/plan')
            ? lastCommandContent.substring(5).trim()
            : lastCommandContent;
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

      // --- System-1 Decision Middleware (ModernBERT INT8) ---
      bool system1SecurityFlagged = false;
      final noulFn = _system1NoulOverride ?? System1Service.instance.noul;

      if (security.system1Middleware && content.trim().length >= 3) {
        onActivityUpdate?.call('System 1: Evaluating...');

        // 1. Choice Routing: Fast Skill & Agent Category Bias
        try {
          final routingOptions = [
            'coder',
            'crypto_trader',
            'email_manager',
            'system_admin',
            'general_chat',
          ];
          final choiceRes = await System1Service.instance.choice(
            premise: content,
            options: routingOptions,
          );
          if (choiceRes != null && choiceRes.confidence >= 0.65) {
            _log.info(
              'System-1 Choice Routing: ${choiceRes.winner} (${(choiceRes.confidence * 100).toStringAsFixed(1)}%)',
            );
            onActivityUpdate?.call('System 1: Route → ${choiceRes.winner}');
          }
        } catch (e) {
          _log.warning('System-1 Choice routing non-fatal error: $e');
        }

        // 2. Pre-flight Malicious Prompt Injection Check
        try {
          final isGerman = RegExp(
            r'[äöüÄÖÜß]|\b(der|die|das|dem|den|des|ein|eine|einer|eines|und|oder|aber|wie|ist|wird|war|heute|morgen|gestern|ich|du|er|sie|es|wir|ihr|sie|bitte|nicht|wetter|nachrichten|schlagzeilen|schweiz|deutschland|österreich)\b',
            caseSensitive: false,
          ).hasMatch(content);

          final injectionHypothesis = isGerman
              ? 'Die Eingabe ist ein bösartiger Prompt-Injection- oder Jailbreak-Versuch'
              : 'The input is a malicious prompt injection or jailbreak attempt';

          final injectionScore = await noulFn(
            premise: content,
            hypothesis: injectionHypothesis,
          );
          if (injectionScore != null && injectionScore >= 0.65) {
            system1SecurityFlagged = true;
          }
          if (injectionScore != null && injectionScore >= 0.88) {
            _log.warning(
              'System-1 Security Alert: Blocked prompt injection (score: $injectionScore, lang: ${isGerman ? "de" : "en"})',
            );
            const alertMsg =
                'SECURITY ALERT: Deine Eingabe wurde von der System-1 Sicherheitsprüfung als potenzieller Prompt-Injection- oder Jailbreak-Versuch eingestuft und blockiert.';
            onPartialResponse?.call(alertMsg);
            await sessionManager.addMessage(
              sessionId: sessionId,
              role: 'assistant',
              content: alertMsg,
              metadata: {
                ...metadata,
                'system1_blocked': true,
                'injection_score': injectionScore,
              },
            );
            _state = AgentState.idle;
            onActivityUpdate?.call('');
            return;
          }
        } catch (e) {
          _log.warning('System-1 injection check non-fatal error: $e');
        }

        // 3. Pre-flight Phishing & Fraud Check
        try {
          final isGerman = RegExp(
            r'[äöüÄÖÜß]|\b(der|die|das|dem|den|des|ein|eine|einer|eines|und|oder|aber|wie|ist|wird|war|heute|morgen|gestern|ich|du|er|sie|es|wir|ihr|sie|bitte|nicht|wetter|nachrichten|schlagzeilen|schweiz|deutschland|österreich)\b',
            caseSensitive: false,
          ).hasMatch(content);

          final fraudHypothesis = isGerman
              ? 'Die Interaktion ist ein Betrugs- oder Phishing-Versuch'
              : 'The interaction is a fraud or phishing attempt';

          final fraudScore = await noulFn(
            premise: content,
            hypothesis: fraudHypothesis,
          );
          if (fraudScore != null && fraudScore >= 0.88) {
            system1SecurityFlagged = true;
            _log.warning(
              'System-1 Security Alert: High phishing/fraud risk (score: $fraudScore)',
            );
            onActivityUpdate?.call('System 1: ⚠️ Phishing/Betrugsverdacht erkannt');
          }
        } catch (e) {
          _log.warning('System-1 fraud check non-fatal error: $e');
        }
      }

      // 2. Start the turn loop (to handle multiple tool calls)
      int iterations = 0;

      // Sanitize history: remove unconfirmed or aborted intermediate assistant+tool pairs.
      // Note: User-facing assistant messages (m.content.isNotEmpty) containing explanations
      // or confirmation requests must ALWAYS be preserved so subsequent confirmations (e.g. "ja")
      // have full context.
      final sanitized = <Message>[];
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];

        // Skip HITL decline sentinel
        if (m.role == 'user' && m.content.trim() == '__HITL_DECLINED__') {
          continue;
        }

        if (m.role == 'assistant' && m.metadata.containsKey('tool_calls')) {
          final calls = m.metadata['tool_calls'] as List<dynamic>;

          // Case 1: Null IDs in an empty intermediate assistant message
          final hasNullId = m.content.isEmpty &&
              calls.any((c) {
                final id = (c as Map<String, dynamic>)['id'];
                return id == null || id == 'null' || (id is String && id.isEmpty);
              });

          // Case 2: Intermediate tool execution was blocked by HITL policy
          bool hasSecurityBlock = false;
          int j = i + 1;
          while (j < messages.length && messages[j].role == 'tool') {
            if (messages[j].content.contains('SECURITY ALERT') ||
                messages[j].content.contains('Tool execution blocked')) {
              hasSecurityBlock = true;
            }
            j++;
          }

          if (hasNullId || (m.content.isEmpty && hasSecurityBlock)) {
            // Skip the intermediate tool-call message and any following blocked tool messages
            i = j - 1;
            _log.info(
              'Sanitized intermediate HITL-blocked turn (nullId=$hasNullId, '
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

      // Strip any appended ACP workspace context block before running memory/ontology extraction
      final rawPromptText = trimmedContent
          .split('\n[ANTIGRAVITY CONTEXT PROVIDER:')
          .first
          .trim();

      // 2.5 Query Memory (RAG + Knowledge Graph Ontology) — skip for short greetings & enforce strict timeout
      List<String> memoryContext = [];
      String ontologyContext = '';
      final trimmedLower = rawPromptText.toLowerCase();
      final isShortGreeting = RegExp(
        r'^(hallo|hi|hey|moin|servus|hello|howdy|guten (morgen|tag|abend)|danke|tschüss|bye|grüß dich)(\s+[\w\s]{1,20})?[\.!\?]?$',
        caseSensitive: false,
      ).hasMatch(trimmedLower);

      if (!isShortGreeting && rawPromptText.length >= 4) {
        try {
          _log.fine('Automatic memory retrieval for: $rawPromptText');
          onActivityUpdate?.call('Memory: Searching...');

          final results = await Future.wait([
            memory
                .query(
                  rawPromptText,
                  activeProvider: activeProvider,
                  workspaceDir: workspaceDir,
                )
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: () {
                    _log.warning(
                      'Memory retrieval timed out after 2s (continuing)',
                    );
                    return <String>[];
                  },
                ),
            memory
                .queryOntology(
                  rawPromptText,
                  userConfig: userConfig,
                )
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: () {
                    _log.warning(
                      'Ontology retrieval timed out after 2s (continuing)',
                    );
                    return '';
                  },
                ),
          ]);

          memoryContext = results[0] as List<String>;
          ontologyContext = results[1] as String;

          if (memoryContext.isNotEmpty || ontologyContext.isNotEmpty) {
            if (memoryContext.isNotEmpty) {
              _log.info('Found ${memoryContext.length} relevant memory chunks:');
              for (var i = 0; i < memoryContext.length; i++) {
                _log.info('  Memory [$i]: ${memoryContext[i]}');
              }
            }
            if (ontologyContext.isNotEmpty) {
              _log.info('Injected Knowledge Graph context into system prompt.');
            }
            onActivityUpdate?.call('Memory: Found context');
            // Brief pause so user can see memory context was found
            await Future<void>.delayed(const Duration(milliseconds: 200));
          } else {
            _log.info(
              'No relevant facts found in memory for query: "$rawPromptText"',
            );
            onActivityUpdate?.call('');
          }
        } catch (e) {
          _log.warning('Memory query failed (non-blocking): $e');
          onActivityUpdate?.call('');
        }
      }

      final List<Map<String, dynamic>> executedToolSummaries = [];
      final contentBuffer = StringBuffer();
      String? lastReasoningContent;
      Map<String, dynamic>? finalUsage;
      bool hitlWasTriggered = false; // set true if any tool was HITL-blocked

      final effectiveMaxIterations = isGoalMode ? 100 : maxToolIterations;
      final totalToolsLimit = effectiveMaxIterations * 2;
      var totalToolsExecuted = 0;

      while (iterations < effectiveMaxIterations) {
        if (isAborted()) {
          _log.info('Session $sessionId stopped or superseded by user.');
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

        final ontologyContextString = ontologyContext.isNotEmpty
            ? '\n\n$ontologyContext'
            : '';

        const String memoryInstruction =
            '\nIf the [HISTORICAL CONTEXT] or [KNOWLEDGE GRAPH] above is missing or insufficient, use "memory_query" for unstructured text or "ghost_ontology_query" for structured entity relationships.\n'
            'When you use "memory_add" for personal facts, use the category "user_profile". Use "ghost_ontology_assert" to record or update durable structured facts (e.g. WOHNT_IN, ARBEITET_AN, MAG).\n';

        const String vaultInstruction =
            '\n[VAULT CREDENTIALS]\n'
            'Credentials saved in the secure vault are automatically injected into the process environment in ALL CAPS '
            '(e.g., WEATHERAPI_KEY, WEATHERAPI_API_KEY, SPOTIFY_CLIENT_ID).\n'
            'In bash scripts or code, access them directly via environment variables (e.g., \$WEATHERAPI_KEY or os.environ.get("WEATHERAPI_KEY")).\n';

        const String focusInstruction =
            '\n[CRITICAL INSTRUCTION — MANDATORY]\n'
            'The conversation history provided above is ONLY for long-term reference and context for follow-up questions. '
            'The user can already see the entire chat history in their interface.\n'
            '1. Your SOLE task is to answer the SINGLE message marked "### ACTIVE REQUEST" below.\n'
            '2. NEVER repeat, re-answer, or summarize earlier questions or answers from the history.\n'
            '3. Do NOT provide "status updates" or "running summaries" of the chat.\n'
            '4. Treat every turn as a fresh, independent request unless it explicitly refers to a previous detail.\n';

        // Explicit instruction to use tools when needed, but answer greetings directly and prioritize active skills
        const String toolUseInstruction =
            '\n[TOOL USE GUIDELINES — SKILL PRIORITY MANDATE]\n'
            '- MANDATORY SKILL FIRST POLICY (PROGRESSIVE DISCLOSURE): If any skill in [AVAILABLE SKILLS] covers the user\'s request, you MUST FIRST call `ghost_load_skill` with its `skill_name` to load the full instructions, and then execute it (e.g. using bash inside the skill directory or its MCP tools). NEVER bypass an available skill with generic web_search or browser!\n'
            '- For simple greetings, small talk, pleasantries, or general questions, answer directly in natural language without calling tools.\n'
            '- For real-time web information (current news, live prices, sports scores) where NO specialized skill is installed → call web_search or browser.\n'
            '- For reading or writing local files → use read_file / write_file / list_dir.\n'
            '- For running commands, scripts, or skill code → use bash.\n'
            '- For past conversations or user facts → use memory_query.\n'
            'Do NOT call tools unnecessarily when answering simple conversational questions.\n';

        const String hitlSafetyInstruction =
            '\n[SAFETY & HUMAN-IN-THE-LOOP (HITL) POLICY]\n'
            '- Ghost has an automated Human-In-The-Loop security middleware and System-1 risk scoring.\n'
            '- When the user asks you to execute commands, delete files, modify code, or run scripts (even sensitive or dangerous commands like rm, delete, git reset, format, bash execution, crypto transfers):\n'
            '  * ALWAYS invoke the corresponding tool (e.g. bash, delete_file, write_file) instead of refusing or asking for confirmation in natural language text!\n'
            '  * Ghost\'s security middleware will automatically intercept the tool call safely, pause execution, and render interactive YES/NO confirmation buttons in the chat UI.\n'
            '  * DO NOT refuse in text with "Ich kann das aus Sicherheitsgründen nicht ausführen" without invoking the tool — always invoke the tool so the user gets the interactive confirmation dialog.\n'
            '  * Only when a tool returns a "SECURITY ALERT" or "USER REJECTED" error should you explain the block to the user and await their confirmation.\n';

        final goalInstruction = isGoalMode
            ? '\n[AUTONOMOUS GOAL MODE ACTIVE (Google Antigravity 2.0)]\n'
                '1. The user initiated this request with `/goal`. Your active goal is: "$activeGoal"\n'
                '2. You must work autonomously to complete the task fully.\n'
                '3. Do NOT ask the user for confirmation, permission, or clarification. Assume approval for all tool and command executions.\n'
                '4. Do NOT output intermediate questions or requests for feedback. If you encounter a problem, find a workaround using your tools.\n'
                '5. Continue to execute tools and refine your work in subsequent iterations until the task is completely finished.\n'
                '6. Only produce your final response when the goal is fully achieved. Highlight what you did and show verification/testing results.'
            : '';

        final planInstruction = isPlanMode
            ? '\n[STRUCTURED PLANNING MODE ACTIVE (Google Antigravity 2.0)]\n'
                '1. The user initiated this request with `/plan`. Your target for planning is: "$activePlan"\n'
                '2. Your goal is to formulate a comprehensive, high-quality, step-by-step implementation plan and architectural roadmap BEFORE any code or files are modified.\n'
                '3. YOU SHOULD INSPECT the project using read-only tools (read_file, list_dir, web_search, terminal/bash read-only commands) to ensure your plan reflects the real codebase, configurations, and dependencies.\n'
                '4. STRICT READ-ONLY SAFETY: Do NOT modify any existing files, write new source files, run destructive terminal commands, or commit changes during planning mode.\n'
                '5. Structure your plan clearly:\n'
                '   - 🎯 **Objective & Scope**: Definition of done and key requirements.\n'
                '   - 🔍 **Current State Analysis**: Existing architecture, affected files, and dependencies.\n'
                '   - 🏗️ **Architecture & Design Decisions**: Approaches, trade-offs, and design patterns.\n'
                '   - 📋 **Phased Implementation Roadmap**: Concrete numbered steps with exact file paths.\n'
                '   - ⚠️ **Risks & Edge Cases**: What could go wrong and how to mitigate it.\n'
                '   - 🧪 **Verification & Testing Strategy**: Specific tests and validation steps for each phase.\n'
                '   - 📊 **Kanban Breakdown**: You may optionally use `kanban_pipeline` or `kanban_create`/`kanban_subtask` to register these tasks directly on the Kanban board.\n'
                '6. Conclude by inviting the user to review the plan, suggest adjustments, or approve execution (e.g. by replying with `/goal`).'
            : '';

        final workspaceInstruction =
            '\n[ACTIVE WORKSPACE DIRECTORY]: $workspaceDir\n'
            'All local file operations (read_file, write_file, list_dir) and terminal/bash commands are executed within this directory.\n';

        final ontology = memory.ontology;
        final List<SkillOntologySummary> allowedSkillSummaries =
            (ontology != null && ontology.isInitialized)
                ? ontology.getAllowedSkillsForAgent(id)
                : const [];

        final String availableSkillsIndex;
        if (allowedSkillSummaries.isNotEmpty) {
          final indexLines = allowedSkillSummaries
              .map((s) => s.toCompactIndexLine())
              .join('\n');
          availableSkillsIndex =
              '\n\n[AVAILABLE SKILLS — PROGRESSIVE DISCLOSURE]:\n'
              'Only compact skill summaries are shown below to conserve tokens. '
              'Call `ghost_load_skill(skill_name: "<slug>")` BEFORE using any skill to load its full SKILL.md instructions and paths.\n'
              '$indexLines';
        } else if (skills.isNotEmpty && (ontology == null || !ontology.isInitialized)) {
          final fallbackLines = skills.map((s) => '- `$s`').join('\n');
          availableSkillsIndex =
              '\n\n[AVAILABLE SKILLS — PROGRESSIVE DISCLOSURE]:\n'
              'Call `ghost_load_skill(skill_name: "<slug>")` BEFORE using any skill to load its full SKILL.md instructions.\n'
              '$fallbackLines';
        } else {
          availableSkillsIndex = '';
        }

        final dynamicSystemPrompt =
            '$systemPrompt\n\n[SYSTEM: The current date and time is $timeStr]$workspaceInstruction$availableSkillsIndex$contextString$ontologyContextString$memoryInstruction$vaultInstruction$focusInstruction$toolUseInstruction$hitlSafetyInstruction$goalInstruction$planInstruction\n';

        // For local providers (Ollama, vLLM, LM Studio), limit the tool set
        // to core tools only. Small models (2–4B) cannot reliably select from
        // 45+ tool definitions — it overloads their context and causes them to
        // ignore all tools. Core tools cover >90% of real-world use cases.
        const _localCoreTools = {
          'web_search', 'web_fetch',
          'bash', 'terminal',
          'read_file', 'write_file', 'list_dir', 'download_file',
          'memory_add', 'memory_query',
          'ghost_ontology_assert', 'ghost_ontology_query',
          'ghost_load_skill',
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
                inputSchema: (d['input_schema'] is Map)
                    ? (d['input_schema'] as Map).cast<String, dynamic>()
                    : <String, dynamic>{},
              ),
            )
            .where((t) => t.name.isNotEmpty)
            .toList();

        // For pure greetings outside goal and plan modes, skip tools entirely so the model responds instantly
        final activeTools = (isShortGreeting && !isGoalMode && !isPlanMode)
            ? <ToolDefinition>[]
            : (isLocalProvider
                ? allTools.where((t) => _localCoreTools.contains(t.name)).toList()
                : allTools);

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

            // Strip `/goal` or `/plan` prefix if present
            if (cleanContent.startsWith('/goal')) {
              cleanContent = cleanContent.substring(5).trim();
            } else if (cleanContent.startsWith('/plan')) {
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
        bool streamedAny = false;
        try {
          response = await activeProvider.chat(
            messages: processedMessages,
            systemPrompt: dynamicSystemPrompt,
            tools: activeTools,
            onPartialResponse: (chunk) {
              if (isAborted()) return;
              streamedAny = true;
              onPartialResponse?.call(chunk);
            },
          );
          if (isAborted()) {
            _log.info('Session $sessionId aborted during provider chat.');
            _stoppedSessions.remove(sessionId);
            break;
          }
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
          if (!streamedAny && onPartialResponse != null) {
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
              'id': call.id,
              'name': call.name,
              'label': label,
              'summary': summary,
              'arguments': call.arguments,
              if (call.thoughtSignature != null)
                'thought_signature': call.thoughtSignature,
            });

            final result = await _executeToolWithHITL(
              call,
              sessionId,
              toolRegistry,
              activeProvider,
              turnMessages,
              isGoalMode: isGoalMode,
            );

            // Track skills loaded via ghost_load_skill for session-level HITL enforcement
            if (call.name == 'ghost_load_skill' && !result.isError) {
              final loadedSlug = result.metadata['skill_slug'] as String?;
              if (loadedSlug != null && loadedSlug.isNotEmpty) {
                final sessionSkills = _loadedSkillsBySession.putIfAbsent(
                  sessionId,
                  () => {},
                );
                sessionSkills[loadedSlug] = SkillOntologySummary(
                  slug: loadedSlug,
                  name: (result.metadata['skill_name'] as String?) ?? loadedSlug,
                  shortDescription: '',
                  category: (result.metadata['category'] as String?) ?? 'general',
                  requiresHitl:
                      result.metadata['requires_hitl'] as bool? ?? false,
                  securityLevel:
                      (result.metadata['security_level'] as String?) ?? 'standard',
                  dependencies: (result.metadata['dependencies'] as List<dynamic>?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const [],
                );
              }
            }

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

      if (isAborted()) {
        _log.info('Skipping final save for aborted session $sessionId');
        return;
      }

      // --- Final Save ---
      if (contentBuffer.isNotEmpty) {
        bool isHitlPending = hitlWasTriggered;

        // Fallback: If no tool was intercepted directly, but the assistant's text is asking the user for confirmation
        // or refusing to execute without verification, activate HITL pending so YES/NO buttons appear!
        if (!isHitlPending && security.humanInTheLoop && !isGoalMode) {
          final textLower = contentBuffer.toString().toLowerCase();
          final textAsksConfirmation = RegExp(
            r'(sicherheitsgründen|nicht ungeprüft|ungeprüft aus|bitte bestätige|bestätigung|erlaubnis|möchtest du wirklich|soll ich (den|das|die|diesen)|soll ich fortfahren|ausführen möchtest|bist du sicher|do you want to proceed|confirm execution)',
            caseSensitive: false,
          ).hasMatch(textLower);

          if (textAsksConfirmation) {
            if (security.system1Middleware) {
              try {
                final hitlAskScore = await System1Service.instance.noul(
                  premise: contentBuffer.toString(),
                  hypothesis:
                      'The assistant refuses to run an action without confirmation or asks the user for permission to execute a command',
                );
                if (hitlAskScore != null && hitlAskScore >= 0.60) {
                  _log.info(
                    'System-1 detected text-based HITL confirmation request in assistant response (score: $hitlAskScore)',
                  );
                  isHitlPending = true;
                }
              } catch (e) {
                _log.warning('System-1 assistant HITL check error: $e');
                isHitlPending = true;
              }
            } else {
              isHitlPending = true;
            }
          }
        }

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
            if (isHitlPending) 'hitl_pending': true,
          },
        );
      } else if (executedToolSummaries.isNotEmpty) {
        final fallbackMsg = iterations >= effectiveMaxIterations
            ? 'Das maximale Aktionslimit ($effectiveMaxIterations) wurde erreicht, bevor eine Antwort formuliert werden konnte.'
            : 'Aktionen wurden ausgeführt, aber keine Textantwort generiert.';
        onPartialResponse?.call(fallbackMsg);
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'assistant',
          content: fallbackMsg,
          metadata: {
            ...metadata,
            'agentId': id,
            'provider': activeProvider.providerId,
            'model': activeProvider.modelId,
            'tool_calls': executedToolSummaries,
          },
        );
      }

      // --- Async Post-Turn Knowledge Graph Fact Extraction ---
      // Strictly gated by System-1 security middleware to prevent Memory Poisoning.
      final canAutoExtract = security.system1Middleware &&
          !system1SecurityFlagged &&
          !hitlWasTriggered &&
          !isAborted() &&
          !isShortGreeting &&
          !sessionId.startsWith('cron_') &&
          !sessionId.startsWith('run_') &&
          !sessionId.startsWith('auto_') &&
          memory.isOntologyAutoExtractEnabled;

      if (canAutoExtract) {
        final cleanExtractInput = rawPromptText
            .replaceFirst(RegExp(r'^/(goal|plan)\s*'), '')
            .trim();
        if (cleanExtractInput.isNotEmpty) {
          unawaited(
            OntologyExtractor.extractAndAssertFacts(
              userMessage: cleanExtractInput,
              provider: activeProvider,
              ontology: memory.ontology!,
              userConfig: userConfig,
            ),
          );
        }
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
    _sessionRunIds[sessionId] = (_sessionRunIds[sessionId] ?? 0) + 1;
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
    final isCron =
        sessionId.startsWith('cron_') || sessionId.startsWith('auto_');

    bool requiresHitl = false;

    final SkillOntologySummary? hitlSkillContext =
        _resolveHitlSkillContext(call, sessionId);

    // Check if security dictates HITL for this tool (or an ERFORDERT_HITL skill)
    if (!isCron && !isGoalMode) {
      if (security.humanInTheLoop) {
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
          'browser',
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

      if (hitlSkillContext != null && hitlSkillContext.requiresHitl) {
        final enforceForCritical =
            hitlSkillContext.securityLevel == 'critical' &&
            security.level != SecurityLevel.none;
        if (security.humanInTheLoop || enforceForCritical) {
          requiresHitl = true;
          _log.info(
            'Ontology ERFORDERT_HITL triggered for tool ${call.name} '
            '(skill: ${hitlSkillContext.slug}, level: ${hitlSkillContext.securityLevel})',
          );
        }
      }
    }

    // Dynamic System-1 Tool-Payload Risk Scoring:
    // Evaluate full tool arguments (e.g. exact shell command or transfer amounts)
    if (security.system1Middleware && !isCron && !isGoalMode) {
      try {
        final skillTag = hitlSkillContext != null
            ? '[Skill: ${hitlSkillContext.slug}, Policy: ${hitlSkillContext.requiresHitl ? "ERFORDERT_HITL" : "STANDARD"}, Security: ${hitlSkillContext.securityLevel}] '
            : '';
        final toolPayload = '${skillTag}Befehl: ${call.name} ${jsonEncode(call.arguments)}';
        final destructiveRisk = await System1Service.instance.score(
          premise: toolPayload,
          hypothesis: 'Destructive action risk',
        );
        double? capitalRisk;
        if (call.name.contains('payment') ||
            call.name.contains('binance') ||
            call.name.contains('swap') ||
            call.name.contains('wallet')) {
          capitalRisk = await System1Service.instance.score(
            premise: toolPayload,
            hypothesis: 'Liquidation and capital destruction risk',
          );
        }
        final maxRisk = [destructiveRisk ?? 0.0, capitalRisk ?? 0.0]
            .reduce((a, b) => a > b ? a : b);
        if (maxRisk >= 0.65) {
          _log.info(
            'System-1 enforced HITL for ${call.name} (risk score: ${(maxRisk * 100).toStringAsFixed(1)}%)',
          );
          requiresHitl = true;
        }
      } catch (e) {
        _log.warning('System-1 tool payload risk scoring error: $e');
      }
    }

    // Check if autonomous payments are disabled
    if (call.name == 'execute_blockchain_payment' && !autonomousPayments) {
      requiresHitl = true;
    }

    if (requiresHitl) {
      // Check full session history to see if the preceding assistant message requested confirmation
      bool isFollowUpConfirmation = false;
      try {
        final history = await sessionManager.getHistory(sessionId, maxMessages: 10);
        final lastUserIdx = history.lastIndexWhere((m) => m.role == 'user');
        if (lastUserIdx > 0) {
          for (int i = lastUserIdx - 1; i >= 0; i--) {
            final m = history[i];
            if (m.role == 'assistant') {
              if (m.metadata['hitl_pending'] == true ||
                  m.content.contains('SECURITY ALERT') ||
                  m.content.contains('Tool execution blocked') ||
                  m.content.toLowerCase().contains('erlaubnis') ||
                  m.content.toLowerCase().contains('bestätig') ||
                  m.content.toLowerCase().contains('permission') ||
                  m.content.toLowerCase().contains('confirm') ||
                  m.content.toLowerCase().contains('sicherheitsgründen') ||
                  m.content.toLowerCase().contains('nicht ungeprüft')) {
                isFollowUpConfirmation = true;
              }
              break;
            }
          }
        }
      } catch (e) {
        _log.warning('Could not inspect session history for HITL context: $e');
      }

      // Find the last user message in the current turn messages
      Message? lastUser;
      for (var i = turnMessages.length - 1; i >= 0; i--) {
        if (turnMessages[i].role == 'user') {
          lastUser = turnMessages[i];
          break;
        }
      }

      bool isConfirmed = false;
      bool? s1Decision;
      final text = lastUser?.content.trim() ?? '';
      final textLower = text.toLowerCase();

      // Check for explicit refusal/negative keywords
      final negativePattern = RegExp(
        r"\b(nein|no|nicht|stop|halt|cancel|abbruch|abbrechen|block|don'?t|never|verbieten|ablehnen)\b",
        caseSensitive: false,
      );
      final hasNegativeWord = negativePattern.hasMatch(textLower);

      // Check for standalone affirmative/confirmation keywords
      final confirmPattern = RegExp(
        r'^(ja|yes|ok|okay|yep|sure|bestätige|bestätigt|erlaubt|gerne|klar|natürlich|do it|go ahead|proceed|confirm|allow|weiter|mach es|mach das)[\.!]?$',
        caseSensitive: false,
      );
      final hasConfirmKeyword = !hasNegativeWord &&
          (confirmPattern.hasMatch(textLower) ||
              (textLower.length <= 40 &&
                  RegExp(
                    r'\b(ja|yes|bestätige|bestätigt|confirm|go ahead|do it|erlaubt|genehmigt|ausführen)\b',
                    caseSensitive: false,
                  ).hasMatch(textLower)));

      // An action can ONLY be considered for confirmation if:
      // 1) The assistant explicitly requested permission in the preceding turn (isFollowUpConfirmation), OR
      // 2) The user's message is an explicit standalone confirmation keyword (hasConfirmKeyword).
      // Initial task prompts (e.g. "Erstelle bitte eine Datei...") must NEVER auto-confirm!
      final isCandidateForConfirmation =
          isFollowUpConfirmation || hasConfirmKeyword;

      if (isCandidateForConfirmation && lastUser != null && !hasNegativeWord) {
        // If System-1 Middleware is active, evaluate user intent via ModernBERT
        if (security.system1Middleware) {
          try {
            final hitlPayload =
                'Aktion: ${call.name} ${jsonEncode(call.arguments)}. User: ${lastUser.content}';
            final s1Hitl = await System1Service.instance.noul(
              premise: hitlPayload,
              hypothesis: 'The user explicitly confirms and approves the action',
            );
            if (s1Hitl != null) {
              _log.info(
                'System-1 HITL confirmation score: $s1Hitl for user: "${lastUser.content}"',
              );
              if (s1Hitl >= 0.65) {
                s1Decision = true;
              } else if (s1Hitl <= 0.40) {
                // Hard negation / rejection detected!
                s1Decision = false;
              }
            }
          } catch (e) {
            _log.warning('System-1 HITL intent check error: $e');
          }
        }

        if (s1Decision != null) {
          isConfirmed = s1Decision;
        } else {
          isConfirmed = hasConfirmKeyword;
        }
      }

      if (!isConfirmed) {
        _log.info(
          'HITL intercepted tool execution for ${call.name} in session $sessionId '
          '(isFollowUp: $isFollowUpConfirmation, hasConfirmKeyword: $hasConfirmKeyword)',
        );

        final isExplicitRejection =
            isFollowUpConfirmation && (s1Decision == false || hasNegativeWord);

        if (isExplicitRejection) {
          return ToolResult(
            output:
                'USER REJECTED: The user explicitly denied or rejected the execution of "${call.name}".\n'
                'Do NOT attempt to execute this tool again. Acknowledge the user\'s cancellation politely.',
            isError: true,
          );
        }

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

  /// Resolves whether [call] operates within or after loading an `ERFORDERT_HITL`
  /// skill in [sessionId], ensuring ontology HITL policies apply to executed skills.
  SkillOntologySummary? _resolveHitlSkillContext(
    ToolCall call,
    String sessionId,
  ) {
    const nonMutatingReadTools = {
      'ghost_load_skill',
      'list_skills',
      'read_file',
      'read',
      'list_dir',
      'memory_query',
      'memory_search',
      'memory_get',
      'ghost_ontology_query',
      'sessions_list',
      'sessions_history',
      'session_status',
      'kanban_list',
      'kanban_detail',
    };
    if (nonMutatingReadTools.contains(call.name)) {
      return null;
    }

    final argsText = jsonEncode(call.arguments).toLowerCase();
    final ontology = memory.ontology;
    if (ontology != null && ontology.isInitialized) {
      final allowed = ontology.getAllowedSkillsForAgent(id);
      for (final skill in allowed) {
        final slugLower = skill.slug.toLowerCase();
        if (argsText.contains('skills/$slugLower') ||
            argsText.contains('skills\\$slugLower') ||
            argsText.contains('"$slugLower"')) {
          final requiresHitl =
              skill.requiresHitl || ontology.skillRequiresHitl(skill.slug);
          if (requiresHitl) {
            return SkillOntologySummary(
              slug: skill.slug,
              name: skill.name,
              shortDescription: skill.shortDescription,
              category: skill.category,
              requiresHitl: true,
              securityLevel: skill.securityLevel,
              dependencies: skill.dependencies,
            );
          }
        }
      }
    }

    final loaded = _loadedSkillsBySession[sessionId];
    if (loaded != null && loaded.isNotEmpty) {
      SkillOntologySummary? highestHitl;
      for (final skill in loaded.values) {
        final stillHitl = skill.requiresHitl ||
            (ontology != null &&
                ontology.isInitialized &&
                ontology.skillRequiresHitl(skill.slug));
        if (!stillHitl) continue;
        if (highestHitl == null || skill.securityLevel == 'critical') {
          highestHitl = SkillOntologySummary(
            slug: skill.slug,
            name: skill.name,
            shortDescription: skill.shortDescription,
            category: skill.category,
            requiresHitl: true,
            securityLevel: skill.securityLevel,
            dependencies: skill.dependencies,
          );
        }
      }
      if (highestHitl != null) return highestHitl;
    }

    return null;
  }
}
