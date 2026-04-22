import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../engine.dart';
import 'package:hive_ce/hive.dart';
import 'package:logging/logging.dart';
import 'platform_storage.dart';
import 'secure_storage_impl.dart';

final _log = Logger('Ghost.Migration');

class MigrationService {
  final _secureStorage = FlutterSecureStorageImpl();
  static const _migrationDoneKey = 'migration_v1_done';

  Future<void> run() async {
    final isDone = await _secureStorage.get(_migrationDoneKey);
    if (isDone == 'true') {
      _log.fine('Migration already completed.');
      return;
    }

    _log.info('Starting migration from legacy storage...');

    try {
      final ghostDir = await PlatformStorage.getGhostDir();
      final configPath = await PlatformStorage.getConfigPath();
      final configFile = File(configPath);

      if (!await configFile.exists()) {
        _log.info('No legacy config found at $configPath. Skipping migration.');
        await _secureStorage.set(_migrationDoneKey, 'true');
        return;
      }

      // 1. Read config to get the seed for Hive key
      final content = await configFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final config = GhostConfig.fromJson(json);

      final tokenHash = config.gateway.auth.tokenHash;
      final passwordHash = config.gateway.auth.passwordHash;
      final seedString = tokenHash ?? passwordHash ?? 'ghost-default-session-key';
      final sessionKey = Uint8List.fromList(sha256.convert(utf8.encode(seedString)).bytes);

      // 2. Open legacy Hive vault
      Hive.init(ghostDir);
      final legacyVault = HiveSecureStorage(encryptionKey: sessionKey);
      
      _log.info('Opening legacy Hive vault...');
      final keys = await legacyVault.listKeys();
      
      if (keys.isEmpty) {
        _log.info('Legacy vault is empty.');
      } else {
        _log.info('Migrating ${keys.length} keys to secure storage...');
        for (final key in keys) {
          final value = await legacyVault.get(key);
          if (value != null) {
            await _secureStorage.set(key, value);
            _log.fine('Migrated key: $key');
          }
        }
      }

      // 3. Migrate the auth token itself if it's in the config file
      // In the legacy system, the raw token wasn't in the config (only hash),
      // but the app might have had it in SharedPreferences. 
      // We'll handle SharedPreferences migration in the providers if needed,
      // but here we focus on systemic secrets.

      // 4. Mark as done
      await _secureStorage.set(_migrationDoneKey, 'true');
      _log.info('Migration successful.');
      
      // We keep the old files for safety but could archive them.
      _log.info('Legacy files preserved at $ghostDir');

    } catch (e, stack) {
      _log.severe('Migration failed: $e', e, stack);
      // We don't mark as done so it retries or we can debug.
    }
  }
}
