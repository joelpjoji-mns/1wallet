import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages a per-device AES-256 key stored in the OS secure enclave and provides
/// authenticated encryption with a **unique random IV per operation**.
///
/// Storage format (new):   `<ivBase64>:<cipherBase64>`
/// Storage format (legacy): `<cipherBase64>`  (hardcoded key + all-zero IV)
///
/// On decryption, legacy values are transparently detected and decrypted.
/// On the next save the caller should re-encrypt with [encrypt] so the value
/// is migrated to the secure format automatically.
abstract final class SecureKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyAlias = 'onewallet_aes_key_v1';

  /// The original hardcoded key that was used before per-device keys.
  /// Kept ONLY for migrating existing user data — never used for new encryption.
  static const _legacyKey = 'my32lengthsupersecretkey12345678';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] with the device-specific key and a fresh random IV.
  ///
  /// Returns a `'<ivBase64>:<cipherBase64>'` string safe to persist in Firestore
  /// or local storage.
  static Future<String> encrypt(String plaintext) async {
    final key = await _getOrCreateKey();
    final iv = enc.IV(_randomBytes(16));
    final encrypter = enc.Encrypter(enc.AES(key));
    final cipherText = encrypter.encrypt(plaintext, iv: iv).base64;
    return '${base64Encode(iv.bytes)}:$cipherText';
  }

  /// Decrypts a [stored] value produced by either [encrypt] (new format) or the
  /// old hardcoded-key approach (legacy format).
  ///
  /// Returns the plaintext string.
  static Future<String> decrypt(String stored) async {
    if (_isNewFormat(stored)) {
      return _decryptNew(stored);
    }
    return _decryptLegacy(stored);
  }

  /// Returns `true` if [stored] uses the legacy (hardcoded key) format.
  /// Use this to decide whether to migrate after decryption.
  static bool isLegacyFormat(String stored) => !_isNewFormat(stored);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<enc.Key> _getOrCreateKey() async {
    String? stored = await _storage.read(key: _keyAlias);
    if (stored == null) {
      final bytes = _randomBytes(32);
      stored = base64Encode(bytes);
      await _storage.write(key: _keyAlias, value: stored);
    }
    return enc.Key(base64Decode(stored));
  }

  static bool _isNewFormat(String stored) {
    // Base-64 alphabet: A-Za-z0-9+/= — colons never appear, so the separator ':' is safe.
    return stored.contains(':');
  }

  static Future<String> _decryptNew(String stored) async {
    final separatorIdx = stored.indexOf(':');
    if (separatorIdx < 0)
      throw const FormatException('Invalid encrypted format');
    final ivBytes = base64Decode(stored.substring(0, separatorIdx));
    final cipherBase64 = stored.substring(separatorIdx + 1);
    final iv = enc.IV(ivBytes);
    final key = await _getOrCreateKey();
    final encrypter = enc.Encrypter(enc.AES(key));
    return encrypter.decrypt64(cipherBase64, iv: iv);
  }

  static String _decryptLegacy(String stored) {
    final key = enc.Key.fromUtf8(_legacyKey);
    final iv = enc.IV(Uint8List(16)); // original code used an all-zero IV
    final encrypter = enc.Encrypter(enc.AES(key));
    return encrypter.decrypt64(stored, iv: iv);
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
