// Ghost — File System Tools.

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../tools/registry.dart';

/// Tools for interacting with the file system.
class FileSystemTools {
  FileSystemTools._();

  /// Register all file system tools to the registry.
  static void registerAll(ToolRegistry registry) {
    registry.register(ReadFileTool());
    registry.register(WriteFileTool());
    registry.register(ListDirTool());
    registry.register(DownloadTool());
  }
}

/// Tool to download a file from a URL.
class DownloadTool extends Tool {
  @override
  String get name => 'download_file';

  @override
  String get description => 'Download a file from a URL to the workspace.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The URL to download from.',
          },
          'path': {
            'type': 'string',
            'description':
                'The relative path in the workspace to save the file.',
          },
        },
        'required': ['url', 'path'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      '${input['url']} -> ${input['path']}';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final urlStr = input['url'] as String;
    final relPath = input['path'] as String;
    final file = File(p.join(context.workspaceDir, relPath));

    try {
      final response = await http.get(Uri.parse(urlStr));

      if (response.statusCode != 200) {
        return ToolResult.error(
            'Download failed (${response.statusCode}): ${response.reasonPhrase}');
      }

      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);

      return ToolResult(
        output: 'Successfully downloaded to $relPath',
        metadata: {'bytes': response.bodyBytes.length},
      );
    } catch (e) {
      return ToolResult.error('Download failed: $e');
    }
  }
}

/// Tool to read a file's content.
class ReadFileTool extends Tool {
  @override
  String get name => 'read_file';

  @override
  String get description => 'Read the contents of a file.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'The relative path to the file from the workspace root.',
          },
        },
        'required': ['path'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) => input['path'] as String;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final path = input['path'] as String;
    final file = File(p.join(context.workspaceDir, path));

    if (!await file.exists()) {
      return ToolResult.error('File not found: $path');
    }

    try {
      final content = await file.readAsString();
      return ToolResult(output: content);
    } catch (e) {
      return ToolResult.error('Failed to read file: $e');
    }
  }
}

/// Tool to write content to a file.
class WriteFileTool extends Tool {
  @override
  String get name => 'write_file';

  @override
  String get description => 'Write content to a file (overwrites if exists).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'The relative path to the file.',
          },
          'content': {
            'type': 'string',
            'description': 'The content to write.',
          },
        },
        'required': ['path', 'content'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) => input['path'] as String;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final path = input['path'] as String;
    final content = input['content'] as String;
    final file = File(p.join(context.workspaceDir, path));

    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return ToolResult(output: 'Successfully wrote to $path');
    } catch (e) {
      return ToolResult.error('Failed to write file: $e');
    }
  }
}

/// Tool to list directory contents.
class ListDirTool extends Tool {
  @override
  String get name => 'list_dir';

  @override
  String get description => 'List files and directories in a path.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'The relative path to list (defaults to ".").',
          },
        },
      };

  @override
  String getLogSummary(Map<String, dynamic> input) =>
      input['path'] as String? ?? '.';

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final relPath = input['path'] as String? ?? '.';
    final dir = Directory(p.join(context.workspaceDir, relPath));

    if (!await dir.exists()) {
      return ToolResult.error('Directory not found: $relPath');
    }

    try {
      final entities = await dir.list().toList();
      final items = entities.map((e) {
        final type = e is Directory ? 'dir' : 'file';
        final name = p.basename(e.path);
        return '$type: $name';
      }).join('\n');

      return ToolResult(output: items.isEmpty ? '(empty)' : items);
    } catch (e) {
      return ToolResult.error('Failed to list directory: $e');
    }
  }
}
