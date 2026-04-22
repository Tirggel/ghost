import 'package:test/test.dart';
import 'package:ghost/engine/infra/crypto.dart';

void main() {
  group('Hashing', () {
    test('sha256Hash produces consistent hex strings', () {
      const input = 'hello world';
      final hash1 = sha256Hash(input);
      final hash2 = sha256Hash(input);

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // SHA-256 hex is 64 chars
    });

    test('hmacSha256 produces consistent results', () {
      const key = 'secret';
      const message = 'data';
      final hmac1 = hmacSha256(key, message);
      final hmac2 = hmacSha256(key, message);

      expect(hmac1, equals(hmac2));
      expect(hmac1.length, equals(64));
    });
  });

  group('Random Generation', () {
    test('secureRandomBytes returns correct length', () {
      final bytes = secureRandomBytes(16);
      expect(bytes.length, equals(16));
    });

    test('generateToken returns hex string of correct length', () {
      final token = generateToken(byteLength: 32);
      expect(token.length, equals(64)); // 32 bytes = 64 hex chars
    });
  });

  group('Encryption', () {
    test('AES-256-GCM encryption/decryption round-trip', () {
      const plaintext = 'This is a secret message 👻';
      const password = 'strong-password-123';

      final encrypted = encryptAes256Gcm(plaintext, password);

      expect(encrypted.containsKey('ciphertext'), isTrue);
      expect(encrypted.containsKey('iv'), isTrue);
      expect(encrypted.containsKey('tag'), isTrue);
      expect(encrypted.containsKey('salt'), isTrue);

      final decrypted = decryptAes256Gcm(encrypted, password);
      expect(decrypted, equals(plaintext));
    });

    test('Decryption fails with wrong password', () {
      const plaintext = 'Secret content';
      const password = 'correct-password';
      final encrypted = encryptAes256Gcm(plaintext, password);

      expect(
          () => decryptAes256Gcm(encrypted, 'wrong-password'), throwsException);
    });
  });

  group('Comparison', () {
    test('secureCompare works correctly', () {
      expect(secureCompare('abc', 'abc'), isTrue);
      expect(secureCompare('abc', 'abd'), isFalse);
      expect(secureCompare('abc', 'abcd'), isFalse);
    });
  });
}
