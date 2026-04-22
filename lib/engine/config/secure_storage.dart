// Ghost — Secure storage for API keys and secrets.
//
// Uses Hive CE with AES-256 for encryption at rest.

import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:logging/logging.dart';

import '../infra/errors.dart';

final _log = Logger('Ghost.SecureStorage');

/// Base class for secure storage (API keys, tokens).
abstract class SecureStorage {
  Future<void> set(String key, String value);
  Future<String?> get(String key);
  Future<void> remove(String key);
  Future<bool> has(String key);
  Future<List<String>> listKeys();
  void clearCache();
  Future<void> deleteVault();
  Future<void> reinitialize(Uint8List newKey);
  Future<void> close();
}

/// Secure storage implementation using an encrypted Hive CE box.
class HiveSecureStorage implements SecureStorage {
  HiveSecureStorage({required Uint8List encryptionKey}) : _encryptionKey = encryptionKey;

  /// The 32-byte encryption key for the Hive box.
  Uint8List _encryptionKey;

  static const _boxName = 'vault';
  bool _initialized = false;
  late Box<String> _box;

  Future<void> _ensureOpen() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(_encryptionKey),
      );
      // Trigger a read to catch decryption errors immediately
      if (_box.isNotEmpty) {
        _box.get(_box.keys.first);
      }
      _initialized = true;
    } catch (e) {
      _log.severe('Failed to open encrypted vault: $e');
      throw ConfigError(
        'Failed to decrypt vault — wrong key or corrupted file',
        code: 'DECRYPT_FAILED',
        cause: e,
      );
    }
  }

  @override
  Future<void> set(String key, String value) async {
    await _ensureOpen();
    await _box.put(key, value);
    _log.fine('Secret stored: $key');
  }

  @override
  Future<String?> get(String key) async {
    await _ensureOpen();
    return _box.get(key);
  }

  @override
  Future<void> remove(String key) async {
    await _ensureOpen();
    await _box.delete(key);
    _log.fine('Secret removed: $key');
  }

  @override
  Future<bool> has(String key) async {
    await _ensureOpen();
    return _box.containsKey(key);
  }

  @override
  Future<List<String>> listKeys() async {
    await _ensureOpen();
    return _box.keys.map((k) => k.toString()).toList();
  }

  @override
  void clearCache() {
    // Hive manages its own caching.
  }

  @override
  Future<void> deleteVault() async {
    await _ensureOpen();
    await _box.clear();
    await _box.close();
    await Hive.deleteBoxFromDisk(_boxName);
    _initialized = false;
    _log.info('Vault deleted from disk');
  }

  @override
  Future<void> close() async {
    if (_initialized) {
      await _box.close();
      _initialized = false;
      _log.info('Vault closed');
    }
  }

  @override
  Future<void> reinitialize(Uint8List newKey) async {
    if (_initialized) {
      await _box.close();
      _initialized = false;
    }
    _encryptionKey = newKey;
    _log.info('Vault re-initialized with new encryption key');
  }
}

/// Implementation of [SecureStorage] that stays in memory (volatile).
class MemorySecureStorage implements SecureStorage {
  final Map<String, String> _secrets = {};

  @override
  Future<void> set(String key, String value) async {
    _secrets[key] = value;
  }

  @override
  Future<String?> get(String key) async {
    return _secrets[key];
  }

  @override
  Future<void> remove(String key) async {
    _secrets.remove(key);
  }

  @override
  Future<bool> has(String key) async {
    return _secrets.containsKey(key);
  }

  @override
  Future<List<String>> listKeys() async {
    return _secrets.keys.toList();
  }

  @override
  void clearCache() {}

  @override
  Future<void> deleteVault() async {
    _secrets.clear();
  }

  @override
  Future<void> reinitialize(Uint8List newKey) async {
    _secrets.clear();
  }

  @override
  Future<void> close() async {
    _secrets.clear();
  }
}
