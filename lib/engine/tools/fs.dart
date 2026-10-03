// Ghost — File System Tools.

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../tools/registry.dart';

/// Tools for interacting with the file system.
class FileSystemTools {
  FileSystemTools._();

  /// Resolve and validate that a path is strictly inside the workspace directory.
  /// Prevents directory traversal attacks (e.g. "../" or absolute system paths).
  static String? resolveSafePath(String workspaceDir, String inputPath) {
    if (inputPath.trim().isEmpty) return null;
    final canonicalWorkspace = p.canonicalize(workspaceDir);
    final resolved = p.isAbsolute(inputPath)
        ? p.canonicalize(inputPath)
        : p.canonicalize(p.join(canonicalWorkspace, inputPath));

    if (resolved != canonicalWorkspace && !p.isWithin(canonicalWorkspace, resolved)) {
      return null;
    }
    return resolved;
  }

  /// Register all file system tools to the registry.
  static void registerAll(ToolRegistry registry) {
    registry.register(ReadFileTool());
    registry.register(WriteFileTool());
    registry.register(ListDirTool());
    registry.register(DownloadTool());
    registry.register(ApplyPatchTool());
    registry.register(EditFileTool());
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
    final safePath = FileSystemTools.resolveSafePath(context.workspaceDir, relPath);
    if (safePath == null) {
      return ToolResult.error('Access denied: Path "$relPath" is outside the workspace directory.');
    }
    final file = File(safePath);

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
    final safePath = FileSystemTools.resolveSafePath(context.workspaceDir, path);
    if (safePath == null) {
      return ToolResult.error('Access denied: Path "$path" is outside the workspace directory.');
    }
    final file = File(safePath);

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
    final safePath = FileSystemTools.resolveSafePath(context.workspaceDir, path);
    if (safePath == null) {
      return ToolResult.error('Access denied: Path "$path" is outside the workspace directory.');
    }
    final content = input['content'] as String;
    final file = File(safePath);

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
    final safePath = FileSystemTools.resolveSafePath(context.workspaceDir, relPath);
    if (safePath == null) {
      return ToolResult.error('Access denied: Path "$relPath" is outside the workspace directory.');
    }
    final dir = Directory(safePath);

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

/// Tool to apply a search/replace diff patch or unified patch to a file.
class ApplyPatchTool extends Tool {
  @override
  String get name => 'apply_patch';

  @override
  String get description =>
      'Apply a patch or search/replace block to a file. '
      'Can be in unified diff format or using SEARCH/REPLACE block markers:\n'
      '<<<<<<< SEARCH\n'
      'old content\n'
      '=======\n'
      'new content\n'
      '>>>>>>> REPLACE';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'The relative path to the file to patch.',
          },
          'patch': {
            'type': 'string',
            'description': 'The patch or search/replace block.',
          },
        },
        'required': ['path', 'patch'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) => input['path'] as String;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final relPath = input['path'] as String;
    final patch = input['patch'] as String;
    final safePath =
        FileSystemTools.resolveSafePath(context.workspaceDir, relPath);
    if (safePath == null) {
      return ToolResult.error(
          'Access denied: Path "$relPath" is outside workspace directory.');
    }

    final file = File(safePath);
    if (!await file.exists()) {
      return ToolResult.error('File not found: $relPath');
    }

    try {
      final originalContent = await file.readAsString();

      // Check for SEARCH/REPLACE block format
      final searchReplacePattern = RegExp(
        r'<<<<<<<\s*SEARCH\r?\n([\s\S]*?)\r?\n=======\r?\n([\s\S]*?)\r?\n>>>>>>>\s*REPLACE',
        multiLine: true,
      );

      final matches = searchReplacePattern.allMatches(patch).toList();
      if (matches.isNotEmpty) {
        String updated = originalContent;
        int appliedCount = 0;

        for (final match in matches) {
          final searchBlock = match.group(1)!;
          final replaceBlock = match.group(2)!;

          if (!updated.contains(searchBlock)) {
            return ToolResult.error(
                'Patch failed: Could not find target SEARCH block in $relPath.');
          }

          updated = updated.replaceFirst(searchBlock, replaceBlock);
          appliedCount++;
        }

        await file.writeAsString(updated);
        return ToolResult(
          output: 'Successfully applied $appliedCount patch block(s) to $relPath.',
          metadata: {'blocksApplied': appliedCount, 'path': relPath},
        );
      }

      // Simple unified diff parsing (fallback)
      final lines = patch.split('\n');
      final searchLines = <String>[];
      final replaceLines = <String>[];

      for (final line in lines) {
        if (line.startsWith('-') && !line.startsWith('---')) {
          searchLines.add(line.substring(1));
        } else if (line.startsWith('+') && !line.startsWith('+++')) {
          replaceLines.add(line.substring(1));
        } else if (line.startsWith(' ')) {
          searchLines.add(line.substring(1));
          replaceLines.add(line.substring(1));
        }
      }

      if (searchLines.isNotEmpty) {
        final searchBlock = searchLines.join('\n');
        final replaceBlock = replaceLines.join('\n');

        if (originalContent.contains(searchBlock)) {
          final updated =
              originalContent.replaceFirst(searchBlock, replaceBlock);
          await file.writeAsString(updated);
          return ToolResult(
            output: 'Successfully applied unified diff to $relPath.',
            metadata: {'path': relPath},
          );
        }
      }

      return ToolResult.error(
          'Could not parse or match patch for $relPath. Ensure SEARCH block matches exact lines.');
    } catch (e) {
      return ToolResult.error('Failed to apply patch: $e');
    }
  }
}

/// Tool to perform an exact contiguous string or block replacement in a file.
class EditFileTool extends Tool {
  @override
  String get name => 'edit_file';

  @override
  String get description =>
      'Edit a file by replacing a contiguous target string with replacement text.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'The relative path to the file to edit.',
          },
          'target_content': {
            'type': 'string',
            'description': 'The exact character sequence to be replaced.',
          },
          'replacement_content': {
            'type': 'string',
            'description': 'The replacement string.',
          },
          'allow_multiple': {
            'type': 'boolean',
            'description':
                'Whether to replace multiple occurrences (default: false).',
          },
        },
        'required': ['path', 'target_content', 'replacement_content'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) => input['path'] as String;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final relPath = input['path'] as String;
    final targetContent = input['target_content'] as String;
    final replacementContent = input['replacement_content'] as String;
    final allowMultiple = input['allow_multiple'] as bool? ?? false;

    final safePath =
        FileSystemTools.resolveSafePath(context.workspaceDir, relPath);
    if (safePath == null) {
      return ToolResult.error(
          'Access denied: Path "$relPath" is outside workspace directory.');
    }

    final file = File(safePath);
    if (!await file.exists()) {
      return ToolResult.error('File not found: $relPath');
    }

    try {
      final content = await file.readAsString();
      if (!content.contains(targetContent)) {
        return ToolResult.error(
            'Target content not found in $relPath. Please verify the exact lines.');
      }

      final occurrences = targetContent.allMatches(content).length;
      if (occurrences > 1 && !allowMultiple) {
        return ToolResult.error(
            'Found $occurrences occurrences of target content in $relPath, but allow_multiple was false.');
      }

      final updated = allowMultiple
          ? content.replaceAll(targetContent, replacementContent)
          : content.replaceFirst(targetContent, replacementContent);

      await file.writeAsString(updated);
      return ToolResult(
        output:
            'Successfully edited $relPath (replaced $occurrences occurrence(s)).',
        metadata: {'path': relPath, 'occurrences': occurrences},
      );
    } catch (e) {
      return ToolResult.error('Failed to edit file: $e');
    }
  }
}
