// Ghost — CLI entry point.

import 'dart:async';
// ignore_for_file: avoid_print
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
import 'package:ghost/channels/discord.dart';
import 'package:ghost/channels/whatsapp.dart';
import 'package:ghost/channels/slack.dart';
import 'package:ghost/channels/signal.dart';
import 'package:ghost/channels/imessage.dart';
import 'package:ghost/channels/ms_teams.dart';
import 'package:ghost/channels/nextcloud_talk.dart';
import 'package:ghost/channels/matrix.dart';
import 'package:ghost/channels/nostr.dart';
import 'package:ghost/channels/tlon.dart';
import 'package:ghost/channels/zalo.dart';
import 'package:ghost/channels/webchat.dart';
import 'package:ghost/tools/memory.dart';
import 'package:ghost/tools/browser.dart';
import 'package:ghost/tools/skills.dart';
import 'package:ghost/tools/agents.dart';

Future<void> main(List<String> arguments) async {
  print('Ghost — Personal AI Assistant built by aquawitchcode.dev');

  final runner = CommandRunner<void>(
    'ghost',
    '👻 Ghost — Personal AI Assistant built by aquawitchcode.dev',
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

    final consolidatedRes = await _consolidateConfig(config, storage);
    config = consolidatedRes.consolidated;
    final fromVault = consolidatedRes.fromVault;

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
      configPath: configPath,
    );
    MemoryTools.registerAll(toolRegistry, agentManager.memorySystem);
    SkillsTools.registerAll(toolRegistry, agentManager.skillManager);
    AgentsTools.registerAll(toolRegistry, agentManager);

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

    agentManager.onConfigChanged.listen((_) {
      server.broadcast('config.changed');
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

    // 8. Watch for config changes
    watchConfig(configPath, (newConfig) async {
      _log.info('Configuration file changed, reloading...');
      final res = await _consolidateConfig(newConfig, storage);
      server.updateConfig(res.consolidated.gateway);
      await agentManager.updateConfig(res.consolidated);
    });

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
          print(
              '⚠️  Google Chat enabled but missing required settings (serviceAccountJsonPath, projectId, subscriptionId).');
        }
      }

      // Discord
      if (config.channels.discord.enabled) {
        final token = config.channels.discord.settings['token'] as String?;
        final name = config.channels.discord.settings['botName'] as String? ?? 'Ghost';
        if (token != null && token.isNotEmpty) {
          await channelManager.addChannel(DiscordChannel(botToken: token, botName: name));
        } else {
          print('⚠️  Discord enabled but Bot Token is missing.');
        }
      }

      // WhatsApp
      if (config.channels.whatsapp.enabled) {
        final token = config.channels.whatsapp.settings['token'] as String?;
        final phoneNumberId = config.channels.whatsapp.settings['phoneNumberId'] as String?;
        final verifyToken = config.channels.whatsapp.settings['verifyToken'] as String?;
        if (token != null && phoneNumberId != null) {
          await channelManager.addChannel(WhatsAppChannel(
            apiToken: token,
            phoneNumberId: phoneNumberId,
            verifyToken: verifyToken ?? 'ghost_verify',
          ));
        } else {
          print('⚠️  WhatsApp enabled but API Token or Phone Number ID is missing.');
        }
      }

      // Slack
      if (config.channels.slack.enabled) {
        final token = config.channels.slack.settings['token'] as String?;
        final signingSecret = config.channels.slack.settings['signingSecret'] as String?;
        if (token != null && token.isNotEmpty) {
          await channelManager.addChannel(SlackChannel(
            botToken: token,
            signingSecret: signingSecret,
          ));
        } else {
          print('⚠️  Slack enabled but Bot OAuth Token is missing.');
        }
      }

      // Signal
      if (config.channels.signal.enabled) {
        final phone = config.channels.signal.settings['token'] as String?;
        final apiUrl = config.channels.signal.settings['apiUrl'] as String?;
        if (phone != null && apiUrl != null) {
          await channelManager.addChannel(SignalChannel(
            phoneNumber: phone,
            apiUrl: apiUrl,
          ));
        } else {
          print('⚠️  Signal enabled but phone number or API URL is missing.');
        }
      }

      // iMessage (via BlueBubbles)
      if (config.channels.imessage.enabled) {
        final serverUrl = config.channels.imessage.settings['apiUrl'] as String?;
        final password = config.channels.imessage.settings['token'] as String?;
        if (serverUrl != null && password != null) {
          await channelManager.addChannel(IMessageChannel(
            serverUrl: serverUrl,
            serverPassword: password,
          ));
        } else {
          print('⚠️  iMessage enabled but BlueBubbles URL or password is missing.');
        }
      }

      // Microsoft Teams
      if (config.channels.msTeams.enabled) {
        final appId = config.channels.msTeams.settings['apiUrl'] as String?;
        final appPassword = config.channels.msTeams.settings['token'] as String?;
        if (appId != null && appPassword != null) {
          await channelManager.addChannel(MsTeamsChannel(
            appId: appId,
            appPassword: appPassword,
          ));
        } else {
          print('⚠️  MS Teams enabled but App ID or App Password is missing.');
        }
      }

      // Nextcloud Talk
      if (config.channels.nextcloudTalk.enabled) {
        final nextcloudUrl = config.channels.nextcloudTalk.settings['apiUrl'] as String?;
        final credentials = config.channels.nextcloudTalk.settings['token'] as String?;
        final roomToken = config.channels.nextcloudTalk.settings['roomToken'] as String?;
        if (nextcloudUrl != null && credentials != null) {
          await channelManager.addChannel(NextcloudTalkChannel(
            nextcloudUrl: nextcloudUrl,
            basicAuthCredentials: credentials,
            roomToken: roomToken,
          ));
        } else {
          print('⚠️  Nextcloud Talk enabled but URL or credentials are missing.');
        }
      }

      // Matrix
      if (config.channels.matrix.enabled) {
        final homeserverUrl = config.channels.matrix.settings['apiUrl'] as String?;
        final accessToken = config.channels.matrix.settings['token'] as String?;
        final userId = config.channels.matrix.settings['userId'] as String?;
        if (homeserverUrl != null && accessToken != null && userId != null) {
          await channelManager.addChannel(MatrixChannel(
            accessToken: accessToken,
            homeserverUrl: homeserverUrl,
            userId: userId,
          ));
        } else {
          print('⚠️  Matrix enabled but homeserver URL, access token, or user ID is missing.');
        }
      }

      // Nostr
      if (config.channels.nostr.enabled) {
        final relayUrl = config.channels.nostr.settings['apiUrl'] as String?;
        final pubKey = config.channels.nostr.settings['pubKey'] as String?;
        final privKey = config.channels.nostr.settings['token'] as String?;
        if (relayUrl != null && pubKey != null) {
          await channelManager.addChannel(NostrChannel(
            relayUrl: relayUrl,
            publicKeyHex: pubKey,
            privateKeyHex: privKey,
          ));
        } else {
          print('⚠️  Nostr enabled but relay URL or public key is missing.');
        }
      }

      // Tlon / Urbit
      if (config.channels.tlon.enabled) {
        final shipUrl = config.channels.tlon.settings['apiUrl'] as String?;
        final code = config.channels.tlon.settings['token'] as String?;
        final shipName = config.channels.tlon.settings['shipName'] as String?;
        if (shipUrl != null && code != null && shipName != null) {
          await channelManager.addChannel(TlonChannel(
            shipUrl: shipUrl,
            code: code,
            shipName: shipName,
          ));
        } else {
          print('⚠️  Tlon enabled but ship URL, code, or ship name is missing.');
        }
      }

      // Zalo
      if (config.channels.zalo.enabled) {
        final token = config.channels.zalo.settings['token'] as String?;
        final oaId = config.channels.zalo.settings['oaId'] as String?;
        if (token != null && token.isNotEmpty) {
          await channelManager.addChannel(ZaloChannel(
            oaAccessToken: token,
            oaId: oaId,
          ));
        } else {
          print('⚠️  Zalo enabled but OA Access Token is missing.');
        }
      }

      // WebChat (always start if enabled, it uses the gateway's HTTP server)
      if (config.channels.webchat.enabled) {
        final host = config.gateway.bindAddress;
        final port = server.port;
        await channelManager.addChannel(WebChatChannel(
          host: host,
          port: port,
        ));
      }

      print('👻 Ghost Gateway running on '
          'ws://${config.gateway.bindAddress}:${server.port}');
      print('📂 Workspace: $workspaceDir');
      if (provider.modelId.isNotEmpty) {
        print('🧠 Model: ${provider.displayName} (${provider.modelId})');
      }

      final channelsStatus = channelManager.getStatus();
      if (channelsStatus.isNotEmpty) {
        print(
            '📱 Active Channels: ${channelsStatus.map((c) => c['type']).join(', ')}');
      }
      print('   Press Ctrl+C to stop');
    }).catchError((Object e) {
      print('❌ Background initialization failed: $e');
    }));

    // Handle SIGINT
    ProcessSignal.sigint.watch().listen((_) async {
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

  /// Consolidated configuration from disk and vault.
  Future<({GhostConfig consolidated, bool fromVault})> _consolidateConfig(
      GhostConfig config, SecureStorage storage) async {
    var consolidated = config;
    bool fromVault = false;

    // Overlay encrypted config from Vault
    final rawAgent = await storage.get('agent_config');
    if (rawAgent != null) {
      try {
        final json = jsonDecode(rawAgent) as Map<String, dynamic>;
        final agent = AgentConfig.fromJson(json);
        if (agent.model.isNotEmpty || agent.provider.isNotEmpty) {
          consolidated = consolidated.copyWith(agent: agent);
          fromVault = true;
          _log.fine('Applied agent config from vault');
        }
      } catch (e) {
        _log.warning('Failed to load agent config from vault: $e');
      }
    }

    final rawUser = await storage.get('user_config');
    if (rawUser != null) {
      try {
        final json = jsonDecode(rawUser) as Map<String, dynamic>;
        consolidated =
            consolidated.copyWith(user: UserConfig.fromJson(json));
      } catch (_) {}
    }

    final rawIdentity = await storage.get('identity_config');
    if (rawIdentity != null) {
      try {
        final json = jsonDecode(rawIdentity) as Map<String, dynamic>;
        consolidated =
            consolidated.copyWith(identity: IdentityConfig.fromJson(json));
      } catch (_) {}
    }

    final rawMemory = await storage.get('memory_config');
    if (rawMemory != null) {
      try {
        final json = jsonDecode(rawMemory) as Map<String, dynamic>;
        consolidated =
            consolidated.copyWith(memory: MemoryConfig.fromJson(json));
      } catch (_) {}
    }

    final rawCustomAgents = await storage.get('custom_agents_config');
    if (rawCustomAgents != null) {
      try {
        final list = jsonDecode(rawCustomAgents) as List<dynamic>;
        consolidated = consolidated.copyWith(
          customAgents: list
              .map((a) => CustomAgentConfig.fromJson(a as Map<String, dynamic>))
              .toList(),
        );
      } catch (_) {}
    }

    final rawChannels = await storage.get('channels_config');
    if (rawChannels != null) {
      try {
        final json = jsonDecode(rawChannels) as Map<String, dynamic>;
        consolidated =
            consolidated.copyWith(channels: ChannelsConfig.fromJson(json));
      } catch (_) {}
    }

    final rawTools = await storage.get('tools_config');
    if (rawTools != null) {
      try {
        final json = jsonDecode(rawTools) as Map<String, dynamic>;
        consolidated =
            consolidated.copyWith(tools: ToolsConfig.fromJson(json));
      } catch (_) {}
    }

    final rawSession = await storage.get('session_config');
    if (rawSession != null) {
      try {
        final json = jsonDecode(rawSession) as Map<String, dynamic>;
        consolidated =
            consolidated.copyWith(session: SessionConfig.fromJson(json));
      } catch (_) {}
    }

    final rawIntegrations = await storage.get('integrations_config');
    if (rawIntegrations != null) {
      try {
        final json = jsonDecode(rawIntegrations) as Map<String, dynamic>;
        consolidated = consolidated.copyWith(
            integrations: IntegrationsConfig.fromJson(json));
      } catch (_) {}
    }

    return (consolidated: consolidated, fromVault: fromVault);
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
      print('✅ Configuration is valid');
    } else {
      print('❌ Configuration errors:');
      for (final error in errors) {
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

    print('🔑 New auth token generated:');
    print('   ${authToken.raw}');
    print('');
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
    print('🩺 Ghost Doctor\n');

    // Check Dart version
    print('✅ Dart ${Platform.version.split(' ').first}');

    // Check config
    final configPath = argResults!.option('config')!;
    final configFile = File(configPath);
    if (await configFile.exists()) {
      print('✅ Config found: $configPath');

      try {
        final config = await loadConfig(configPath);
        final errors = validateConfig(config);
        if (errors.isEmpty) {
          print('✅ Config validates OK');
        } else {
          print('⚠️  Config has ${errors.length} issue(s):');
          for (final error in errors) {
            print('   - $error');
          }
        }
      } catch (e) {
        print('❌ Config error: $e');
      }
    }

    // Check state directory
    final stateDir = Directory(
      p.join(Platform.environment['HOME'] ?? '.', '.ghost'),
    );
    if (await stateDir.exists()) {
      print('✅ State directory: ${stateDir.path}');

      final vaultFile = File(p.join(stateDir.path, 'vault.enc'));
      if (await vaultFile.exists()) {
        print('✅ Secure vault found');
      } else {
        print('ℹ️  Secure vault not initialized');
      }
    }

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
      print(
          '⚠️  WARNING: This will delete ALL configuration, your secure vault, and your local database (sessions, avatars).');
      stdout.write('Are you sure you want to continue? (y/N): ');
      final response = stdin.readLineSync();
      if (response == null || response.trim().toLowerCase() != 'y') {
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
              print('✅ User avatar backed up from database.');
            }
            if (savedIdentityAvatar != null) {
              print('✅ Identity avatar backed up from database.');
            }
          } catch (e) {
            print('ℹ️  Could not read avatars from database: $e');
          }

          if (savedSecrets != null ||
              savedUserAvatar != null ||
              savedIdentityAvatar != null) {
            print('✅ Successfully captured configuration for restoration.');
          } else {
            print('ℹ️  No data found to backup. Backup skipped.');
            backupData = false;
          }
        } catch (e) {
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

    print('\n🗑️  Starting factory reset...');

    // Delete state dir
    final home = Platform.environment['HOME'] ?? '.';
    final stateDir = Directory(p.join(home, '.ghost'));
    if (await stateDir.exists()) {
      try {
        await stateDir.delete(recursive: true);
        print('✅ Deleted state directory (${stateDir.path})');
      } catch (e) {
        print('❌ Failed to delete state directory: $e');
      }
    } else {
      print('ℹ️  State directory did not exist.');
    }

    // Delete config file
    final configFile = File(configPath);
    if (await configFile.exists()) {
      try {
        await configFile.delete();
        print('✅ Deleted configuration file ($configPath)');
      } catch (e) {
        print('❌ Failed to delete configuration file: $e');
      }
    }

    // Recreate config and token
    print('\n✨ Generating new default configuration and token...');
    final config = await loadConfig(configPath);

    ({String raw, String hash})? authToken;
    String? tokenHash;

    if (backupData && providedToken != null) {
      try {
        tokenHash = GatewayAuth.hashToken(providedToken);
        print('✅ Preserved explicit gateway auth token.');
      } catch (e) {
        // Fallback to new if parsing fails somehow
        authToken = GatewayAuth.generateAuthToken();
        tokenHash = authToken.hash;
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
      security: const SecurityConfig(
        level: SecurityLevel.none,
        humanInTheLoop: false,
        promptHardening: false,
        restrictNetwork: false,
        promptAnalyzers: false,
      ),
    );

    await saveConfig(newConfig, configPath);
    print('🔓 Security settings reset to level "none" (all disabled).');

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
          print('✅ Restored vault keys: ${filteredKeys.join(', ')}');
        }
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
          print('✅ Restored avatars to new database.');
        } catch (e) {
          print('⚠️  Could not restore avatars to database: $e');
        }
      }
    }

    print('');
    if (authToken != null) {
      print('🔑 NEW GATEWAY AUTH TOKEN:');
      print('   ${authToken.raw}');
    } else {
      print('🔑 GATEWAY AUTH TOKEN HAS BEEN PRESERVED.');
    }
    print('');

    stdout.write('🚀 Do you want to start the gateway now? (y/N): ');
    final startResponse = stdin.readLineSync();
    if (startResponse != null && startResponse.trim().toLowerCase() == 'y') {
      print('\nStarting gateway...\n');

      // Dispatch immediately to gateway command
      final gatewayCommand = GatewayCommand();
      final runner = CommandRunner<void>('runner', 'internal')
        ..addCommand(gatewayCommand);

      // We pass the config path to ensure we load what we just saved.
      await runner.run(['gateway', '--config', configPath]);
    } else {
      print('\nReady! Run `dart bin/ghost.dart gateway` to start.');
    }
  }
}
