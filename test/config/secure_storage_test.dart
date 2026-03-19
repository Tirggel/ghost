import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ghost/config/secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late Uint8List encryptionKey;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_test_');
    Hive.init(tempDir.path);
    encryptionKey = Uint8List.fromList(List.generate(32, (i) => i));
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HiveSecureStorage', () {
    test('Set and get secret', () async {
      final storage = HiveSecureStorage(encryptionKey: encryptionKey);

      await storage.set('api_key', 'sk-123456');
      final value = await storage.get('api_key');

      expect(value, equals('sk-123456'));
    });

    test('Vault is persisted and reloadable', () async {
      final storage1 = HiveSecureStorage(encryptionKey: encryptionKey);
      await storage1.set('key1', 'value1');
      await Hive.close(); // Ensure flushed to disk

      Hive.init(tempDir.path);
      final storage2 = HiveSecureStorage(encryptionKey: encryptionKey);
      expect(await storage2.get('key1'), equals('value1'));
    });

    test('Fails with wrong key', () async {
      final storage1 = HiveSecureStorage(encryptionKey: encryptionKey);
      await storage1.set('important_secret', 'top-secret-value');
      await Hive.close();

      Hive.init(tempDir.path);
      // Use a completely different key
      final wrongKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      final storage2 = HiveSecureStorage(encryptionKey: wrongKey);

      // Hive behavior: If the box exists but decoding fails (wrong key),
      // it may clear/recover the box or throw. Our implementation tries to trigger a read.
      // If Hive recovers (clears), the secret will be null.
      final result = await storage2.get('important_secret');
      expect(result, isNot(equals('top-secret-value')));
    });

    test('Delete vault works', () async {
      final storage = HiveSecureStorage(encryptionKey: encryptionKey);
      await storage.set('key', 'val');

      final hiveFile = File(p.join(tempDir.path, 'vault.hive'));
      expect(await hiveFile.exists(), isTrue);

      await storage.deleteVault();
      expect(await hiveFile.exists(), isFalse);
      expect(await storage.get('key'), isNull);
    });
  });
}
