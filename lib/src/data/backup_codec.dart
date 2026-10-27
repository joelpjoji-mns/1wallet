import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../utils/secure_key_store.dart';
import 'ledger_archive.dart';
import 'ledger_models.dart';

const _format = 'onewallet.encrypted.backup';
const _iterations = 600000;
const maximumBackupEnvelopeCharacters = 64 * 1024 * 1024;

void ensureSupportedBackupSize(int characterCount) {
  if (characterCount < 0 || characterCount > maximumBackupEnvelopeCharacters) {
    throw const FormatException('Backup exceeds the supported size.');
  }
}

Uint8List _random(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Uint8List _derive((String, Uint8List) input) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(input.$2, _iterations, 32));
  return derivator.process(Uint8List.fromList(utf8.encode(input.$1)));
}

Uint8List _aad(String salt) => Uint8List.fromList(
  utf8.encode('$_format|1|PBKDF2-HMAC-SHA256|$_iterations|$salt'),
);

String _seal((String, Uint8List, String) input) {
  final nonce = enc.IV(_random(12));
  final cipher = enc.Encrypter(
    enc.AES(enc.Key(input.$2), mode: enc.AESMode.gcm),
  );
  final envelope = jsonEncode({
    'format': _format,
    'version': 1,
    'kdf': 'PBKDF2-HMAC-SHA256',
    'iterations': _iterations,
    'salt': input.$3,
    'nonce': nonce.base64,
    'data': cipher
        .encrypt(input.$1, iv: nonce, associatedData: _aad(input.$3))
        .base64,
  });
  ensureSupportedBackupSize(envelope.length);
  return envelope;
}

Future<String> encodeDeviceBackup(LedgerState state) async {
  final archive = await compute(encodeLedgerArchive, state);
  final envelope = await SecureKeyStore.encrypt(
    archive,
    userId: state.userId,
    purpose: 'backup',
  );
  ensureSupportedBackupSize(envelope.length);
  return envelope;
}

Future<LedgerState> _rewrapFields(
  LedgerState ledger, {
  required bool exporting,
  required String targetUserId,
}) async {
  final accounts = <Account>[];
  for (final account in ledger.accounts) {
    final details = account.encryptedDetails;
    if (details == null) {
      accounts.add(account);
      continue;
    }
    final next = <String, String>{};
    for (final entry in details.entries) {
      if (statementMetadataKeys.contains(entry.key)) {
        next[entry.key] = entry.value;
      } else if (exporting) {
        final versioned = entry.value.startsWith('v2:');
        next[entry.key] = await SecureKeyStore.decrypt(
          entry.value,
          userId: versioned ? ledger.userId : null,
          context: versioned
              ? SecureKeyStore.fieldContext(account.id, entry.key)
              : null,
        );
      } else {
        next[entry.key] = await SecureKeyStore.encrypt(
          entry.value,
          userId: targetUserId,
          context: SecureKeyStore.fieldContext(account.id, entry.key),
        );
      }
    }
    accounts.add(account.copyWith(encryptedDetails: next));
  }
  return ledger.copyWith(accounts: accounts);
}

Future<String> encodePortableBackup(
  LedgerState state,
  String passphrase,
) async {
  if (passphrase.isEmpty) {
    throw ArgumentError('A backup passphrase is required.');
  }
  final transport = await _rewrapFields(
    state,
    exporting: true,
    targetUserId: state.userId,
  );
  final archive = await compute(encodeLedgerArchive, transport);
  final salt = _random(16);
  final key = await compute(_derive, (passphrase, salt));
  return compute(_seal, (archive, key, base64Encode(salt)));
}

Future<LedgerState> decodeBackup(
  String source, {
  String? passphrase,
  required String targetUserId,
  bool allowLegacy = false,
  bool rewrapForImport = false,
}) async {
  ensureSupportedBackupSize(source.length);
  if (source.startsWith('v2:')) {
    final archive = await SecureKeyStore.decrypt(source, purpose: 'backup');
    final ledger = await compute(decodeLedgerArchive, archive);
    return _rekeyImported(ledger, targetUserId, rewrapForImport);
  }
  final envelope = await compute(jsonDecode, source);
  if (envelope is! Map<String, dynamic> || envelope['format'] != _format) {
    if (!allowLegacy) {
      throw const FormatException(
        'Legacy backup requires explicit confirmation.',
      );
    }
    final ledger = await compute(decodeLedgerArchive, source);
    return _rekeyImported(ledger, targetUserId, rewrapForImport);
  }
  if (envelope['version'] != 1 ||
      envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
      envelope['iterations'] != _iterations ||
      envelope['salt'] is! String ||
      envelope['nonce'] is! String ||
      envelope['data'] is! String) {
    throw const FormatException('Unsupported or malformed encrypted backup.');
  }
  if (passphrase == null || passphrase.isEmpty) {
    throw const FormatException('This backup requires its passphrase.');
  }
  final saltText = envelope['salt'] as String;
  final salt = base64Decode(saltText);
  final nonce = enc.IV.fromBase64(envelope['nonce'] as String);
  if (salt.length != 16 || nonce.bytes.length != 12) {
    throw const FormatException('Invalid backup salt or nonce.');
  }
  final key = await compute(_derive, (passphrase, salt));
  final archive = await compute(_open, (
    envelope['data'] as String,
    key,
    nonce.bytes,
    saltText,
  ));
  final ledger = await compute(decodeLedgerArchive, archive);
  return _rewrapFields(
    ledger,
    exporting: false,
    targetUserId: targetUserId == 'local-user' ? ledger.userId : targetUserId,
  );
}

String _open((String, Uint8List, Uint8List, String) input) {
  final cipher = enc.Encrypter(
    enc.AES(enc.Key(input.$2), mode: enc.AESMode.gcm),
  );
  try {
    return cipher.decrypt64(
      input.$1,
      iv: enc.IV(input.$3),
      associatedData: _aad(input.$4),
    );
  } on InvalidCipherTextException {
    throw const FormatException(
      'The backup passphrase is incorrect or the file was modified.',
    );
  }
}

Future<LedgerState> _rekeyImported(
  LedgerState ledger,
  String target,
  bool importing,
) async {
  if (!importing || target == 'local-user' || target == ledger.userId) {
    return ledger;
  }
  final transport = await _rewrapFields(
    ledger,
    exporting: true,
    targetUserId: ledger.userId,
  );
  return _rewrapFields(transport, exporting: false, targetUserId: target);
}
