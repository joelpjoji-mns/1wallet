import 'dart:convert';
import '../data/ledger_codec.dart';
import '../data/ledger_models.dart';

LedgerState decodeReactNativeOneWalletArchive(
  String archiveContent, {
  required String userId,
  // `expectedChecksum` is advisory only: we do not have a matching checksum
  // implementation for the legacy React Native archive format, so it is
  // accepted for API compatibility but intentionally not verified here.
  String? expectedChecksum,
  int? expectedLedgerStateVersion,
}) {
  final decoded = jsonDecode(archiveContent);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Archive root must be a JSON object.');
  }

  // The old React Native archive has the state directly under the 'ledger' key.
  final ledgerJson = decoded['ledger'];
  if (ledgerJson == null) {
    // If it happens to be the new format, fallback to payload
    if (decoded['payload'] != null) {
      final payloadStr = decoded['payload'] as String;
      return decodeLedgerState(payloadStr).copyWith(userId: userId);
    }
    throw const FormatException('Archive ledger is missing.');
  }

  final payloadStr = jsonEncode(ledgerJson);
  return decodeLedgerState(payloadStr).copyWith(userId: userId);
}

// Checksum is advisory/unenforced: we don't have a compatible checksum
// implementation for the legacy archive, so this always returns empty and
// callers must not treat a mismatch as a hard failure.
String reactNativeLedgerChecksum(String content) => '';
const reactNativeArchiveFormat = 'rn-archive';
const reactNativeArchiveVersion = 1;
