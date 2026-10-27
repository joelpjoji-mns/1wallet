import 'ledger_models.dart';

/// Combines two complete wallets for the offline → Google "merge" choice.
///
/// [cloud] is the base: its preferences, owner and any record whose id exists
/// on both sides are kept. Records that exist only in [local] are appended,
/// so no local account, category, transaction, capture or import is dropped.
/// Record ids are generated per record, so ids shared by both sides denote
/// the same record (for example a built-in category).
///
/// Both wallets must already belong to the same owner; secure account fields
/// are expected to be wrapped for that owner (see `rekeyLedgerForOwner`).
LedgerState mergeLedgerStates({
  required LedgerState cloud,
  required LedgerState local,
}) {
  if (cloud.userId != local.userId) {
    throw ArgumentError('Only wallets of the same owner can be merged.');
  }
  final accounts = _union(cloud.accounts, local.accounts, (item) => item.id);
  final enabledCurrencies = <String>{
    for (final currency in cloud.preferences.enabledCurrencies)
      currency.toUpperCase(),
    for (final currency in local.preferences.enabledCurrencies)
      currency.toUpperCase(),
    for (final account in accounts) account.currency.toUpperCase(),
  }.toList()..sort();
  return cloud.copyWith(
    accounts: accounts,
    categories: _union(cloud.categories, local.categories, (item) => item.id),
    transactions: _union(
      cloud.transactions,
      local.transactions,
      (item) => item.id,
    ),
    captureCandidates: _union(
      cloud.captureCandidates,
      local.captureCandidates,
      (item) => item.id,
    ),
    importBatches: _union(
      cloud.importBatches,
      local.importBatches,
      (item) => item.id,
    ),
    exchangeRates: _union(
      cloud.exchangeRates,
      local.exchangeRates,
      (item) => '${item.base}|${item.quote}|${item.asOfDate.toIso8601String()}',
    ),
    preferences: cloud.preferences.copyWith(
      enabledCurrencies: enabledCurrencies,
    ),
    ingressReceipts: Set<String>.unmodifiable({
      ...cloud.ingressReceipts,
      ...local.ingressReceipts,
    }),
    hasAuthoritativeEmptyWallet: false,
  );
}

List<T> _union<T>(List<T> base, List<T> extra, String Function(T) idOf) {
  final seen = <String>{for (final item in base) idOf(item)};
  return [
    ...base,
    for (final item in extra)
      if (seen.add(idOf(item))) item,
  ];
}
