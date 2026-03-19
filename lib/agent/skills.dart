// Ghost — Skill Manager

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../models/skill.dart';

final _log = Logger('Ghost.SkillManager');

class SkillManager {
  SkillManager({
    required this.stateDir,
  });

  /// Typically `~/.ghost`
  final String stateDir;

  String get skillsDir => p.join(stateDir, 'skills');
  String get globalsFile => p.join(stateDir, 'skills_global.json');

  /// List of globally enabled skill slugs
  Set<String> _globalSlugs = {};

  Future<void> initialize() async {
    final dir = Directory(skillsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _loadGlobals();
  }

  Future<void> _loadGlobals() async {
    final file = File(globalsFile);
    if (await file.exists()) {
      try {
        final String content = await file.readAsString();
        final jsonList = jsonDecode(content) as List<dynamic>;
        _globalSlugs = jsonList.map((e) => e.toString()).toSet();
      } catch (e) {
        _log.warning('Failed to load global skills list: $e');
        _globalSlugs = {};
      }
    }
  }

  Future<void> _saveGlobals() async {
    final file = File(globalsFile);
    await file.writeAsString(jsonEncode(_globalSlugs.toList()));
  }

  /// Discover all installed skills.
  Future<List<Skill>> loadSkills() async {
    final List<Skill> skills = [];
    final dir = Directory(skillsDir);

    if (!await dir.exists()) {
      return skills;
    }

    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        final slug = p.basename(entity.path);
        final metaFile = File(p.join(entity.path, '_meta.json'));
        final mdFile = File(p.join(entity.path, 'SKILL.md'));

        Map<String, dynamic>? metaData;

        if (await metaFile.exists()) {
          try {
            final content = await metaFile.readAsString();
            metaData = jsonDecode(content) as Map<String, dynamic>;
          } catch (e) {
            _log.warning('Failed to parse _meta.json for skill $slug: $e');
          }
        }

        if (await mdFile.exists()) {
          try {
            final mdContent = await mdFile.readAsString();
            final frontmatter = _parseFrontmatter(mdContent);

            // Frontmatter takes precedence or fills gaps
            metaData ??= {};
            if (frontmatter.containsKey('name'))
              metaData['name'] = frontmatter['name'];
            if (frontmatter.containsKey('description'))
              metaData['description'] = frontmatter['description'];
            if (frontmatter.containsKey('emoji'))
              metaData['emoji'] = frontmatter['emoji'];
            if (frontmatter.containsKey('slug'))
              metaData['slug'] = frontmatter['slug'];
          } catch (e) {
            _log.warning('Failed to parse SKILL.md for skill $slug: $e');
          }
        }

        if (metaData != null || await mdFile.exists()) {
          final skill = Skill(
            slug: metaData?['slug'] as String? ?? slug,
            name: metaData?['name'] as String? ?? slug,
            description: metaData?['description'] as String? ?? '',
            emoji: metaData?['emoji'] as String?,
            isGlobal: _globalSlugs.contains(slug),
          );
          skills.add(skill);
        }
      }
    }

    return skills;
  }

  Map<String, String> _parseFrontmatter(String content) {
    final result = <String, String>{};
    // Support both --- and +++ delimiters, and be more lenient with whitespace
    final match = RegExp(r'^---\s*\n([\s\S]*?)\n---').firstMatch(content) ??
        RegExp(r'^\+\+\+\s*\n([\s\S]*?)\n\+\+\+').firstMatch(content);

    if (match != null) {
      final yamlLines = match.group(1)!.split('\n');
      for (final line in yamlLines) {
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          final key = line.substring(0, colonIndex).trim();
          var value = line.substring(colonIndex + 1).trim();

          // Remove surrounding quotes if present
          if ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'"))) {
            value = value.substring(1, value.length - 1);
          }
          result[key] = value;
        }
      }

      // Legacy support for emoji in metadata block if needed
      if (!result.containsKey('emoji')) {
        final emojiMatch = RegExp(r'metadata:\s*\{[^}]*"emoji":\s*"([^"]+)"')
            .firstMatch(content);
        if (emojiMatch != null) {
          result['emoji'] = emojiMatch.group(1)!;
        }
      }
    }
    return result;
  }

  /// Installs a new skill from a zip archive.
  Future<Skill> installSkill(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    String? foundSlug;
    Map<String, dynamic> metaJson = {};

    // 1. Look for SKILL.md for frontmatter metadata (Modern way)
    for (final file in archive) {
      if (file.isFile && p.basename(file.name) == 'SKILL.md') {
        final content = utf8.decode(file.content as List<int>);
        final frontmatter = _parseFrontmatter(content);
        if (frontmatter.containsKey('name'))
          metaJson['name'] = frontmatter['name'];
        if (frontmatter.containsKey('description'))
          metaJson['description'] = frontmatter['description'];
        if (frontmatter.containsKey('emoji'))
          metaJson['emoji'] = frontmatter['emoji'];
        if (frontmatter.containsKey('slug')) foundSlug = frontmatter['slug'];
        break;
      }
    }

    // 2. Fallback to _meta.json (Legacy compatibility)
    for (final file in archive) {
      if (file.isFile && p.basename(file.name) == '_meta.json') {
        final content = utf8.decode(file.content as List<int>);
        final json = jsonDecode(content) as Map<String, dynamic>;
        metaJson['name'] ??= json['name'];
        metaJson['description'] ??= json['description'];
        foundSlug ??= json['slug'] as String?;
        break;
      }
    }

    // 3. Fallback: Use 'name' if slug is missing
    if (foundSlug == null && metaJson['name'] != null) {
      final rawName = metaJson['name'] as String;
      // Sanitize name to create a valid slug (lowercase, alphanumeric, hyphens)
      foundSlug = rawName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
    }

    // 4. Last fallback: determine slug from folder name in ZIP if possible
    if (foundSlug == null || foundSlug.isEmpty) {
      for (final file in archive) {
        final parts = p.split(file.name);
        if (parts.length > 1) {
          foundSlug = parts[0];
          break;
        }
      }
    }

    if (foundSlug == null || foundSlug.isEmpty) {
      throw Exception('Invalid skill archive: slug could not be determined. '
          'Please ensure SKILL.md has a "name" or "slug" field in its frontmatter.');
    }

    // --- Start Duplicate Handling ---
    String uniqueSlug = foundSlug;
    int suffix = 1;
    while (await Directory(p.join(skillsDir, uniqueSlug)).exists()) {
      uniqueSlug = '$foundSlug-${suffix++}';
    }
    foundSlug = uniqueSlug;
    // --- End Duplicate Handling ---

    final skillDir = Directory(p.join(skillsDir, foundSlug));
    if (!await skillDir.exists()) {
      await skillDir.create(recursive: true);
    }

    // Extract files
    for (final file in archive) {
      if (file.isFile) {
        final relativePath = p.normalize(file.name);
        if (relativePath.contains('..')) continue;

        // outPath should be relative to skillDir
        final outPath = p.join(skillDir.path, relativePath);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    return Skill(
      slug: foundSlug,
      name: metaJson['name'] as String? ?? foundSlug,
      description: metaJson['description'] as String? ?? '',
      emoji: metaJson['emoji'] as String?,
      isGlobal: _globalSlugs.contains(foundSlug),
    );
  }

  /// Downloads a skill from a GitHub repository folder.
  /// Expects a URL like: https://github.com/owner/repo/tree/branch/path/to/skill
  Future<Skill> downloadGithubSkill(String url) async {
    final uri = Uri.parse(url);
    if (uri.host != 'github.com') {
      throw Exception('Invalid GitHub URL: $url');
    }
    var segments = uri.pathSegments.toList();

    // If URL points directly to SKILL.md, trim it off to get the folder
    if (segments.isNotEmpty && segments.last == 'SKILL.md') {
      segments.removeLast();
    }

    if (segments.length < 5 ||
        (segments[2] != 'tree' && segments[2] != 'blob')) {
      throw Exception(
          'URL must point to a folder or SKILL.md in a GitHub repository: $url');
    }

    final owner = segments[0];
    final repo = segments[1];
    final branch = segments[3];
    final folderPath = segments.sublist(4).join('/');

    // GitHub provides repository ZIPs at this URL pattern
    final zipUrl =
        'https://github.com/$owner/$repo/archive/refs/heads/$branch.zip';
    _log.info('Downloading skill from GitHub: $zipUrl (folder: $folderPath)');

    final response = await http.get(Uri.parse(zipUrl));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to download repository ZIP from $zipUrl: ${response.statusCode}');
    }

    final archive = ZipDecoder().decodeBytes(response.bodyBytes);

    // GitHub ZIPs have a root folder (usually repo-branch or repo-sha)
    // We determine it from the first entry instead of guessing
    if (archive.isEmpty) throw Exception('Downloaded ZIP is empty.');
    final rootFolder = archive.files.first.name.split('/')[0];
    final targetPrefix = '$rootFolder/$folderPath/';
    _log.info('Target prefix in ZIP: $targetPrefix');

    // Group files by potential skill directories
    // A skill directory is one that contains a SKILL.md or _meta.json
    final Map<String, List<ArchiveFile>> skillFiles = {};
    final Set<String> skillRoots = {};

    for (final file in archive) {
      if (file.isFile && file.name.startsWith(targetPrefix)) {
        final relativePath = file.name.substring(targetPrefix.length);
        final filename = p.basename(relativePath);

        if (filename == 'SKILL.md' || filename == '_meta.json') {
          final skillRoot = p.dirname(relativePath);
          skillRoots.add(skillRoot);
        }
      }
    }

    if (skillRoots.isEmpty) {
      throw Exception(
          'No skill definition (SKILL.md or _meta.json) found in "$folderPath".');
    }

    // Now group files by their closest skill root
    for (final file in archive) {
      if (file.isFile && file.name.startsWith(targetPrefix)) {
        final relativePath = file.name.substring(targetPrefix.length);

        // Find which skill root this file belongs to (longest match)
        String? bestRoot;
        for (final root in skillRoots) {
          if (root == '.' || relativePath.startsWith('$root/')) {
            if (bestRoot == null || root.length > bestRoot.length) {
              bestRoot = root;
            }
          }
        }

        if (bestRoot != null) {
          skillFiles.putIfAbsent(bestRoot, () => []).add(file);
        }
      }
    }

    Skill? firstSkill;
    for (final root in skillRoots) {
      final files = skillFiles[root] ?? [];
      if (files.isEmpty) continue;

      final encoder = ZipEncoder();
      final newArchive = Archive();
      final rootPrefix = root == '.' ? '' : '$root/';

      for (final file in files) {
        final relativeName =
            file.name.substring(targetPrefix.length + rootPrefix.length);
        newArchive.addFile(ArchiveFile(relativeName, file.size, file.content));
      }

      final zipBytes = encoder.encode(newArchive);
      if (zipBytes != null) {
        final installed = await installSkill(zipBytes);
        firstSkill ??= installed;
        _log.info('Installed skill: ${installed.slug} from $root');
      }
    }

    if (firstSkill == null) {
      throw Exception('Failed to install any skills from the repository.');
    }

    return firstSkill;
  }

  Future<void> deleteSkill(String slug) async {
    final skillDir = Directory(p.join(skillsDir, slug));
    if (await skillDir.exists()) {
      await skillDir.delete(recursive: true);
    }

    if (_globalSlugs.contains(slug)) {
      _globalSlugs.remove(slug);
      await _saveGlobals();
    }
  }

  Future<void> setGlobal(String slug, bool isGlobal) async {
    if (isGlobal) {
      _globalSlugs.add(slug);
    } else {
      _globalSlugs.remove(slug);
    }
    await _saveGlobals();
  }

  Future<String> readSkillContent(String slug) async {
    final skillFile = File(p.join(skillsDir, slug, 'SKILL.md'));
    if (await skillFile.exists()) {
      return await skillFile.readAsString();
    }
    return '';
  }

  Future<void> updateSkillContent(String slug, String content) async {
    final skillFile = File(p.join(skillsDir, slug, 'SKILL.md'));
    if (!await skillFile.exists()) {
      // Ensure directory exists just in case
      await skillFile.parent.create(recursive: true);
    }
    await skillFile.writeAsString(content);
  }

  /// Builds context from the given skill slugs AND globally enabled skills.
  Future<String> buildSkillContext(List<String> agentSlugs) async {
    final Set<String> slugsToLoad = {..._globalSlugs, ...agentSlugs};
    final buffer = StringBuffer();

    for (final slug in slugsToLoad) {
      final content = await readSkillContent(slug);
      if (content.isNotEmpty) {
        buffer.writeln('=== SKILL: $slug ===');
        buffer.writeln(content);
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Backs up all skills to a JSON string.
  Future<String> backupSkills() async {
    final skills = await loadSkills();
    final List<Map<String, dynamic>> backup = [];

    for (final skill in skills) {
      final skillDirPath = p.join(skillsDir, skill.slug);
      final skillDir = Directory(skillDirPath);

      if (!await skillDir.exists()) continue;

      final List<String> files = [];
      final Map<String, String> fileContents = {};

      await for (final entity in skillDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: skillDirPath);
          if (relativePath.contains('..')) continue;

          files.add(relativePath);
          fileContents[relativePath] = await entity.readAsString();
        }
      }

      backup.add({
        'slug': skill.slug,
        'name': skill.name,
        'description': skill.description,
        'emoji': skill.emoji,
        'isGlobal': skill.isGlobal,
        'files': files,
        'fileContents': fileContents,
      });
    }

    return jsonEncode({
      'version': 1,
      'skills': backup,
    });
  }

  /// Restores skills from a JSON backup string.
  Future<void> restoreSkills(String data) async {
    final backup = jsonDecode(data) as Map<String, dynamic>;
    final version = backup['version'] as int?;
    if (version != 1) {
      throw Exception('Unsupported backup version: $version');
    }

    final skills = backup['skills'] as List<dynamic>;

    for (final skillJson in skills) {
      final skill = skillJson as Map<String, dynamic>;
      final slug = skill['slug'] as String;
      final files = (skill['files'] as List<dynamic>).cast<String>();
      final fileContents = (skill['fileContents'] as Map<String, dynamic>)
          .cast<String, String>();
      final isGlobal = skill['isGlobal'] as bool? ?? false;

      final skillDir = Directory(p.join(skillsDir, slug));

      if (await skillDir.exists()) {
        await skillDir.delete(recursive: true);
      }
      await skillDir.create(recursive: true);

      for (final filePath in files) {
        final content = fileContents[filePath];
        if (content == null) continue;

        final outFile = File(p.join(skillDir.path, filePath));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsString(content);
      }

      if (isGlobal) {
        _globalSlugs.add(slug);
      }
    }

    await _saveGlobals();
  }
}
