// Ghost — Agent Manager

import 'dart:async';
import 'dart:convert';
import 'package:cron/cron.dart';
import 'package:logging/logging.dart';

import '../config/config.dart';
import '../config/io.dart';
import '../config/secure_storage.dart';
import '../models/message.dart';
import '../sessions/manager.dart';
import '../sessions/session.dart';
import '../tools/registry.dart';
import 'agent.dart';
import 'memory.dart';
import 'rag_memory.dart';
import 'providers/factory.dart';
import 'skills.dart';
import 'memory_system.dart';

final _log = Logger('Ghost.AgentManager');

/// Callback when a session is updated by an agent.
typedef SessionUpdateCallback = void Function(
    String sessionId, Message message);

/// Callback for streaming agent responses.
typedef SessionStreamCallback = void Function(String sessionId, String chunk);

/// Manages multiple agents (the default one + custom cron agents)
class AgentManager {
  AgentManager({
    required this.config,
    required this.sessionManager,
    required this.toolRegistry,
    required this.storage,
    required this.workspaceDir,
    required this.stateDir,
    this.configPath,
  }) {
    skillManager = SkillManager(stateDir: stateDir);
    memoryEngine = MemoryEngine(
      config: config.memory,
      storage: storage,
      stateDir: stateDir,
    );
    ragMemoryEngine = RAGMemoryEngine(
      config: config.memory,
      storage: storage,
      stateDir: stateDir,
    );
    memorySystem = MemorySystem(standard: memoryEngine, rag: ragMemoryEngine);
  }

  GhostConfig config;
  final SessionManager sessionManager;
  final ToolRegistry toolRegistry;
  final SecureStorage storage;
  String workspaceDir;
  final String stateDir;
  final String? configPath;

  final _configChangedController = StreamController<void>.broadcast();
  Stream<void> get onConfigChanged => _configChangedController.stream;
  
  void notifyConfigChanged() {
    _configChangedController.add(null);
  }

  /// Callbacks for notifications
  SessionUpdateCallback? onSessionUpdated;
  SessionStreamCallback? onSessionStream;

  late Agent defaultAgent;
  late final SkillManager skillManager;
  late final MemoryEngine memoryEngine;
  late final RAGMemoryEngine ragMemoryEngine;
  late final MemorySystem memorySystem;
  final Map<String, Agent> _customAgents = {};
  final Map<String, ScheduledTask> _cronTasks = {};

  final _cron = Cron();

  /// Initialize default agent and all custom agents.
  Future<void> initialize() async {
    // 1. Initialize default AI provider
    final defaultProvider = await ProviderFactory.create(
      model: config.agent.model,
      provider: config.agent.provider,
      storage: storage,
    );

    // 1.5. Initialize MemoryEngine
    await memoryEngine.initialize(
      agentModel: config.agent.model,
      agentProvider: config.agent.provider,
    );
    await ragMemoryEngine.initialize();

    // 1.6. Initialize SkillManager
    await skillManager.initialize();

    // 2. Initialize default agent
    defaultAgent = Agent(
      id: 'default-agent',
      provider: defaultProvider,
      sessionManager: sessionManager,
      toolRegistry: toolRegistry,
      storage: storage,
      memory: memorySystem,
      systemPrompt: config.buildSystemPrompt(
        workspaceDir: workspaceDir,
        skillsContext:
            await skillManager.buildSkillContext(config.agent.skills),
      ),
      workspaceDir: workspaceDir,
      stateDir: stateDir,
      browserHeadless: config.tools.browserHeadless,
    );

    // 3. Initialize custom agents
    await reloadCustomAgents(config.customAgents);
  }

  /// Reload the list of custom agents (stops old crons, starts new ones)
  Future<void> reloadCustomAgents(List<CustomAgentConfig> agentConfigs) async {
    // Stop all current tasks
    for (final task in _cronTasks.values) {
      await task.cancel();
    }
    _cronTasks.clear();
    _customAgents.clear();

    for (final agentConfig in agentConfigs) {
      try {
        final provider = await ProviderFactory.create(
          model: agentConfig.model ?? config.agent.model,
          provider: agentConfig.provider ?? config.agent.provider,
          storage: storage,
        );

        final finalPrompt = config.buildSystemPrompt(
          workspaceDir: workspaceDir,
          skillsContext:
              await skillManager.buildSkillContext(agentConfig.skills),
        );

        final agent = Agent(
          id: agentConfig.id,
          provider: provider,
          sessionManager: sessionManager,
          toolRegistry: toolRegistry,
          storage: storage,
          memory: memorySystem,
          systemPrompt: agentConfig.systemPrompt.isNotEmpty
              ? '${agentConfig.systemPrompt}\n\n$finalPrompt'
              : finalPrompt,
          workspaceDir: workspaceDir,
          stateDir: stateDir,
          browserHeadless: config.tools.browserHeadless,
          shouldSendChatHistory: agentConfig.shouldSendChatHistory,
        );

        _customAgents[agentConfig.id] = agent;
        _log.info(
            'Initialized custom agent ${agentConfig.name} (${agentConfig.id})');

        // Schedule cron if provided and enabled
        if (agentConfig.enabled &&
            agentConfig.cronSchedule != null &&
            agentConfig.cronSchedule!.isNotEmpty) {
          try {
            final task = _cron
                .schedule(Schedule.parse(agentConfig.cronSchedule!), () async {
              _log.info('Running scheduled task for agent ${agentConfig.name}');
              await _runCronTask(agent, agentConfig);
            });
            _cronTasks[agentConfig.id] = task;
            _log.info(
                'Scheduled cron for ${agentConfig.name} at ${agentConfig.cronSchedule}');
          } catch (e) {
            _log.severe('Failed to schedule cron for ${agentConfig.name}: $e');
          }
        }
      } catch (e) {
        _log.severe(
            'Failed to initialize custom agent ${agentConfig.name}: $e');
      }
    }
  }

  Future<void> _runCronTask(Agent agent, CustomAgentConfig agentConfig) async {
    try {
      // Create or get a system session for this cron job
      final sessionId = 'cron_${agentConfig.id}';
      final Session session = sessionManager.getSession(sessionId) ??
          sessionManager.createSession(
            id: sessionId,
            channelType: 'system',
            peerId: 'cron',
          );
      session.agentName = '${agentConfig.name} Agent';

      // Build cron task message with skill reminder if skills are present
      String cronMessage = agentConfig.cronMessage;
      if (agentConfig.skills.isNotEmpty) {
        cronMessage +=
            '\n\nIMPORTANT: Use your available skills to complete this task.';
      }

      // Add user message to history
      await sessionManager.addMessage(
        sessionId: session.id,
        role: 'user',
        content: cronMessage,
        metadata: {
          'channelType': 'system',
          'senderId': 'cron',
          'agentId': agentConfig.id,
          'agentName': '${agentConfig.name} Agent',
        },
      );

      // Trigger agent processing in the background
      await agent.processMessage(
        sessionId: session.id,
        content: cronMessage,
        onPartialResponse: (chunk) {
          onSessionStream?.call(session.id, chunk);
        },
      );

      // Notify completion
      if (onSessionUpdated != null && session.history.isNotEmpty) {
        onSessionUpdated!(session.id, session.history.last);
      }
    } catch (e) {
      _log.severe('Error running cron task for ${agentConfig.name}: $e');
      
      final errorStr = e.toString().toLowerCase();
      String errorMessage = '⚠️ Agent failed: $e';
      
      if (errorStr.contains('429') || errorStr.contains('too many requests') || errorStr.contains('rate limit')) {
        errorMessage = '⚠️ Rate limit exceeded: $e\n\n💡 Tipp: Versuche einen anderen Provider oder ein anderes Modell zu wählen.\n\n🚦 Agent wurde automatisch pausiert, um wiederholte Fehler zu vermeiden.';
        
        // Auto-pause the custom agent
        final agentsList = List<CustomAgentConfig>.from(config.customAgents);
        final index = agentsList.indexWhere((a) => a.id == agentConfig.id);
        if (index != -1) {
          agentsList[index] = agentConfig.copyWith(enabled: false);
          // Fire and forget save so we don't block
          unawaited(saveCustomAgents(agentsList));
          _log.info('Auto-paused custom agent ${agentConfig.name} due to rate limits.');
        }
      }

      try {
        final sessionId = 'cron_${agentConfig.id}';
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'error',
          content: errorMessage,
          metadata: {
            'is_error': true,
          },
        );
        
        final session = sessionManager.getSession(sessionId);
        if (onSessionUpdated != null && session != null && session.history.isNotEmpty) {
          onSessionUpdated!(sessionId, session.history.last);
        }
      } catch (innerErr) {
        _log.severe('Failed to log cron error to session: $innerErr');
      }
    }
  }

  /// Updates the config and refreshes the system prompts of all managed agents.
  Future<void> updateConfig(GhostConfig newConfig) async {
    config = newConfig;

    // 1. Refresh default agent provider
    defaultAgent.provider = await ProviderFactory.create(
      model: config.agent.model,
      provider: config.agent.provider,
      storage: storage,
    );

    defaultAgent.workspaceDir = config.agent.workspace ?? workspaceDir;
    workspaceDir = defaultAgent.workspaceDir;
    defaultAgent.systemPrompt = config.buildSystemPrompt(
      workspaceDir: workspaceDir,
      skillsContext: await skillManager.buildSkillContext(config.agent.skills),
    );
    defaultAgent.browserHeadless = config.tools.browserHeadless;

    // 2. Refresh memory engine config
    memoryEngine.config = config.memory;
    await memoryEngine.initialize(
      agentModel: config.agent.model,
      agentProvider: config.agent.provider,
    );
    ragMemoryEngine.updateConfig(config.memory);
    await ragMemoryEngine.initialize();

    // 3. Refresh custom agents (prompts & providers)
    for (final agentConfig in config.customAgents) {
      final agent = _customAgents[agentConfig.id];
      if (agent != null) {
        // Refresh provider for custom agent as well
        agent.provider = await ProviderFactory.create(
          model: agentConfig.model ?? config.agent.model,
          provider: agentConfig.provider,
          storage: storage,
        );

        final finalPrompt = config.buildSystemPrompt(
          workspaceDir: workspaceDir,
          skillsContext:
              await skillManager.buildSkillContext(agentConfig.skills),
        );

        agent.workspaceDir = workspaceDir;
        agent.systemPrompt = agentConfig.systemPrompt.isNotEmpty
            ? '${agentConfig.systemPrompt}\n\n$finalPrompt'
            : finalPrompt;
        agent.browserHeadless = config.tools.browserHeadless;
        agent.shouldSendChatHistory = agentConfig.shouldSendChatHistory;
      }
    }
    _log.info('Updated config, providers, and system prompts for all agents');
  }
  
  /// Persist custom agents to secure storage and ghost.json
  Future<void> saveCustomAgents(List<CustomAgentConfig> agents) async {
    final jsonList = agents.map((a) => a.toJson()).toList();
    await storage.set('custom_agents_config', jsonEncode(jsonList));
    
    if (configPath != null) {
      final currentConfig = await loadConfig(configPath!);
      await saveConfig(currentConfig.copyWith(customAgents: agents), configPath!);
    }
    
    // Refresh local config and reload crons
    config = config.copyWith(customAgents: agents);
    await reloadCustomAgents(agents);
    
    notifyConfigChanged();
  }

  /// Get a specific agent, or the default one
  Agent getAgent(String? agentId) {
    if (agentId == null || agentId == 'default-agent') {
      return defaultAgent;
    }
    return _customAgents[agentId] ?? defaultAgent;
  }

  Future<void> shutdown() async {
    for (final task in _cronTasks.values) {
      await task.cancel();
    }
    await _cron.close();
  }

  /// Stop processing for a session.
  void stop(String sessionId) {
    defaultAgent.stop(sessionId);
    for (final agent in _customAgents.values) {
      agent.stop(sessionId);
    }
  }

  /// Clears the specified memory type.
  Future<void> clearMemory(String type) async {
    if (type == 'standard') {
      await memoryEngine.clear();
    } else if (type == 'rag') {
      await ragMemoryEngine.clear();
    } else {
      _log.warning('Unknown memory type to clear: $type');
    }
  }
}
