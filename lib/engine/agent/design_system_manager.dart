import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

import '../../core/models/design_system.dart';

final _log = Logger('Ghost.DesignSystemManager');

class DesignSystemManager {
  DesignSystemManager({
    required this.stateDir,
  });

  /// Typically `~/.ghost`
  final String stateDir;

  String get dsDir => p.join(stateDir, 'design-systems');

  final _dsChangedController = StreamController<void>.broadcast();
  Stream<void> get onDesignSystemsChanged => _dsChangedController.stream;
  StreamSubscription<FileSystemEvent>? _watchSubscription;

  Future<void> initialize() async {
    final dir = Directory(dsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _startWatching();
  }

  void _startWatching() {
    final dir = Directory(dsDir);
    if (!dir.existsSync()) return;

    Timer? debounceTimer;
    try {
      _watchSubscription = dir.watch(recursive: false).listen((event) {
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (!_dsChangedController.isClosed) {
            _dsChangedController.add(null);
          }
        });
      });
    } catch (e) {
      _log.warning('Could not start directory watcher on design systems dir: $e');
    }
  }

  void dispose() {
    _watchSubscription?.cancel();
    _dsChangedController.close();
  }

  /// Discover all installed design systems.
  Future<List<DesignSystem>> loadDesignSystems() async {
    final List<DesignSystem> systems = [];
    final dir = Directory(dsDir);

    if (!await dir.exists()) {
      return systems;
    }

    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.md')) {
        final id = p.basenameWithoutExtension(entity.path);
        
        // Try to parse a name from the content (first heading)
        String name = id;
        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');
          for (final line in lines) {
            if (line.startsWith('# ')) {
              name = line.substring(2).trim();
              break;
            } else if (line.startsWith('name:')) {
              // basic frontmatter support
              name = line.substring(5).trim().replaceAll('"', '').replaceAll("'", "");
              break;
            }
          }
        } catch (e) {
          _log.warning('Failed to read design system $id: $e');
        }

        // Capitalize slug if no name found
        if (name == id && name.isNotEmpty) {
          name = name[0].toUpperCase() + name.substring(1).replaceAll('-', ' ');
        }

        systems.add(DesignSystem(
          id: id,
          name: name,
        ));
      }
    }

    // Sort alphabetically by name
    systems.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return systems;
  }

  Future<DesignSystem?> getDesignSystem(String id) async {
    final file = File(p.join(dsDir, '$id.md'));
    if (!await file.exists()) return null;

    final systems = await loadDesignSystems();
    final ds = systems.firstWhere((s) => s.id == id, orElse: () => DesignSystem(id: id, name: id));
    
    final content = await file.readAsString();
    return DesignSystem(id: id, name: ds.name, content: content);
  }

  Future<void> deleteDesignSystem(String id) async {
    final file = File(p.join(dsDir, '$id.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<DesignSystem> saveDesignSystem(String id, String name, String content) async {
    // Sanitize ID
    String slug = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'design-system';

    final file = File(p.join(dsDir, '$slug.md'));
    await file.writeAsString(content);

    return DesignSystem(id: slug, name: name, content: content);
  }

  Future<DesignSystem> downloadFromUrl(String url) async {
    String urlToFetch = url.trim();
    if (urlToFetch.startsWith('https://github.com/') && urlToFetch.contains('/blob/')) {
      urlToFetch = urlToFetch
          .replaceFirst('https://github.com/', 'https://raw.githubusercontent.com/')
          .replaceFirst('/blob/', '/');
    }

    _log.info('Fetching design system from URL: $urlToFetch');
    final response = await http.get(Uri.parse(urlToFetch));
    
    if (response.statusCode == 200) {
      final content = response.body;
      
      // Try to determine a name from URL
      String slug = p.basenameWithoutExtension(Uri.parse(urlToFetch).path);
      if (slug.toLowerCase() == 'design' || slug.isEmpty) {
        // use the parent directory name if it's just 'design.md'
        final segments = Uri.parse(urlToFetch).pathSegments;
        if (segments.length > 1) {
          slug = segments[segments.length - 2];
        } else {
          slug = 'imported-design';
        }
      }

      // Handle duplicates
      String uniqueSlug = slug;
      int suffix = 1;
      while (await File(p.join(dsDir, '$uniqueSlug.md')).exists()) {
        uniqueSlug = '$slug-$suffix';
        suffix++;
      }

      return await saveDesignSystem(uniqueSlug, slug, content);
    } else {
      throw Exception('Failed to download design system (Status: ${response.statusCode})');
    }
  }

  Future<String> backupDesignSystems() async {
    final systems = await loadDesignSystems();
    final List<Map<String, dynamic>> backup = [];
    
    for (final s in systems) {
      final detailed = await getDesignSystem(s.id);
      if (detailed != null) {
        backup.add(detailed.toJson());
      }
    }
    
    return jsonEncode(backup);
  }

  Future<void> restoreDesignSystems(String data) async {
    final List<dynamic> list = jsonDecode(data);
    for (final item in list) {
      final ds = DesignSystem.fromJson(item as Map<String, dynamic>);
      await saveDesignSystem(ds.id, ds.name, ds.content);
    }
  }

  Future<void> installDesignSystem(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (file.isFile && file.name.endsWith('.md')) {
        final content = utf8.decode(file.content as List<int>);
        final name = p.basenameWithoutExtension(file.name);
        await saveDesignSystem(name, name, content);
      }
    }
  }
}
