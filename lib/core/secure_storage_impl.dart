import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../engine.dart';

/// Implementation of [SecureStorage] using [FlutterSecureStorage].
/// This provides OS-level secure storage (Keychain, Keystore, etc.)
class FlutterSecureStorageImpl implements SecureStorage {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    lOptions: LinuxOptions(),
  );

  @override
  Future<void> set(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<String?> get(String key) async {
    return await _storage.read(key: key);
  }

  @override
  Future<void> remove(String key) async {
    await _storage.delete(key: key);
  }

  @override
  Future<bool> has(String key) async {
    return await _storage.containsKey(key: key);
  }

  @override
  Future<List<String>> listKeys() async {
    final all = await _storage.readAll();
    return all.keys.toList();
  }

  @override
  void clearCache() {
    // FlutterSecureStorage doesn't have a manual cache to clear.
  }

  @override
  Future<void> deleteVault() async {
    await _storage.deleteAll();
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
