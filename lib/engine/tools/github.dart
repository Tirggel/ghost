// Ghost — GitHub Tools.

import 'dart:io';
import '../tools/registry.dart';

/// Tools for interacting with GitHub and the `gh` CLI.
class GithubTools {
  GithubTools._();

  /// Register all GitHub tools to the registry.
  static void registerAll(ToolRegistry registry) {
    registry.register(GhCliTool());
  }
}

/// Tool to execute the GitHub CLI (`gh`).
class GhCliTool extends Tool {
  @override
  String get name => 'github';

  @override
  String get description => 'Execute a command using the GitHub CLI (`gh`). '
      'Useful for creating or viewing pull requests, issues, repositories, etc. '
      'The `gh` CLI must be installed and authenticated on the host machine.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'args': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'The arguments to pass to the `gh` CLI (e.g., ["issue", "list", "--repo", "owner/repo"]).',
          },
        },
        'required': ['args'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      (input['args'] as List<dynamic>).join(' ');

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final argsDynamic = input['args'] as List<dynamic>;
    final args = argsDynamic.cast<String>();

    try {
      final result = await Process.run(
        'gh',
        args,
        workingDirectory: context.workspaceDir,
      );

      final output = [
        if (result.stdout.toString().isNotEmpty) result.stdout.toString(),
        if (result.stderr.toString().isNotEmpty) 'Error/Log:\n${result.stderr}',
      ].join('\n').trim();

      return ToolResult(
        output: output.isEmpty ? '(no output)' : output,
        isError: result.exitCode != 0,
        metadata: {'exitCode': result.exitCode},
      );
    } catch (e) {
      if (e is ProcessException && e.errorCode == 2) {
        return const ToolResult.error(
            'The `gh` CLI tool is not installed or not in PATH.');
      }
      return ToolResult.error('Failed to execute `gh` CLI: $e');
    }
  }
}
