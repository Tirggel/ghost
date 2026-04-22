import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PlatformStorage {
  /// Returns the root directory where Ghost data should be stored.
  /// Desktop: ~/.ghost (for compatibility with CLI)
  /// Mobile: Application Documents Directory / .ghost
  static Future<String> getGhostDir() async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      String? home;
      if (Platform.isWindows) {
        home = Platform.environment['USERPROFILE'];
      } else {
        home = Platform.environment['HOME'];
      }
      
      if (home != null) {
        return p.join(home, '.ghost');
      }
    }
    
    // For mobile or if environment variables are missing
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, '.ghost');
  }

  static Future<String> getConfigPath() async {
    final dir = await getGhostDir();
    return p.join(dir, 'ghost.json');
  }
}
