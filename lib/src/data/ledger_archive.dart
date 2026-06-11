import 'dart:convert';

import 'ledger_codec.dart';
import 'ledger_models.dart';

const oneWalletArchiveFormat = 'onewallet.ledger.archive';
const oneWalletArchiveVersion = 1;

String encodeLedgerArchive(
  LedgerState state, {
  String source = 'flutter-local',
  DateTime? exportedAt,
}) {
  final payload = encodeLedgerState(state);
  return jsonEncode({
    'format': oneWalletArchiveFormat,
    'archiveVersion': oneWalletArchiveVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'source': source,
    'ledgerStateVersion': state.version,
    'checksum': fnv1a32Hex(payload),
    'summary': {
      'accounts': state.accounts.length,
      'categories': state.categories.length,
      'transactions': state.transactions.length,
      'budgets': state.budgets.length,
      'goals': state.goals.length,
      'captureCandidates': state.captureCandidates.length,
      'importBatches': state.importBatches.length,
    },
    'payload': payload,
  });
}

LedgerState decodeLedgerArchive(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Archive root must be a JSON object.');
  }
  if (decoded['format'] != oneWalletArchiveFormat) {
    throw const FormatException('Unsupported 1Wallet archive format.');
  }
  if (decoded['archiveVersion'] != oneWalletArchiveVersion) {
    throw const FormatException('Unsupported 1Wallet archive version.');
  }
  final payload = decoded['payload'];
  if (payload is! String || payload.trim().isEmpty) {
    throw const FormatException('Archive payload is missing.');
  }
  final checksum = decoded['checksum'];
  if (checksum is! String || checksum != fnv1a32Hex(payload)) {
    throw const FormatException('Archive checksum mismatch.');
  }
  return decodeLedgerState(payload);
}

String fnv1a32Hex(String source) {
  const offsetBasis = 0x811c9dc5;
  const prime = 0x01000193;
  var hash = offsetBasis;
  for (final byte in utf8.encode(source)) {
    hash ^= byte;
    hash = (hash * prime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
