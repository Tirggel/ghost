import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/secure_storage.dart';
import '../tools/registry.dart';

/// Tools for executing processes.
class ExecTools {
  ExecTools._();

  /// Register all execution tools.
  static void registerAll(ToolRegistry registry, [SecureStorage? storage]) {
    registry.register(BashTool(storage: storage));
    registry.register(TerminalTool(storage: storage));
  }

  /// Builds a map of environment variables by extracting external service API keys from the secure vault.
  /// Internal sensitive tokens (auth_token, client_token, internal configurations, crypto keys)
  /// are strictly blocked to prevent credential leakage.
  static Future<Map<String, String>> buildVaultEnvironment(SecureStorage? storage) async {
    final env = Map<String, String>.from(Platform.environment);
    if (storage == null) return env;

    const blockedKeys = {
      'auth_token',
      'client_token',
      'agent_config',
      'custom_agents_config',
      'migration_v1_done',
      'payment_card_transactions',
      'wallet_private_key',
      'wallet_seed',
      'wallet_mnemonic',
      'binance_secret_key',
    };

    try {
      final keys = await storage.listKeys();
      for (final key in keys) {
        final lowerKey = key.toLowerCase();

        // 1. Block internal vault config keys (starting with _ or in blocked set)
        if (lowerKey.startsWith('_') || blockedKeys.contains(lowerKey)) {
          continue;
        }

        // 2. Export external service credentials & any user vault key
        final value = await storage.get(key);
        if (value != null && value.isNotEmpty) {
          final cleanKey = key.startsWith('vault_') ? key.substring(6) : key;
          final envKey = cleanKey.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toUpperCase();
          env[envKey] = value;

          // Provide common aliases for API keys:
          // e.g. WEATHERAPI_API_KEY -> WEATHERAPI_KEY, WEATHERAPI, WEATHER_API_KEY
          if (envKey.endsWith('_API_KEY')) {
            final base = envKey.substring(0, envKey.length - 8);
            env['${base}_KEY'] = value;
            env[base] = value;
          } else if (envKey.endsWith('_KEY')) {
            final base = envKey.substring(0, envKey.length - 4);
            env['${base}_API_KEY'] = value;
            env[base] = value;
          } else {
            env['${envKey}_API_KEY'] = value;
            env['${envKey}_KEY'] = value;
          }
        }
      }
    } catch (e) {
      // Ignore storage errors, return default env
    }
    return env;
  }
}

/// Tool to run a shell command.
class BashTool extends Tool {
  BashTool({this.storage});
  final SecureStorage? storage;

  @override
  String get name => 'bash';

  @override
  String get description => 'Execute a shell command.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The shell command to execute.',
          },
        },
        'required': ['command'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) {
    final cmd = (input['command'] as String).replaceAll('\n', ' ');
    return cmd;
  }

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final command = input['command'] as String;
    final workingDir = context.workspaceDir;

    try {
      String finalCommand = command;

      // 1. Detect Python Venv
      final venvPath = p.join(workingDir, '.venv');
      if (await Directory(venvPath).exists()) {
        final activatePath = Platform.isWindows
            ? p.join(venvPath, 'Scripts', 'activate.bat')
            : p.join(venvPath, 'bin', 'activate');
        
        if (await File(activatePath).exists()) {
          finalCommand = Platform.isWindows 
            ? 'call "$activatePath" && $finalCommand'
            : 'source "$activatePath" && $finalCommand';
        }
      }

      // 2. Detect Node Modules
      final nodeModulesBin = p.join(workingDir, 'node_modules', '.bin');
      if (await Directory(nodeModulesBin).exists()) {
        final separator = Platform.isWindows ? ';' : ':';
        final envPrefix = Platform.isWindows
            ? 'set "PATH=$nodeModulesBin$separator%PATH%" && '
            : 'export PATH="$nodeModulesBin$separator\$PATH" && ';
        finalCommand = '$envPrefix$finalCommand';
      }

      // 3. Inject Vault API Keys
      final vaultEnv = await ExecTools.buildVaultEnvironment(storage);

      final result = await Process.run(
        Platform.isWindows ? 'cmd' : 'bash',
        Platform.isWindows ? ['/c', finalCommand] : ['-c', finalCommand],
        workingDirectory: workingDir,
        environment: vaultEnv,
      );

      final output = [
        if (result.stdout.toString().isNotEmpty) result.stdout.toString(),
        if (result.stderr.toString().isNotEmpty) 'Error:\n${result.stderr}',
      ].join('\n').trim();

      return ToolResult(
        output: output.isEmpty ? '(no output)' : output,
        isError: result.exitCode != 0,
        metadata: {'exitCode': result.exitCode},
      );
    } catch (e) {
      return ToolResult.error('Process execution failed: $e');
    }
  }
}

/// Tool to run a command in a visible terminal window.
class TerminalTool extends Tool {
  TerminalTool({this.storage});
  final SecureStorage? storage;

  @override
  String get name => 'terminal';

  @override
  String get description =>
      'Execute a command in a new VISIBLE terminal window. '
      'Only use this tool when the user explicitly says they want to open a terminal, '
      'see the output in a window, or run it in bash/cmd themselves. '
      'Do NOT use this for background execution or after saving a script automatically.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The command to execute in the terminal.',
          },
          'title': {
            'type': 'string',
            'description': 'Optional title for the terminal window.',
          },
        },
        'required': ['command'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) {
    final cmd = (input['command'] as String).replaceAll('\n', ' ');
    return cmd;
  }

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final command = input['command'] as String;
    final title = input['title'] as String? ?? 'Ghost Terminal';
    final workingDir = context.workspaceDir;

    try {
      String commandToRun = command;

      // 1. Detect Python Venv
      final venvPath = p.join(workingDir, '.venv');
      if (await Directory(venvPath).exists()) {
        final activatePath = Platform.isWindows
            ? p.join(venvPath, 'Scripts', 'activate.bat')
            : p.join(venvPath, 'bin', 'activate');
        
        if (await File(activatePath).exists()) {
          commandToRun = Platform.isWindows 
            ? 'call "$activatePath" && $commandToRun'
            : 'source "$activatePath" && $commandToRun';
        }
      }

      // 2. Detect Node Modules
      final nodeModulesBin = p.join(workingDir, 'node_modules', '.bin');
      if (await Directory(nodeModulesBin).exists()) {
        final separator = Platform.isWindows ? ';' : ':';
        final envPrefix = Platform.isWindows
            ? 'set "PATH=$nodeModulesBin$separator%PATH%" && '
            : 'export PATH="$nodeModulesBin$separator\$PATH" && ';
        commandToRun = '$envPrefix$commandToRun';
      }

      // 3. Inject Vault API Keys
      final vaultEnv = await ExecTools.buildVaultEnvironment(storage);

      if (Platform.isLinux) {
        // Construct the wrapper script to keep terminal open
        final fullCommand =
            '$commandToRun; echo; echo "---------------------------------------"; '
            'echo "Task finished. Press Enter to close window..."; read';

        // Try to find a terminal emulator
        final terminals = [
          'x-terminal-emulator',
          'gnome-terminal',
          'konsole',
          'xfce4-terminal',
          'xterm'
        ];
        String? foundTerminal;

        for (final t in terminals) {
          final which = await Process.run('which', [t]);
          if (which.exitCode == 0) {
            foundTerminal = t;
            break;
          }
        }

        if (foundTerminal == null) {
          return const ToolResult.error(
              'No supported terminal emulator found.');
        }

        List<String> args;
        if (foundTerminal == 'gnome-terminal') {
          args = ['--title', title, '--', 'bash', '-c', fullCommand];
        } else if (foundTerminal == 'konsole') {
          args = ['--title', title, '-e', 'bash', '-c', fullCommand];
        } else {
          // generic for x-terminal-emulator / xterm
          args = ['-e', 'bash -c "$fullCommand"'];
        }

        await Process.start(
          foundTerminal,
          args,
          workingDirectory: workingDir,
          environment: vaultEnv,
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isWindows) {
        await Process.start(
          'cmd.exe',
          ['/c', 'start', '"$title"', 'cmd', '/k', commandToRun],
          workingDirectory: workingDir,
          environment: vaultEnv,
          mode: ProcessStartMode.detached,
        );
      } else {
        return const ToolResult.error(
            'Terminal tool not supported on this platform.');
      }

      return ToolResult(
        output: 'Terminal window opened executing: $command',
        metadata: {'status': 'launched'},
      );
    } catch (e) {
      return ToolResult.error('Failed to launch terminal: $e');
    }
  }
}
