// Ghost — Cryptography utilities.
//
// Provides SHA-256 hashing, AES-256-GCM encryption/decryption,
// PBKDF2 key derivation, and secure random byte generation.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:pointycastle/export.dart';

/// SHA-256 hash of a string, returned as hex.
String sha256Hash(String input) {
  final bytes = utf8.encode(input);
  final digest = crypto_pkg.sha256.convert(bytes);
  return digest.toString();
}

/// SHA-256 hash of bytes, returned as hex.
String sha256HashBytes(Uint8List bytes) {
  final digest = crypto_pkg.sha256.convert(bytes);
  return digest.toString();
}

/// HMAC-SHA256 of a message with a key.
String hmacSha256(String key, String message) {
  final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, utf8.encode(key));
  final digest = hmac.convert(utf8.encode(message));
  return digest.toString();
}

/// Generate cryptographically secure random bytes.
Uint8List secureRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// Generate a secure random token as hex string.
String generateToken({int byteLength = 32}) {
  final bytes = secureRandomBytes(byteLength);
  return _bytesToHex(bytes);
}

/// Derive a key from a password using PBKDF2-HMAC-SHA256.
///
/// Returns a [byteLength]-byte key (default 32 = 256 bits).
Uint8List deriveKey(
  String password, {
  required Uint8List salt,
  int iterations = 10000,
  int byteLength = 32,
}) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, iterations, byteLength));
  return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
}

/// Encrypt plaintext using AES-256-GCM.
///
/// Returns a map with `ciphertext`, `iv`, `tag`, and `salt` (all base64).
/// The key is derived from [password] via PBKDF2.
Map<String, String> encryptAes256Gcm(String plaintext, String password) {
  final salt = secureRandomBytes(16);
  final key = deriveKey(password, salt: salt);
  final iv = secureRandomBytes(12); // 96-bit IV for GCM

  final cipher = GCMBlockCipher(AESEngine());
  final params = AEADParameters(
    KeyParameter(key),
    128, // 128-bit tag
    iv,
    Uint8List(0), // no AAD
  );
  cipher.init(true, params);

  final input = Uint8List.fromList(utf8.encode(plaintext));
  final output = Uint8List(cipher.getOutputSize(input.length));
  var len = cipher.processBytes(input, 0, input.length, output, 0);
  len += cipher.doFinal(output, len);

  final actualOutput = output.sublist(0, len);
  final tagStart = actualOutput.length - 16;
  final ciphertext = actualOutput.sublist(0, tagStart);
  final tag = actualOutput.sublist(tagStart);

  return {
    'ciphertext': base64Encode(ciphertext),
    'iv': base64Encode(iv),
    'tag': base64Encode(tag),
    'salt': base64Encode(salt),
  };
}

/// Decrypt AES-256-GCM encrypted data.
///
/// Takes the same map structure returned by [encryptAes256Gcm].
String decryptAes256Gcm(Map<String, String> encrypted, String password) {
  final salt = base64Decode(encrypted['salt']!);
  final iv = base64Decode(encrypted['iv']!);
  final ciphertext = base64Decode(encrypted['ciphertext']!);
  final tag = base64Decode(encrypted['tag']!);

  final key = deriveKey(password, salt: Uint8List.fromList(salt));

  final cipher = GCMBlockCipher(AESEngine());
  final params = AEADParameters(
    KeyParameter(key),
    128,
    Uint8List.fromList(iv),
    Uint8List(0),
  );
  cipher.init(false, params);

  // Combine ciphertext + tag for GCM decryption
  final input = Uint8List(ciphertext.length + tag.length);
  input.setAll(0, ciphertext);
  input.setAll(ciphertext.length, tag);

  final output = Uint8List(cipher.getOutputSize(input.length));
  var len = cipher.processBytes(input, 0, input.length, output, 0);
  len += cipher.doFinal(output, len);

  // Remove padding bytes (GCM output includes tag space)
  final plaintextBytes = output.sublist(0, ciphertext.length);
  return utf8.decode(plaintextBytes);
}

/// Constant-time comparison of two strings to prevent timing attacks.
bool secureCompare(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
