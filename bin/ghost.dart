// Ghost — CLI entry point.

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'package:ghost/ghost.dart';
import 'package:ghost/gateway/agent_router.dart';
import 'package:ghost/gateway/config_router.dart';
import 'package:ghost/agent/manager.dart';
import 'package:ghost/tools/sessions.dart';
import 'package:ghost/tools/google_workspace.dart';
import 'package:ghost/tools/github.dart';
import 'package:ghost/channels/google_chat.dart';
import 'package:ghost/tools/memory.dart';
import 'package:ghost/tools/browser.dart';
import 'package:ghost/tools/skills.dart';

Future<void> main(List<String> arguments) async {
  print(r''' ██████   ██    ██   ██████    ██████   ████████
██        ██    ██  ██    ██  ██           ██   
██  ████  ████████  ██    ██   ██████      ██   
██    ██  ██    ██  ██    ██        ██     ██   
 ██████   ██    ██   ██████    ██████      ██   
 ''');

  final runner = CommandRunner<void>(
    'ghost',
    '👻 Ghost — Personal AI Assistant',
  )
    ..addCommand(GatewayCommand())
    ..addCommand(ConfigCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(ResetCommand());

  try {
    await runner.run(arguments);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exit(64);
  }
}

// ---------------------------------------------------------------------------
// Gateway command
// ---------------------------------------------------------------------------

final _log = Logger('Ghost.CLI');

class GatewayCommand extends Command<void> {
  GatewayCommand() {
    argParser
      ..addOption('config',
          abbr: 'c',
          help: 'Path to config file',
          defaultsTo: defaultConfigPath())
      ..addOption('workspace',
          abbr: 'w', help: 'Workspace root directory', defaultsTo: '.')
      ..addFlag('verbose',
          abbr: 'v', help: 'Enable verbose logging', defaultsTo: false);
  }

  @override
  String get name => 'gateway';

  @override
  String get description => 'Start the Gateway WebSocket server';

  @override
  Future<void> run() async {
    final results = argResults!;
    final verbose = results.flag('verbose');
    initLogging(verbose: verbose);

    final configPath = results.option('config')!;
    var config = await loadConfig(configPath);

    // State directory setup
    final home = Platform.environment['HOME'] ?? '.';
    final stateDir = p.join(home, '.ghost');
    await Directory(stateDir).create(recursive: true);

    // 1. Initialize Secure Storage System
    Hive.init(stateDir);

    final tokenHash = config.gateway.auth.tokenHash;
    final passwordHash = config.gateway.auth.passwordHash;
    final seedString = tokenHash ?? passwordHash ?? 'ghost-default-session-key';
    final sessionKey =
        Uint8List.fromList(sha256.convert(utf8.encode(seedString)).bytes);

    final storage = HiveSecureStorage(encryptionKey: sessionKey);

    // 2. Overlay encrypted config from Vault (agent, user, identity)
    bool fromVault = false;
    final rawAgent = await storage.get('agent_config');
    if (rawAgent != null) {
      try {
        final json = jsonDecode(rawAgent) as Map<String, dynamic>;
        final agent = AgentConfig.fromJson(json);
        if (agent.model.isNotEmpty || agent.provider.isNotEmpty) {
          config = config.copyWith(agent: agent);
          fromVault = true;
          _log.info('Applied agent config from vault');
        }
      } catch (e) {
        print('⚠️  Failed to load agent config from vault: $e');
      }
    }
    final rawUser = await storage.get('user_config');
    if (rawUser != null) {
      try {
        final json = jsonDecode(rawUser) as Map<String, dynamic>;
        config = config.copyWith(user: UserConfig.fromJson(json));
        _log.info('Applied user config from vault');
      } catch (e) {
        print('⚠️  Failed to load user config from vault: $e');
      }
    }
    final rawIdentity = await storage.get('identity_config');
    if (rawIdentity != null) {
      try {
        final json = jsonDecode(rawIdentity) as Map<String, dynamic>;
        config = config.copyWith(identity: IdentityConfig.fromJson(json));
        _log.info('Applied identity config from vault');
      } catch (e) {
        print('⚠️  Failed to load identity config from vault: $e');
      }
    }
    final rawMemory = await storage.get('memory_config');
    if (rawMemory != null) {
      try {
        final json = jsonDecode(rawMemory) as Map<String, dynamic>;
        final memory = MemoryConfig.fromJson(json);
        config = config.copyWith(memory: memory);
        _log.info('Applied memory config from vault');
      } catch (e) {
        print('⚠️  Failed to load memory config from vault: $e');
      }
    }

    final rawCustomAgents = await storage.get('custom_agents_config');
    if (rawCustomAgents != null) {
      try {
        final list = jsonDecode(rawCustomAgents) as List<dynamic>;
        config = config.copyWith(
          customAgents: list
              .map((a) => CustomAgentConfig.fromJson(a as Map<String, dynamic>))
              .toList(),
        );
        _log.info(
            'Applied ${config.customAgents.length} custom agents from vault');
      } catch (e) {
        print('⚠️  Failed to load custom agents config from vault: $e');
      }
    }

    final rawChannels = await storage.get('channels_config');
    if (rawChannels != null) {
      try {
        final json = jsonDecode(rawChannels) as Map<String, dynamic>;
        config = config.copyWith(channels: ChannelsConfig.fromJson(json));
      } catch (e) {
        print('⚠️  Failed to load channels config from vault: $e');
      }
    }

    final rawTools = await storage.get('tools_config');
    if (rawTools != null) {
      try {
        final json = jsonDecode(rawTools) as Map<String, dynamic>;
        config = config.copyWith(tools: ToolsConfig.fromJson(json));
      } catch (e) {
        print('⚠️  Failed to load tools config from vault: $e');
      }
    }

    final rawSession = await storage.get('session_config');
    if (rawSession != null) {
      try {
        final json = jsonDecode(rawSession) as Map<String, dynamic>;
        config = config.copyWith(session: SessionConfig.fromJson(json));
      } catch (e) {
        print('⚠️  Failed to load session config from vault: $e');
      }
    }

    final rawIntegrations = await storage.get('integrations_config');
    if (rawIntegrations != null) {
      try {
        final json = jsonDecode(rawIntegrations) as Map<String, dynamic>;
        config =
            config.copyWith(integrations: IntegrationsConfig.fromJson(json));
      } catch (e) {
        print('⚠️  Failed to load integrations config from vault: $e');
      }
    }

    if (!fromVault) {
      _log.info('No active agent configuration in vault, using defaults');
    }

    // Workspace: CLI arg > config (vault/json) value > default '.'
    final cliWorkspace = results.option('workspace');
    final workspaceDir = p.absolute(
      (cliWorkspace != null && cliWorkspace != '.')
          ? cliWorkspace
          : (config.agent.workspace?.isNotEmpty == true
              ? config.agent.workspace!
              : '.'),
    );

    // We strictly use the port defined in the loaded configuration file.
    // Dynamic or CLI-overridden ports are no longer permitted per user request.

    // Override verbose
    if (verbose) {
      config = config.copyWith(
        gateway: config.gateway.copyWith(verbose: true),
      );
    }

    // Validate config
    assertConfigValid(config);

    final sessionStore = SessionStore(encryptionKey: sessionKey);
    final sessionManager = SessionManager(store: sessionStore);
    await sessionManager.loadAll();

    // 3. Initialize    // Register tools
    final toolRegistry = ToolRegistry(
      profile: config.tools.profile,
      allow: config.tools.allow,
      deny: config.tools.deny,
    );
    SearchTools.registerAll(toolRegistry);
    SessionTools.registerAll(toolRegistry, sessionStore);
    ExecTools.registerAll(toolRegistry);
    FileSystemTools.registerAll(toolRegistry);
    GithubTools.registerAll(toolRegistry);
    GoogleWorkspaceTools.registerAll(toolRegistry, storage);
    BrowserTools.registerAll(toolRegistry);

    // 4. Initialize AI Provider
    final provider = await ProviderFactory.create(
      model: config.agent.model,
      provider: config.agent.provider,
      storage: storage,
    );

    // 5. Initialize Gateway Server
    final server = GatewayServer(
      config: config.gateway,
      stateDir: stateDir,
      storage: storage,
    );

    // 6. Initialize Agent Manager (heavy components)
    final agentManager = AgentManager(
      config: config,
      sessionManager: sessionManager,
      toolRegistry: toolRegistry,
      storage: storage,
      workspaceDir: workspaceDir,
      stateDir: stateDir,
    );
    MemoryTools.registerAll(toolRegistry, agentManager.memorySystem);
    SkillsTools.registerAll(toolRegistry, agentManager.skillManager);

    agentManager.onSessionUpdated = (sessionId, message) {
      server.broadcast('agent.response', {
        'sessionId': sessionId,
        'message': message.toJson(),
      });
    };
    agentManager.onSessionStream = (sessionId, chunk) {
      server.broadcast('agent.stream', {
        'sessionId': sessionId,
        'chunk': chunk,
      });
    };

    agentManager.skillManager.onSkillsChanged.listen((_) {
      server.broadcast('skills.changed');
    });

    // 7. Initialize Agent Router
    final agentRouter = AgentRouter(
      agentManager: agentManager,
      gateway: server,
      sessionManager: sessionManager,
    );
    agentRouter.register();

    // 7b. Initialize Channel Manager
    final channelManager = ChannelManager(
      agentManager: agentManager,
      sessionManager: sessionManager,
      storage: storage,
      configPath: configPath,
      gateway: server,
    );

    // 7c. Initialize Config Router
    final configRouter = ConfigRouter(
      gateway: server,
      storage: storage,
      configPath: configPath,
      agentManager: agentManager,
      channelManager: channelManager,
    );
    configRouter.register();

    // Start server ASAP so the Flutter app can connect and fetch its token
    await server.start();

    // Always use the bound server port in the active config for this run
    if (server.port != config.gateway.port) {
      _log.warning('Updating config file with new bound port: ${server.port}');
      config = config.copyWith(
        gateway: config.gateway.copyWith(port: server.port),
      );
      await saveConfig(config, configPath);
    }

    // Background: Initialize heavy AI components while the server is already active
    unawaited(agentManager.initialize().then((_) async {
      // Add enabled channels after agent is ready (some might depend on it)
      if (config.channels.telegram.enabled) {
        final botToken = await storage.get('telegram_bot_token') ??
            Env.get('TELEGRAM_BOT_TOKEN');

        if (botToken != null) {
          await channelManager.addChannel(TelegramChannel(
            token: botToken,
            botName: config.channels.telegram.settings['botName'] as String? ??
                'GhostBot',
          ));
        } else {
          // ignore: avoid_print
          print(
              '⚠️  Telegram enabled but token is missing. Set TELEGRAM_BOT_TOKEN or use config set-key.');
        }
      }

      if (config.channels.googleChat.enabled) {
        final googleChatServiceAccountJsonPath = config
            .channels.googleChat.settings['serviceAccountJsonPath'] as String?;
        final googleChatProjectId =
            config.channels.googleChat.settings['projectId'] as String?;
        final googleChatSubscriptionId =
            config.channels.googleChat.settings['subscriptionId'] as String?;

        if (googleChatServiceAccountJsonPath != null &&
            googleChatProjectId != null &&
            googleChatSubscriptionId != null) {
          await channelManager.addChannel(GoogleChatChannel(
            serviceAccountJsonPath: googleChatServiceAccountJsonPath,
            projectId: googleChatProjectId,
            subscriptionId: googleChatSubscriptionId,
          ));
        } else {
          // ignore: avoid_print
          print(
              '⚠️  Google Chat enabled but missing required settings (serviceAccountJsonPath, projectId, subscriptionId).');
        }
      }

      // ignore: avoid_print
      print('👻 Ghost Gateway running on '
          'ws://${config.gateway.bindAddress}:${server.port}');
      // ignore: avoid_print
      print('📂 Workspace: $workspaceDir');
      if (provider.modelId.isNotEmpty) {
        // ignore: avoid_print
        print('🧠 Model: ${provider.displayName} (${provider.modelId})');
      }

      final channelsStatus = channelManager.getStatus();
      if (channelsStatus.isNotEmpty) {
        // ignore: avoid_print
        print(
            '📱 Active Channels: ${channelsStatus.map((c) => c['type']).join(', ')}');
      }
      // ignore: avoid_print
      print('   Press Ctrl+C to stop');
    }).catchError((Object e) {
      // ignore: avoid_print
      print('❌ Background initialization failed: $e');
    }));

    // Handle SIGINT
    ProcessSignal.sigint.watch().listen((_) async {
      // ignore: avoid_print
      print('\n🛑 Shutting down...');
      await server.stop();
      for (final chan in channelManager.getStatus()) {
        await channelManager.removeChannel(chan['type'] as String);
      }
      await agentManager.shutdown();
      exit(0);
    });

    // Keep running
    await Future<void>.delayed(const Duration(days: 365));
  }
}

// ---------------------------------------------------------------------------
// Config command
// ---------------------------------------------------------------------------

class ConfigCommand extends Command<void> {
  ConfigCommand() {
    addSubcommand(ConfigShowCommand());
    addSubcommand(ConfigValidateCommand());
    addSubcommand(ConfigSetTokenCommand());
    addSubcommand(ConfigSetKeyCommand());
  }

  @override
  String get name => 'config';

  @override
  String get description => 'Manage Ghost configuration';
}

class ConfigShowCommand extends Command<void> {
  ConfigShowCommand() {
    argParser.addOption('config', abbr: 'c', defaultsTo: defaultConfigPath());
  }

  @override
  String get name => 'show';

  @override
  String get description => 'Show the current configuration';

  @override
  Future<void> run() async {
    final configPath = argResults!.option('config')!;
    final config = await loadConfig(configPath);
    // ignore: avoid_print
    print(config.toString());
  }
}

class ConfigValidateCommand extends Command<void> {
  ConfigValidateCommand() {
    argParser.addOption('config', abbr: 'c', defaultsTo: defaultConfigPath());
  }

  @override
  String get name => 'validate';

  @override
  String get description => 'Validate the configuration file';

  @override
  Future<void> run() async {
    final configPath = argResults!.option('config')!;
    final config = await loadConfig(configPath);
    final errors = validateConfig(config);

    if (errors.isEmpty) {
      // ignore: avoid_print
      print('✅ Configuration is valid');
    } else {
      // ignore: avoid_print
      print('❌ Configuration errors:');
      for (final error in errors) {
        // ignore: avoid_print
        print('  - $error');
      }
      exit(1);
    }
  }
}

class ConfigSetTokenCommand extends Command<void> {
  ConfigSetTokenCommand() {
    argParser.addOption('config', abbr: 'c', defaultsTo: defaultConfigPath());
  }

  @override
  String get name => 'set-token';

  @override
  String get description => 'Generate and set a new auth token';

  @override
  Future<void> run() async {
    final configPath = argResults!.option('config')!;
    var config = await loadConfig(configPath);

    final authToken = GatewayAuth.generateAuthToken();

    config = config.copyWith(
      gateway: config.gateway.copyWith(
        auth: config.gateway.auth.copyWith(
          mode: AuthMode.token,
          tokenHash: authToken.hash,
        ),
      ),
    );

    await saveConfig(config, configPath);

    // ignore: avoid_print
    print('🔑 New auth token generated:');
    // ignore: avoid_print
    print('   ${authToken.raw}');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('Token hash saved to $configPath');
  }
}

class ConfigSetKeyCommand extends Command<void> {
  ConfigSetKeyCommand() {
    argParser
      ..addOption('config', abbr: 'c', defaultsTo: defaultConfigPath())
      ..addOption('service',
          abbr: 's',
          help: 'anthropic, openai, or telegram',
          allowed: ['anthropic', 'openai', 'telegram'])
      ..addOption('key', abbr: 'k', help: 'The API key / Token');
  }

  @override
  String get name => 'set-key';

  @override
  String get description => 'Securely store an API key for a service';

  @override
  Future<void> run() async {
    final results = argResults!;
    final service = results.option('service');
    final key = results.option('key');

    if (service == null || key == null) {
      // ignore: avoid_print
      print('Usage: ghost config set-key --service <service> --key <key>');
      exit(64);
    }

    final home = Platform.environment['HOME'] ?? '.';
    final stateDir = p.join(home, '.ghost');

    // We need the key to open the vault. In the CLI, we derive it the same way as the Gateway.
    final configPath = results.option('config')!;
    final config = await loadConfig(configPath);
    final tokenHash = config.gateway.auth.tokenHash;
    final passwordHash = config.gateway.auth.passwordHash;
    final sessionKey = Uint8List.fromList(sha256
        .convert(utf8
            .encode(tokenHash ?? passwordHash ?? 'ghost-default-session-key'))
        .bytes);

    Hive.init(stateDir);
    final storage = HiveSecureStorage(encryptionKey: sessionKey);

    final storageKey =
        service == 'telegram' ? 'telegram_bot_token' : '${service}_api_key';

    await storage.set(storageKey, key);
    // ignore: avoid_print
    print('✅ Securely stored $service key in vault');
  }
}

// ---------------------------------------------------------------------------
// Doctor command
// ---------------------------------------------------------------------------

class DoctorCommand extends Command<void> {
  DoctorCommand() {
    argParser.addOption('config', abbr: 'c', defaultsTo: defaultConfigPath());
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check Ghost health and configuration';

  @override
  Future<void> run() async {
    // ignore: avoid_print
    print('🩺 Ghost Doctor\n');

    // Check Dart version
    // ignore: avoid_print
    print('✅ Dart ${Platform.version.split(' ').first}');

    // Check config
    final configPath = argResults!.option('config')!;
    final configFile = File(configPath);
    if (await configFile.exists()) {
      // ignore: avoid_print
      print('✅ Config found: $configPath');

      try {
        final config = await loadConfig(configPath);
        final errors = validateConfig(config);
        if (errors.isEmpty) {
          // ignore: avoid_print
          print('✅ Config validates OK');
        } else {
          // ignore: avoid_print
          print('⚠️  Config has ${errors.length} issue(s):');
          for (final error in errors) {
            // ignore: avoid_print
            print('   - $error');
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('❌ Config error: $e');
      }
    }

    // Check state directory
    final stateDir = Directory(
      p.join(Platform.environment['HOME'] ?? '.', '.ghost'),
    );
    if (await stateDir.exists()) {
      // ignore: avoid_print
      print('✅ State directory: ${stateDir.path}');

      final vaultFile = File(p.join(stateDir.path, 'vault.enc'));
      if (await vaultFile.exists()) {
        // ignore: avoid_print
        print('✅ Secure vault found');
      } else {
        // ignore: avoid_print
        print('ℹ️  Secure vault not initialized');
      }
    }

    // ignore: avoid_print
    print('\n👻 Doctor check complete');
  }
}

// ---------------------------------------------------------------------------
// Reset command
// ---------------------------------------------------------------------------

class ResetCommand extends Command<void> {
  ResetCommand() {
    argParser
      ..addOption('config', abbr: 'c', defaultsTo: defaultConfigPath())
      ..addFlag('force',
          abbr: 'f',
          help: 'Skip confirmation prompt',
          defaultsTo: false,
          negatable: false);
  }

  @override
  String get name => 'reset';

  @override
  String get description =>
      'Factory reset: Deletes all state, configs, and vault.';

  @override
  Future<void> run() async {
    final results = argResults!;
    final force = results.flag('force');
    final configPath = results.option('config')!;

    if (!force) {
      // ignore: avoid_print
      print(
          '⚠️  WARNING: This will delete ALL configuration, your secure vault, and your local database (sessions, avatars).');
      stdout.write('Are you sure you want to continue? (y/N): ');
      final response = stdin.readLineSync();
      if (response == null || response.trim().toLowerCase() != 'y') {
        // ignore: avoid_print
        print('Reset cancelled.');
        return;
      }
    }

    bool backupData = false;
    String? providedToken;
    Map<String, String>? savedSecrets;
    Uint8List? savedUserAvatar;
    Uint8List? savedIdentityAvatar;

    if (!force) {
      stdout.write(
          'Do you want to save the user and main agent configuration and restore them after reset? (y/N): ');
      final backupResponse = stdin.readLineSync();
      if (backupResponse != null &&
          backupResponse.trim().toLowerCase() == 'y') {
        backupData = true;

        // Read EVERYTHING from the encrypted vault
        final home = Platform.environment['HOME'] ?? '.';
        final stateDir = p.join(home, '.ghost');

        final config = await loadConfig(configPath);
        final tokenHash = config.gateway.auth.tokenHash;
        final passwordHash = config.gateway.auth.passwordHash;
        final seedString =
            tokenHash ?? passwordHash ?? 'ghost-default-session-key';
        final sessionKey =
            Uint8List.fromList(sha256.convert(utf8.encode(seedString)).bytes);

        Hive.init(stateDir);
        final backupStorage = HiveSecureStorage(encryptionKey: sessionKey);

        try {
          final keys = await backupStorage.listKeys();
          if (keys.isNotEmpty) {
            savedSecrets = {};
            for (final key in keys) {
              final val = await backupStorage.get(key);
              if (val != null) {
                savedSecrets[key] = val;
              }
            }
            // ignore: avoid_print
            print('✅ All vault secrets (${keys.length}) backed up.');
          }

          // Also back up avatar bytes from Hive
          try {
            Hive.init(stateDir);
            if (!Hive.isBoxOpen('avatars')) {
              await Hive.openBox<Uint8List>('avatars');
            }
            final avatarsBox = Hive.box<Uint8List>('avatars');
            savedUserAvatar = avatarsBox.get('user_avatar');
            savedIdentityAvatar = avatarsBox.get('identity_avatar');
            if (savedUserAvatar != null) {
              // ignore: avoid_print
              print('✅ User avatar backed up from database.');
            }
            if (savedIdentityAvatar != null) {
              // ignore: avoid_print
              print('✅ Identity avatar backed up from database.');
            }
          } catch (e) {
            // ignore: avoid_print
            print('ℹ️  Could not read avatars from database: $e');
          }

          if (savedSecrets != null ||
              savedUserAvatar != null ||
              savedIdentityAvatar != null) {
            // ignore: avoid_print
            print('✅ Successfully captured configuration for restoration.');
          } else {
            // ignore: avoid_print
            print('ℹ️  No data found to backup. Backup skipped.');
            backupData = false;
          }
        } catch (e) {
          // ignore: avoid_print
          print('ℹ️  Could not read vault. Backup skipped.');
          backupData = false;
        }

        if (backupData) {
          stdout.write(
              'Please enter the gateway auth token to use after reset (leave empty to generate a new one): ');
          final tokenInput = stdin.readLineSync()?.trim() ?? '';
          if (tokenInput.isNotEmpty) {
            providedToken = tokenInput;
          }
        }
      }
    }

    // Close Hive before deletion to avoid file locks
    await Hive.close();

    // ignore: avoid_print
    print('\n🗑️  Starting factory reset...');

    // Delete state dir
    final home = Platform.environment['HOME'] ?? '.';
    final stateDir = Directory(p.join(home, '.ghost'));
    if (await stateDir.exists()) {
      try {
        await stateDir.delete(recursive: true);
        // ignore: avoid_print
        print('✅ Deleted state directory (${stateDir.path})');
      } catch (e) {
        // ignore: avoid_print
        print('❌ Failed to delete state directory: $e');
      }
    } else {
      // ignore: avoid_print
      print('ℹ️  State directory did not exist.');
    }

    // Delete config file
    final configFile = File(configPath);
    if (await configFile.exists()) {
      try {
        await configFile.delete();
        // ignore: avoid_print
        print('✅ Deleted configuration file ($configPath)');
      } catch (e) {
        // ignore: avoid_print
        print('❌ Failed to delete configuration file: $e');
      }
    }

    // Recreate config and token
    // ignore: avoid_print
    print('\n✨ Generating new default configuration and token...');
    final config = await loadConfig(configPath);

    ({String raw, String hash})? authToken;
    String? tokenHash;

    if (backupData && providedToken != null) {
      try {
        tokenHash = GatewayAuth.hashToken(providedToken);
        // ignore: avoid_print
        print('✅ Preserved explicit gateway auth token.');
      } catch (e) {
        // Fallback to new if parsing fails somehow
        authToken = GatewayAuth.generateAuthToken();
        tokenHash = authToken.hash;
        // ignore: avoid_print
        print('⚠️  Failed to parse/hash provided token, generated a new one.');
      }
    } else {
      authToken = GatewayAuth.generateAuthToken();
      tokenHash = authToken.hash;
    }

    final newConfig = config.copyWith(
      gateway: config.gateway.copyWith(
        auth: config.gateway.auth.copyWith(
          mode: AuthMode.token,
          tokenHash: tokenHash,
        ),
      ),
    );

    await saveConfig(newConfig, configPath);

    final sessionKey =
        Uint8List.fromList(sha256.convert(utf8.encode(tokenHash)).bytes);

    // Restore ALL data to the new (empty) vault
    if (backupData &&
        (savedSecrets != null ||
            savedUserAvatar != null ||
            savedIdentityAvatar != null)) {
      final home = Platform.environment['HOME'] ?? '.';
      final stateDir = p.join(home, '.ghost');
      await Directory(stateDir).create(recursive: true);

      Hive.init(stateDir);

      if (savedSecrets != null) {
        final newStorage = HiveSecureStorage(encryptionKey: sessionKey);

        // Filter secrets: exclude agent_config and API keys to ensure
        // the Setup Wizard triggers on next run.
        final filteredKeys = <String>[];
        for (final entry in savedSecrets.entries) {
          final key = entry.key;
          if (key == 'agent_config' ||
              key.endsWith('_api_key') ||
              key == 'client_token') {
            continue;
          }
          await newStorage.set(key, entry.value);
          filteredKeys.add(key);
        }

        if (filteredKeys.isNotEmpty) {
          // ignore: avoid_print
          print('✅ Restored vault keys: ${filteredKeys.join(', ')}');
        }
        // ignore: avoid_print
        print('ℹ️  Excluded agent config and API keys to allow Setup Wizard.');
      }

      // Restore avatar bytes back into the new Hive database
      if (savedUserAvatar != null || savedIdentityAvatar != null) {
        try {
          Hive.init(stateDir);
          if (!Hive.isBoxOpen('avatars')) {
            await Hive.openBox<Uint8List>('avatars');
          }
          final avatarsBox = Hive.box<Uint8List>('avatars');
          if (savedUserAvatar != null) {
            await avatarsBox.put('user_avatar', savedUserAvatar);
          }
          if (savedIdentityAvatar != null) {
            await avatarsBox.put('identity_avatar', savedIdentityAvatar);
          }
          // ignore: avoid_print
          print('✅ Restored avatars to new database.');
        } catch (e) {
          // ignore: avoid_print
          print('⚠️  Could not restore avatars to database: $e');
        }
      }
    }

    // ignore: avoid_print
    print('');
    if (authToken != null) {
      // ignore: avoid_print
      print('🔑 NEW GATEWAY AUTH TOKEN:');
      // ignore: avoid_print
      print('   ${authToken.raw}');
    } else {
      // ignore: avoid_print
      print('🔑 GATEWAY AUTH TOKEN HAS BEEN PRESERVED.');
    }
    // ignore: avoid_print
    print('');

    stdout.write('🚀 Do you want to start the gateway now? (y/N): ');
    final startResponse = stdin.readLineSync();
    if (startResponse != null && startResponse.trim().toLowerCase() == 'y') {
      // ignore: avoid_print
      print('\nStarting gateway...\n');

      // Dispatch immediately to gateway command
      final gatewayCommand = GatewayCommand();
      final runner = CommandRunner<void>('runner', 'internal')
        ..addCommand(gatewayCommand);

      // We pass the config path to ensure we load what we just saved.
      await runner.run(['gateway', '--config', configPath]);
    } else {
      // ignore: avoid_print
      print('\nReady! Run `dart bin/ghost.dart gateway` to start.');
    }
  }
}
