import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages a per-device AES-256 key stored in the OS secure enclave and provides
/// authenticated encryption with a **unique random IV per operation**.
///
/// Storage format (new): versioned AES-GCM envelope.
/// Storage format (legacy): `<cipherBase64>`  (hardcoded key + all-zero IV)
///
/// On decryption, legacy values are transparently detected and decrypted.
/// On the next save the caller should re-encrypt with [encrypt] so the value
/// is migrated to the secure format automatically.
abstract final class SecureKeyStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyAlias = 'onewallet_aes_key_v1';
  static String fieldContext(String accountId, String field) =>
      jsonEncode([accountId, field]);

  /// The original hardcoded key that was used before per-device keys.
  /// Kept ONLY for migrating existing user data — never used for new encryption.
  static const _legacyKey = 'my32lengthsupersecretkey12345678';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] with the device-specific key and a fresh random IV.
  ///
  /// Returns an authenticated, versioned envelope for local storage or sync.
  static Future<String> encrypt(
    String plaintext, {
    String? userId,
    String purpose = 'details',
    String context = '',
  }) => _cryptoOperation(() async {
    final alias = _alias(userId, purpose);
    final key = await _getKey(alias, create: true);
    return compute(_sealAuthenticated, (plaintext, key.bytes, alias, context));
  });

  /// Decrypts a [stored] value produced by either [encrypt] (new format) or the
  /// old hardcoded-key approach (legacy format).
  ///
  /// Returns the plaintext string.
  static Future<String> decrypt(
    String stored, {
    String? userId,
    String? purpose,
    String? context,
  }) => _cryptoOperation(() async {
    if (stored.startsWith('v2:')) {
      final (alias, storedContext, nonce, data) = await compute(
        _parseAuthenticated,
        stored.substring(3),
      );
      if ((userId != null && alias != _alias(userId, purpose ?? 'details')) ||
          (purpose != null && !alias.endsWith('.$purpose')) ||
          (context != null && context != storedContext) ||
          (alias != _keyAlias && !alias.startsWith('onewallet.aes.v2.'))) {
        throw const FormatException(
          'Encrypted data belongs to another owner or purpose.',
        );
      }
      final key = await _getKey(alias, create: false);
      return compute(_openAuthenticated, (
        key.bytes,
        nonce,
        data,
        alias,
        storedContext,
      ));
    }
    if (_isNewFormat(stored)) {
      return _decryptNew(stored);
    }
    return _decryptLegacy(stored);
  });

  /// Returns true for either older format that needs authenticated re-encryption.
  /// Use this to decide whether to migrate after decryption.
  static bool isLegacyFormat(String stored) => !stored.startsWith('v2:');

  /// Clears stored cryptographic keys from the device secure storage.
  static Future<void> clear({String? userId}) => _cryptoOperation(
    () => _storageOperation(() async {
      final keys = await _storage.readAll();
      final prefix = userId == null ? 'onewallet.aes.v2.' : _alias(userId, '');
      for (final alias in keys.keys.toList(growable: false)) {
        if (alias.startsWith(prefix) ||
            (userId == null && alias == _keyAlias)) {
          await _storage.delete(key: alias);
          _keys.remove(alias);
        }
      }
      if (userId == null) _keys.clear();
    }),
  );

  static String _alias(String? userId, String purpose) {
    if (userId == null) return _keyAlias;
    final owner = sha256.convert(utf8.encode(userId)).toString();
    return 'onewallet.aes.v2.$owner.$purpose';
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<enc.Key> _getKey(String alias, {required bool create}) {
    // Concurrent callers (e.g. saving several secure fields from different
    // screens at once) must not race to independently create+persist two
    // different device keys — whichever write lost would leave data
    // encrypted under a key no longer in storage, permanently undecryptable.
    // Memoize the in-flight/resolved Future so every caller shares the same
    // read-or-create operation.
    return _keys.putIfAbsent(
      alias,
      () => _storageOperation(() => _loadOrCreateKey(alias, create: create))
          .catchError((Object error) {
            // Don't cache a failed attempt: let the next call retry.
            _keys.remove(alias);
            throw error;
          }),
    );
  }

  static final _keys = <String, Future<enc.Key>>{};
  static Future<void> _storageTail = Future<void>.value();
  static Future<void> _cryptoTail = Future<void>.value();

  static Future<T> _cryptoOperation<T>(Future<T> Function() action) {
    final result = _cryptoTail.then((_) => action());
    _cryptoTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('Encryption operation failed: ${error.runtimeType}');
      },
    );
    return result;
  }

  static Future<T> _storageOperation<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('Secure key operation failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
      },
    );
    return result;
  }

  static Future<enc.Key> _loadOrCreateKey(
    String alias, {
    required bool create,
  }) async {
    String? stored = await _storage.read(key: alias);
    if (stored == null) {
      if (!create) {
        throw StateError('The encryption key is unavailable on this device.');
      }
      final bytes = _randomBytes(32);
      stored = base64Encode(bytes);
      await _storage.write(key: alias, value: stored);
    }
    final bytes = base64Decode(stored);
    if (bytes.length != 32) {
      throw const FormatException('Invalid device encryption key.');
    }
    return enc.Key(bytes);
  }

  static bool _isNewFormat(String stored) {
    // Base-64 alphabet: A-Za-z0-9+/= — colons never appear, so the separator ':' is safe.
    return stored.contains(':');
  }

  static Future<String> _decryptNew(String stored) async {
    final separatorIdx = stored.indexOf(':');
    if (separatorIdx < 0) {
      throw const FormatException('Invalid encrypted format');
    }
    final ivBytes = base64Decode(stored.substring(0, separatorIdx));
    final cipherBase64 = stored.substring(separatorIdx + 1);
    final key = await _getKey(_keyAlias, create: false);
    return compute(_openSic, (key.bytes, ivBytes, cipherBase64));
  }

  static Future<String> _decryptLegacy(String stored) {
    final key = enc.Key.fromUtf8(_legacyKey);
    return compute(_openSic, (key.bytes, Uint8List(16), stored));
  }

  static String _sealAuthenticated((String, Uint8List, String, String) input) {
    final (plaintext, key, alias, context) = input;
    final nonce = enc.IV(SecureKeyStore._randomBytes(12));
    final cipher = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.gcm));
    final data = cipher
        .encrypt(
          plaintext,
          iv: nonce,
          associatedData: Uint8List.fromList(utf8.encode('$alias|$context|v2')),
        )
        .base64;
    return 'v2:${base64Encode(utf8.encode(jsonEncode({'key': alias, 'context': context, 'nonce': nonce.base64, 'data': data})))}';
  }

  static (String, String, Uint8List, String) _parseAuthenticated(String input) {
    final decoded = jsonDecode(utf8.decode(base64Decode(input)));
    if (decoded is! Map<String, dynamic> ||
        decoded['key'] is! String ||
        decoded['context'] is! String ||
        decoded['nonce'] is! String ||
        decoded['data'] is! String) {
      throw const FormatException('Malformed secure envelope.');
    }
    final nonce = base64Decode(decoded['nonce'] as String);
    if (nonce.length != 12) throw const FormatException('Invalid GCM nonce.');
    return (
      decoded['key'] as String,
      decoded['context'] as String,
      nonce,
      decoded['data'] as String,
    );
  }

  static String _openAuthenticated(
    (Uint8List, Uint8List, String, String, String) input,
  ) {
    final (key, nonce, data, alias, context) = input;
    return enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    ).decrypt64(
      data,
      iv: enc.IV(nonce),
      associatedData: Uint8List.fromList(utf8.encode('$alias|$context|v2')),
    );
  }

  static String _openSic((Uint8List, Uint8List, String) input) => enc.Encrypter(
    enc.AES(enc.Key(input.$1), mode: enc.AESMode.sic),
  ).decrypt64(input.$3, iv: enc.IV(input.$2));

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
