import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../engine.dart';
import 'package:hive_ce/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_storage.dart';
import 'secure_storage_impl.dart';
import 'migration_service.dart';

final _log = Logger('Ghost.InternalGateway');

class InternalGatewayManager {
  factory InternalGatewayManager() => _instance;
  InternalGatewayManager._internal();
  static final InternalGatewayManager _instance = InternalGatewayManager._internal();

  AgentManager? _agentManager;
  GatewayServer? _server;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int? get port => _server?.port;

  static const _enabledKey = 'internal_gateway_enabled';

  Future<void> initialize() async {
    // 1. Run migration first
    final migration = MigrationService();
    await migration.run();
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true; // Default to enabled
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    
    if (enabled && !_isRunning) {
      await start();
    } else if (!enabled && _isRunning) {
      await stop();
    }
  }

  Future<void> start() async {
    if (_isRunning) return;

    try {
      final stateDir = await PlatformStorage.getGhostDir();
      final configPath = await PlatformStorage.getConfigPath();
      
      _log.info('Starting internal gateway...');
      _log.info('State Dir: $stateDir');
      _log.info('Config Path: $configPath');

      // 1. Initialize Storage
      final storage = FlutterSecureStorageImpl();
      Hive.init(stateDir);

      // 2. Load Config (Merge JSON with Vault)
      final configFile = File(configPath);
      final isFreshStart = !await configFile.exists();
      var config = await loadConfig(configPath);
      
      // Load overrides from Vault
      final userJson = await storage.get('user_config');
      if (userJson != null) {
        config = config.copyWith(user: UserConfig.fromJson(jsonDecode(userJson) as Map<String, dynamic>));
      }
      
      final identityJson = await storage.get('identity_config');
      if (identityJson != null) {
        config = config.copyWith(identity: IdentityConfig.fromJson(jsonDecode(identityJson) as Map<String, dynamic>));
      }
      
      final agentJson = await storage.get('agent_config');
      if (agentJson != null) {
        config = config.copyWith(agent: AgentConfig.fromJson(jsonDecode(agentJson) as Map<String, dynamic>));
      }
      
      final channelsJson = await storage.get('channels_config');
      if (channelsJson != null) {
        config = config.copyWith(channels: ChannelsConfig.fromJson(jsonDecode(channelsJson) as Map<String, dynamic>));
      }
      
      final customAgentsJson = await storage.get('custom_agents_config');
      if (customAgentsJson != null) {
        final List<dynamic> list = jsonDecode(customAgentsJson) as List<dynamic>;
        config = config.copyWith(
          customAgents: list.map((e) => CustomAgentConfig.fromJson(e as Map<String, dynamic>)).toList(),
        );
      }
      
      final toolsJson = await storage.get('tools_config');
      if (toolsJson != null) {
        config = config.copyWith(tools: ToolsConfig.fromJson(jsonDecode(toolsJson) as Map<String, dynamic>));
      }

      final integrationsJson = await storage.get('integrations_config');
      if (integrationsJson != null) {
        config = config.copyWith(integrations: IntegrationsConfig.fromJson(jsonDecode(integrationsJson) as Map<String, dynamic>));
      }

      // 3. Auto-provision token and handle fresh start (Monolith UX)
      if (isFreshStart || config.gateway.auth.tokenHash == null) {
        _log.info('Detected fresh start or missing auth — ensuring clean slate...');
        
        if (isFreshStart) {
          // If the file was deleted, wipe essential config from the vault
          // to ensure a true "Factory Reset" experience.
          await storage.remove('agent_config');
          await storage.remove('user_config');
          await storage.remove('identity_config');
          await storage.remove('custom_agents_config');
          await storage.remove('channels_config');
          _log.info('Cleared essential vault keys for fresh start.');
        }

        final tokenData = GatewayAuth.generateAuthToken();
        
        config = config.copyWith(
          gateway: config.gateway.copyWith(
            auth: config.gateway.auth.copyWith(
              tokenHash: tokenData.hash,
              mode: AuthMode.token,
            ),
          ),
        );
        
        // Save back to file
        await saveConfig(config, configPath);
        
        // Sync raw token to secure storage so UI can find it
        await storage.set('auth_token', tokenData.raw);
        _log.info('Fresh auth token generated and synced to vault.');
      }

      // 4. Setup Session Key
      final tokenHash = config.gateway.auth.tokenHash;
      final passwordHash = config.gateway.auth.passwordHash;
      final seedString = tokenHash ?? passwordHash ?? 'ghost-default-session-key';
      final sessionKey = Uint8List.fromList(sha256.convert(utf8.encode(seedString)).bytes);

      // 4. Initialize Core Components
      final sessionStore = SessionStore(encryptionKey: sessionKey);
      final sessionManager = SessionManager(store: sessionStore);
      await sessionManager.loadAll();

      final toolRegistry = ToolRegistry(
        profile: config.tools.profile,
        allow: config.tools.allow,
        deny: config.tools.deny,
      );
      
      // Register tools (Replicating bin/ghost.dart registration)
      SearchTools.registerAll(toolRegistry);
      SessionTools.registerAll(toolRegistry, sessionStore);
      ExecTools.registerAll(toolRegistry);
      FileSystemTools.registerAll(toolRegistry);
      GithubTools.registerAll(toolRegistry);
      GoogleWorkspaceTools.registerAll(toolRegistry, storage);
      MicrosoftGraphTools.registerAll(toolRegistry, storage);
      
      // Browser tools might be disabled on some platforms (e.g. mobile)
      if (!kIsWeb && (p.extension(Platform.resolvedExecutable) != '.js')) {
         BrowserTools.registerAll(toolRegistry);
      }

      // 5. Initialize Server & Manager
      _server = GatewayServer(
        config: config.gateway,
        stateDir: stateDir,
        storage: storage,
        onRestart: () async {
          _log.info('Full system restart triggered via Gateway RPC...');
          await stop();
          await Future<void>.delayed(const Duration(milliseconds: 1000));
          await start();
        },
      );

      _agentManager = AgentManager(
        config: config,
        sessionManager: sessionManager,
        toolRegistry: toolRegistry,
        storage: storage,
        workspaceDir: config.agent.workspace ?? '.',
        stateDir: stateDir,
        configPath: configPath,
      );
      
      MemoryTools.registerAll(toolRegistry, _agentManager!.memorySystem);
      SkillsTools.registerAll(toolRegistry, _agentManager!.skillManager);
      AgentsTools.registerAll(toolRegistry, _agentManager!);

      // 6. Wire up events
      _agentManager!.onSessionUpdated = (sessionId, message) {
        _server?.broadcast('agent.response', {
          'sessionId': sessionId,
          'message': message.toJson(),
        });
      };
      _agentManager!.onSessionStream = (sessionId, chunk) {
        _server?.broadcast('agent.stream', {
          'sessionId': sessionId,
          'chunk': chunk,
        });
      };

      _agentManager!.skillManager.onSkillsChanged.listen((_) {
        _server?.broadcast('skills.changed');
      });

      _agentManager!.onConfigChanged.listen((_) {
        _server?.broadcast('config.changed');
      });

      // 7. Routers
      AgentRouter(
        agentManager: _agentManager!,
        gateway: _server!,
        sessionManager: sessionManager,
      ).register();

      final channelManager = ChannelManager(
        agentManager: _agentManager!,
        sessionManager: sessionManager,
        storage: storage,
        configPath: configPath,
        gateway: _server!,
      );

      ConfigRouter(
        gateway: _server!,
        storage: storage,
        configPath: configPath,
        agentManager: _agentManager!,
        channelManager: channelManager,
      ).register();

      // 8. Start
      await _server!.start();
      unawaited(_agentManager!.initialize());
      unawaited(channelManager.initialize()); // Start enabled channels

      _isRunning = true;
      _log.info('Internal gateway started on ws://localhost:${_server!.port}');

    } catch (e, stack) {
      _log.severe('Failed to start internal gateway: $e', e, stack);
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    _log.info('Stopping internal gateway...');
    try {
      await _server?.stop();
      await _agentManager?.shutdown();
      _server = null;
      _agentManager = null;
      _isRunning = false;
      _log.info('Internal gateway stopped.');
    } catch (e) {
      _log.severe('Error stopping internal gateway: $e');
    }
  }
}
