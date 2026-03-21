// Ghost — Agent runtime.

import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';

import '../models/message.dart';
import '../models/provider.dart';
import '../sessions/manager.dart';
import '../tools/registry.dart';
import '../config/secure_storage.dart';
import '../infra/errors.dart';
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
    this.maxToolIterations = 30,
    this.workspaceDir = '.',
    this.stateDir = '.ghost',
    this.browserHeadless = true,
  });

  final String id;
  AIModelProvider provider;
  final SessionManager sessionManager;
  final ToolRegistry toolRegistry;
  final SecureStorage storage;
  final MemorySystem memory;
  String systemPrompt;
  final int maxToolIterations;
  String workspaceDir;
  final String stateDir;
  bool browserHeadless;
  final Set<String> _stoppedSessions = {};

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
      // 1. Resolve session history
      final messages =
          await sessionManager.getHistory(sessionId, maxMessages: 20);

      // 2. Start the turn loop (to handle multiple tool calls)
      int iterations = 0;
      final turnMessages = List<Message>.from(messages);

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

      while (iterations < maxToolIterations) {
        if (_stoppedSessions.contains(sessionId)) {
          _log.info('Session $sessionId stopped by user.');
          _stoppedSessions.remove(sessionId);
          break;
        }
        iterations++;
        _log.fine('Iteration $iterations for session $sessionId');

        onActivityUpdate?.call('AI: Processing turn $iterations...');
        // 3. Call model
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

        // 2.5 Query Memory (RAG) — never block chat if this fails
        List<String> memoryContext = [];
        try {
          _log.fine('Automatic memory retrieval for: $content');
          onActivityUpdate?.call('Memory: Searching...');
          memoryContext =
              await memory.query(content, activeProvider: activeProvider);
          if (memoryContext.isNotEmpty) {
            _log.info(
                'Found ${memoryContext.length} relevant memory chunks automatically.');
            onActivityUpdate?.call('Memory: Found context');
          } else {
            onActivityUpdate?.call('Memory: No relevant facts');
          }
        } catch (e) {
          _log.warning('Memory query failed (non-blocking): $e');
          onActivityUpdate?.call('');
        }
        
        // Wait a tiny bit so the user can see the memory status
        await Future<void>.delayed(const Duration(milliseconds: 300));

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

        onActivityUpdate?.call('AI: Waiting for provider...');
        var response = await activeProvider.chat(
          messages: turnMessages,
          systemPrompt: dynamicSystemPrompt,
          tools: activeTools,
        );
        onActivityUpdate?.call('');

        // 4. Handle text content
        if (response.content.isNotEmpty) {
          final preview = response.content.length > 100
              ? '${response.content.substring(0, 100)}...'
              : response.content;
          _log.fine('Model responded ($preview)');
          if (onPartialResponse != null) {
            onPartialResponse(response.content);
          }
        }

        // 5. Check for raw tool calls if native parsing failed
        bool hasToolCalls = response.hasToolCalls;
        List<ToolCall> toolCalls = response.toolCalls;

        if (!hasToolCalls && response.content.contains('{"name"')) {
          onActivityUpdate?.call('AI: Parsing tool calls...');
          _log.fine('Attempting to parse raw JSON tool calls from content...');
          try {
            final regex = RegExp(r'\[\s*\{.*"name".*\}\s*\]', dotAll: true);
            final match = regex.firstMatch(response.content);
            if (match != null) {
              final jsonStr = match.group(0)!;
              final parsed = jsonDecode(jsonStr) as List<dynamic>;
              final parsedCalls = <ToolCall>[];
              for (final item in parsed) {
                if (item is Map<String, dynamic> && item.containsKey('name')) {
                  final name = item['name'] as String;
                  if (!activeTools.any((t) => t.name == name)) {
                    _log.info(
                        'Skipping raw tool call "$name" because it is filtered/unavailable.');
                    continue;
                  }
                  parsedCalls.add(ToolCall(
                    id: 'call_${DateTime.now().millisecondsSinceEpoch}_${parsedCalls.length}',
                    name: name,
                    arguments:
                        (item['arguments'] as Map<String, dynamic>?) ?? {},
                  ));
                }
              }
              if (parsedCalls.isNotEmpty) {
                hasToolCalls = true;
                toolCalls = parsedCalls;
                // Clean the raw JSON out of the user-facing content
                response = response.copyWith(
                  content: response.content.replaceFirst(jsonStr, '').trim(),
                  toolCalls: toolCalls,
                );
                _log.info(
                    'Successfully parsed ${toolCalls.length} raw tool calls.');
              }
            }
          } catch (e) {
            _log.warning('Failed to parse raw tool calls from content: $e');
          }
        }

        // 5b. Final Check
        if (!hasToolCalls) {
          // Final response achieved
          if (response.content.isNotEmpty) {
            await sessionManager.addMessage(
              sessionId: sessionId,
              role: 'assistant',
              content: response.content,
              metadata: {
                ...metadata,
                'agentId': id,
                'provider': activeProvider.providerId,
                'model': activeProvider.modelId,
                'usage': response.usage?.inputTokens != null
                    ? {
                        'input': response.usage!.inputTokens,
                        'output': response.usage!.outputTokens,
                      }
                    : null,
              },
            );
          }
          break;
        }

        // 6. Execute tools
        _state = AgentState.executingTools;
        final toolNames = response.toolCalls.map((tc) => tc.name).join(', ');
        _log.info(
            'Executing ${response.toolCalls.length} tool calls: $toolNames');

        // Add the assistant response (containing tool calls) to history
        final assistantMsg = Message(
          role: 'assistant',
          content: response.content,
          timestamp: DateTime.now(),
          metadata: {
            'tool_calls': response.toolCalls.map((tc) => tc.toJson()).toList(),
          },
        );
        turnMessages.add(assistantMsg);

        for (var i = 0; i < response.toolCalls.length; i++) {
          final call = response.toolCalls[i];
          final progress =
              response.toolCalls.length > 1 ? ' [${i + 1}/${response.toolCalls.length}]' : '';
          try {
            final tool = toolRegistry.getTool(call.name);
            final summary = tool?.getLogSummary(call.arguments);
            final label = tool?.label ?? call.name;
            
            final activity = summary != null && summary.isNotEmpty
                ? '$label: $summary$progress'
                : '$label$progress';
            onActivityUpdate?.call(activity);

            final result = await toolRegistry.execute(
              call.name,
              call.arguments,
              ToolContext(
                sessionId: sessionId,
                agentId: id,
                workspaceDir: workspaceDir,
                stateDir: stateDir,
                activeProvider: activeProvider,
                browserHeadless: browserHeadless,
              ),
            );

            // Add tool result to context
            turnMessages.add(Message(
              role: 'tool',
              content: result.output,
              timestamp: DateTime.now(),
              metadata: {
                'tool_call_id': call.id,
                'tool_name': call.name,
                'is_error': result.isError,
                ...result.metadata,
              },
            ));
          } catch (e) {
            _log.warning('Tool ${call.name} failed: $e');

            // For critical errors (e.g. memory unavailable), break the loop
            // and surface the error directly to the user as an assistant message.
            if (e is ToolError) {
              final errorMsg = e.message;
              await sessionManager.addMessage(
                sessionId: sessionId,
                role: 'assistant',
                content: '⚠️ $errorMsg',
                metadata: {'agentId': id, 'is_error': true},
              );
              // Signal upstream via rethrow so the process stops cleanly.
              rethrow;
            }

            turnMessages.add(Message(
              role: 'tool',
              content: 'Error: $e',
              timestamp: DateTime.now(),
              metadata: {
                'tool_call_id': call.id,
                'tool_name': call.name,
                'is_error': true,
              },
            ));
          }
        }

        _state = AgentState.thinking;
        onActivityUpdate?.call('AI: Integrating results...');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        onActivityUpdate?.call('');
      }

      if (iterations >= maxToolIterations) {
        _log.warning('Max tool iterations reached ($maxToolIterations)');
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
}
