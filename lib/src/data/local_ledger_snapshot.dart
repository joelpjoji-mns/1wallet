import 'dart:convert';

import 'ledger_codec.dart';
import 'ledger_models.dart';

String encodeLocalLedgerSnapshot(LedgerState state) => jsonEncode({
  'format': 'onewallet.local.v2',
  'owner': state.userId,
  'revision': state.localRevision,
  'ingressReceipts': state.ingressReceipts.toList(),
  'authoritativeEmpty': state.hasAuthoritativeEmptyWallet,
  'ledger': encodeLedgerState(state),
});

LedgerState decodeLocalLedgerSnapshot(String source) {
  final envelope = jsonDecode(source);
  if (envelope is! Map<String, dynamic> ||
      envelope['format'] != 'onewallet.local.v2') {
    if (envelope is Map && envelope.containsKey('format')) {
      throw const FormatException('Unsupported local wallet format.');
    }
    return decodeLedgerState(source);
  }
  final payload = envelope['ledger'];
  final revision = envelope['revision'];
  final receipts = envelope['ingressReceipts'];
  final authoritativeEmpty = envelope['authoritativeEmpty'];
  if (payload is! String ||
      revision is! int ||
      revision < 0 ||
      receipts is! List ||
      receipts.any((id) => id is! String) ||
      (authoritativeEmpty != null && authoritativeEmpty is! bool)) {
    throw const FormatException('Invalid local wallet envelope.');
  }
  final ledger = decodeLedgerState(payload);
  if (ledger.userId != envelope['owner']) {
    throw const FormatException('Local wallet owner does not match.');
  }
  return ledger.copyWith(
    localRevision: revision,
    ingressReceipts: Set<String>.unmodifiable(receipts.cast<String>()),
    hasAuthoritativeEmptyWallet: authoritativeEmpty == true,
  );
}
