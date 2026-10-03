#!/usr/bin/env dart
// Ghost — Standalone ACP (Agent Client Protocol) Entrypoint.
// Can be spawned by Google Antigravity CLI (agy), Zed, and IDEs as a subprocess.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:hive_ce/hive.dart';

import 'package:ghost/engine.dart';

Future<void> main(List<String> arguments) async {
  // Direct all logs to stderr so stdout remains strictly valid JSON-RPC
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stderr.writeln('[${record.level.name}] ${record.loggerName}: ${record.message}');
  });

  final parser = ArgParser()
    ..addOption('workspace', abbr: 'w', defaultsTo: '.', help: 'Workspace root directory')
    ..addOption(
      'guardrails',
      abbr: 'g',
      defaultsTo: 'reviewMode',
      allowed: ['reviewMode', 'autoAccept'],
      help: 'Autopilot execution mode (reviewMode or autoAccept)',
    )
    ..addFlag('ws', defaultsTo: false, help: 'Run as a WebSocket server instead of STDIO')
    ..addOption('port', abbr: 'p', defaultsTo: '3001', help: 'Port for WebSocket server')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage help');

  final results = parser.parse(arguments);
  if (results['help'] as bool) {
    stderr.writeln('Ghost ACP Server (Agent Client Protocol for Antigravity & Zed)');
    stderr.writeln(parser.usage);
    exit(0);
  }

  final workspace = p.canonicalize(results['workspace'] as String);
  final guardrailMode = (results['guardrails'] as String) == 'autoAccept'
      ? AutopilotMode.autoAccept
      : AutopilotMode.reviewMode;
  final runAsWs = results['ws'] as bool;
  final wsPort = int.tryParse(results['port'] as String) ?? 3001;

  stderr.writeln('Initializing Ghost ACP engine in: $workspace (Guardrails: ${guardrailMode.name})...');

  // 1. Resolve State Dir & Storage
  final stateDir = p.join(workspace, '.ghost');
  await Directory(stateDir).create(recursive: true);
  Hive.init(stateDir);

  // Storage for headless CLI run
  final storage = MemorySecureStorage();

  // 2. Load Config or Defaults
  final configPath = p.join(stateDir, 'config.json');
  final config = await loadConfig(configPath);

  // 3. Setup Session Key & Stores
  final seedString = config.gateway.auth.tokenHash ?? 'ghost-acp-session-key';
  final sessionKey = Uint8List.fromList(sha256.convert(utf8.encode(seedString)).bytes);
  final sessionStore = SessionStore(encryptionKey: sessionKey);
  final sessionManager = SessionManager(store: sessionStore);
  await sessionManager.loadAll();

  // 4. Setup Tool Registry
  final toolRegistry = ToolRegistry(
    profile: config.tools.profile,
    allow: config.tools.allow,
    deny: config.tools.deny,
  );

  SearchTools.registerAll(toolRegistry);
  SessionTools.registerAll(toolRegistry, sessionStore);
  ExecTools.registerAll(toolRegistry, storage);
  FileSystemTools.registerAll(toolRegistry);
  GithubTools.registerAll(toolRegistry);
  VaultTools.registerAll(toolRegistry, storage);

  // 5. Setup Task Manager
  final taskStore = TaskStore(stateDir: stateDir);
  final taskManager = TaskManager(store: taskStore);
  await taskManager.initialize();
  KanbanTools.registerAll(toolRegistry, taskManager);

  // 6. Setup Agent Manager
  final agentManager = AgentManager(
    config: config,
    sessionManager: sessionManager,
    toolRegistry: toolRegistry,
    storage: storage,
    workspaceDir: workspace,
    stateDir: stateDir,
    configPath: configPath,
    taskManager: taskManager,
  );
  await agentManager.initialize();

  // 7. Setup Context Provider (Workspace RAG)
  final contextProvider = AcpContextProvider(
    ragEngine: agentManager.memorySystem.rag,
  );

  // 8. Instantiate ACP Server
  final acpServer = AcpServer(
    agentManager: agentManager,
    taskManager: taskManager,
    contextProvider: contextProvider,
    defaultAutopilotMode: guardrailMode,
  );

  if (runAsWs) {
    // Run WebSocket transport
    final wsHandler = webSocketHandler((webSocket) {
      AcpWebSocketClient(
        server: acpServer,
        channel: webSocket,
        clientId: 'ws_${DateTime.now().millisecondsSinceEpoch}',
      );
    });

    final server = await shelf_io.serve(wsHandler, '127.0.0.1', wsPort);
    stderr.writeln('Ghost ACP WebSocket server running at ws://127.0.0.1:${server.port}');
    await Completer<void>().future; // keep alive
  } else {
    // Run STDIO transport
    final stdioTransport = AcpStdioTransport(server: acpServer);
    stdioTransport.start();

    // Keep process alive until stdin closes
    ProcessSignal.sigint.watch().listen((_) async {
      await stdioTransport.stop();
      exit(0);
    });

    await stdioTransport.done;
    exit(0);
  }
}
