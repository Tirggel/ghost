import 'dart:io';
import 'package:path/path.dart' as p;
import '../tools/registry.dart';

/// Tools for executing processes.
class ExecTools {
  ExecTools._();

  /// Register all execution tools.
  static void registerAll(ToolRegistry registry) {
    registry.register(BashTool());
    registry.register(TerminalTool());
  }
}

/// Tool to run a shell command.
class BashTool extends Tool {
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

      final result = await Process.run(
        Platform.isWindows ? 'cmd' : 'bash',
        Platform.isWindows ? ['/c', finalCommand] : ['-c', finalCommand],
        workingDirectory: workingDir,
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
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isWindows) {
        await Process.start(
          'cmd.exe',
          ['/c', 'start', '"$title"', 'cmd', '/k', commandToRun],
          workingDirectory: workingDir,
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
