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
import '../models/provider.dart';

final _log = Logger('Ghost.AgentManager');

/// Callback when a session is updated by an agent.
typedef SessionUpdateCallback = void Function(
    String sessionId, Message message);

/// Callback for streaming agent responses.
typedef SessionStreamCallback = void Function(String sessionId, String chunk);

/// Callback when a session is renamed.
typedef SessionRenameCallback = void Function(String sessionId, String title);

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
  SessionRenameCallback? onSessionRenamed;

  late Agent defaultAgent;
  late final SkillManager skillManager;
  late final MemoryEngine memoryEngine;
  late final RAGMemoryEngine ragMemoryEngine;
  late final MemorySystem memorySystem;
  final Map<String, Agent> _customAgents = {};
  final Map<String, ScheduledTask> _cronTasks = {};
  StreamSubscription<void>? _skillsSubscription;

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
      security: config.security,
    );

    // 3. Initialize custom agents
    await reloadCustomAgents(config.customAgents);

    // 4. Listen for skill changes to rebuild prompts
    _skillsSubscription = skillManager.onSkillsChanged.listen((_) {
      _log.info('Skills changed, rebuilding system prompts...');
      updateConfig(config);
    });
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
          security: config.security,
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

      // Auto-rename if this is a cron session with no fitting title yet
      if (session.title == null ||
          session.title!.isEmpty ||
          session.title!.contains('cron_') ||
          session.title == agentConfig.cronMessage) {
        unawaited(autoRenameSession(session, agent));
      }

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
    defaultAgent.security = config.security;

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
        agent.security = config.security;
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
    await _skillsSubscription?.cancel();
    for (final task in _cronTasks.values) {
      await task.cancel();
    }
    await _cron.close();
    await memoryEngine.close();
    await ragMemoryEngine.close();
  }

  /// Stop processing for a session.
  void stop(String sessionId) {
    defaultAgent.stop(sessionId);
    for (final agent in _customAgents.values) {
      agent.stop(sessionId);
    }
  }

  /// Automatically generate a title for a session using the LLM.
  Future<void> autoRenameSession(Session session, Agent agent) async {
    try {
      _log.info('Auto-renaming session ${session.id}...');

      // Resolve the session-specific provider
      AIModelProvider activeProvider = agent.provider;
      if (session.model != null || session.provider != null) {
        activeProvider = await ProviderFactory.create(
          model: session.model ?? agent.provider.modelId,
          provider: session.provider ?? agent.provider.providerId,
          storage: agent.storage,
        );
      }

      // Create a prompt for summarization
      // Localized prompts for titling
      final lang = config.user.language.split('_').first.toLowerCase();
      final prompts = {
        'de': {
          'system':
              'Du bist ein Assistent für Sitzungstitel. Antworte AUSSCHLIESSLICH auf Deutsch.\nBeispiele:\n"Wie ist das Wetter?" -> Wetterabfrage\n"Schreibe Python Code" -> Python Programmierung',
          'user':
              'Erstelle einen sehr kurzen deutschen Titel (max. 5 Wörter) für dieses Gespräch. Antworte NUR mit dem Titel auf DEUTSCH.',
        },
        'fr': {
          'system':
              'Vous êtes un assistant de titrage. Répondez EXCLUSIVEMENT en français.\nExemples:\n"Quel temps fait-il ?" -> Météo\n"Écris du code Python" -> Programmation Python',
          'user':
              'Créez un titre très court en français (max. 5 mots). Répondez UNIQUEMENT avec le titre en FRANÇAIS.',
        },
        'es': {
          'system':
              'Eres un asistente de titulación. Responde EXCLUSIVAMENTE en español.\nEjemplos:\n"¿Cómo está el clima?" -> Consulta del clima\n"Escribe código Python" -> Programación Python',
          'user':
              'Crea un título muy corto en español (máximo 5 palabras). Responde SOLO con el título en ESPAÑOL.',
        },
        'en': {
          'system':
              'You are a session titling assistant. Respond ONLY in English.\nExamples:\n"How is the weather?" -> Weather inquiry\n"Write Python code" -> Python programming',
          'user':
              'Create a very short title (max 5 words). Respond ONLY with the title in ENGLISH.',
        },
      };

      final selectedPrompt = prompts[lang] ?? prompts['en']!;
      final summaryPrompt = selectedPrompt['user']!;
      final titlingSystemPrompt = selectedPrompt['system']!;

      // Strip metadata from history to avoid passing incompatible tool_calls
      // back to the provider (which causes 400 Bad Request on some APIs).
      final messages = session.history
          .where((m) => m.role != 'system')
          .map((m) => Message(
                role: m.role,
                content: m.content,
                timestamp: m.timestamp,
              ))
          .toList();

      if (messages.isEmpty) return;

      messages.add(Message(
        role: 'user',
        content: summaryPrompt,
        timestamp: DateTime.now(),
      ));

      final response = await activeProvider.chat(
        messages: messages,
        systemPrompt: titlingSystemPrompt,
      );

      if (response.content.isNotEmpty) {
        var title = response.content.trim();
        // Strip common prefixes and quotes
        title = title.replaceAll('"', '').replaceAll("'", '');
        title = title
            .replaceFirst(RegExp(r'^(Titel|Title|Sujet|Título):\s*',
                caseSensitive: false), '')
            .trim();

        session.title = title;
        _log.info('Session ${session.id} renamed to: $title');

        // Persist title via a system message
        await sessionManager.addMessage(
          sessionId: session.id,
          role: 'system',
          content: 'session_rename',
          metadata: {'title': title},
        );

        // Notify broadcast
        onSessionRenamed?.call(session.id, title);
      }
    } catch (e) {
      _log.warning('Auto-rename failed for session ${session.id}: $e');

      // Fallback to first user message if LLM generation fails
      try {
        if ((session.title == null || session.title!.contains('cron_')) &&
            session.history.isNotEmpty) {
          final firstUserMsg = session.history.firstWhere(
            (m) => m.role == 'user',
            orElse: () => session.history.first,
          );

          String fallbackTitle = firstUserMsg.content.trim();
          // Remove newlines if any
          fallbackTitle = fallbackTitle.replaceAll('\n', ' ');
          if (fallbackTitle.length > 30) {
            fallbackTitle = '${fallbackTitle.substring(0, 30)}...';
          }

          if (fallbackTitle.isNotEmpty) {
            session.title = fallbackTitle;
            _log.info(
                'Session ${session.id} renamed to fallback: $fallbackTitle');

            await sessionManager.addMessage(
              sessionId: session.id,
              role: 'system',
              content: 'session_rename',
              metadata: {'title': fallbackTitle},
            );

            onSessionRenamed?.call(session.id, fallbackTitle);
          }
        }
      } catch (fallbackError) {
        _log.warning('Fallback auto-rename also failed: $fallbackError');
      }
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
