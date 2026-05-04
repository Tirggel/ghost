import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../engine.dart';
import 'constants.dart';

/// Implementation of [SecureStorage] using [FlutterSecureStorage].
/// This provides OS-level secure storage (Keychain, Keystore, etc.)
class FlutterSecureStorageImpl implements SecureStorage {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    lOptions: LinuxOptions(),
  );

  static const String _indexKey = '_ghost_secure_keys_index';

  Future<void> _addToIndex(String key) async {
    if (!kIsWeb && Platform.isLinux) {
      if (key == _indexKey) return;
      try {
        final raw = await _storage.read(key: _indexKey);
        final List<String> keys = raw != null ? List<String>.from(jsonDecode(raw) as List) : [];
        if (!keys.contains(key)) {
          keys.add(key);
          await _storage.write(key: _indexKey, value: jsonEncode(keys));
        }
      } catch (_) {}
    }
  }

  Future<void> _removeFromIndex(String key) async {
    if (!kIsWeb && Platform.isLinux) {
      if (key == _indexKey) return;
      try {
        final raw = await _storage.read(key: _indexKey);
        if (raw != null) {
          final List<String> keys = List<String>.from(jsonDecode(raw) as List);
          if (keys.remove(key)) {
            await _storage.write(key: _indexKey, value: jsonEncode(keys));
          }
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> set(String key, String value) async {
    await _storage.write(key: key, value: value);
    await _addToIndex(key);
  }

  @override
  Future<String?> get(String key) async {
    return await _storage.read(key: key);
  }

  @override
  Future<void> remove(String key) async {
    await _storage.delete(key: key);
    await _removeFromIndex(key);
  }

  @override
  Future<bool> has(String key) async {
    return await _storage.containsKey(key: key);
  }

  @override
  Future<List<String>> listKeys() async {
    if (!kIsWeb && !Platform.isLinux) {
      final all = await _storage.readAll();
      return all.keys.where((k) => k != _indexKey).toList();
    }

    // On Linux, avoid using _storage.readAll() as it is known to freeze/hang indefinitely
    // with certain libsecret setups.
    
    final activeKeys = <String>{};
    
    // 1. Core Base Keys
    final baseKeys = [
      'auth_token',
      'client_token',
      'agent_config',
      'user_config',
      'channels_config',
      'tools_config',
      'session_config',
      'identity_config',
      'integrations_config',
      'security_config',
    ];
    activeKeys.addAll(baseKeys);

    // 2. Discover from Index
    try {
      final raw = await _storage.read(key: _indexKey);
      if (raw != null) {
        activeKeys.addAll(List<String>.from(jsonDecode(raw) as List));
      }
    } catch (_) {}

    // 3. Fallback discovery (for keys added before the index feature)
    final dynamicKeys = [
      'google_client_id_web',
      'google_client_id_desktop',
      'google_client_secret',
      'google_access_token',
      'google_api_key',
      'telegram_bot_token',
      'ms_graph_access_token',
      'ms_client_id',
    ];

    for (final p in AppConstants.aiProviders) {
      final id = p['id']!;
      if (AppConstants.isLocalProvider(id)) {
        dynamicKeys.add('${id}_base_url');
      } else {
        dynamicKeys.add('${id}_api_key');
      }
    }
    for (final c in AppConstants.chatChannels) {
      dynamicKeys.add('${c['id']}_token');
    }

    for (final key in dynamicKeys) {
      if (await _storage.containsKey(key: key)) {
        activeKeys.add(key);
        await _addToIndex(key); // Auto-migrate to index
      }
    }

    return activeKeys.toList();
  }

  @override
  void clearCache() {
    // FlutterSecureStorage doesn't have a manual cache to clear.
  }

  @override
  Future<void> deleteVault() async {
    try {
      final keys = await listKeys();
      for (final key in keys) {
        // Overwrite before deleting to ensure data is gone even if delete fails
        await _storage.write(key: key, value: '');
        await _storage.delete(key: key);
      }
      await _storage.delete(key: _indexKey);
    } catch (_) {}
    try {
      if (!kIsWeb && !Platform.isLinux) {
        await _storage.deleteAll();
      }
    } catch (_) {}
  }

  @override
  Future<void> reinitialize(Uint8List newKey) async {
    // FlutterSecureStorage uses OS-level encryption (Keychain/Keystore)
    // and does not require manual key re-initialization like Hive.
  }

  @override
  Future<void> close() async {
    // FlutterSecureStorage is a stateless wrapper around the OS Keychain/Keystore.
    // Nothing to close here.
  }
}
