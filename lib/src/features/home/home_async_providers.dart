import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../ledger/ledger_selectors.dart';
import 'home_dashboard_selectors.dart';

final homeTotalBalanceProvider = FutureProvider.family.autoDispose<Money, ({String? accountId, String? targetCurrency})>((ref, args) async {
  final state = ref.watch(ledgerProvider);
  return compute(_totalBalanceCompute, (state: state, accountId: args.accountId, targetCurrency: args.targetCurrency));
});

Money _totalBalanceCompute(({LedgerState state, String? accountId, String? targetCurrency}) args) {
  return totalBalance(args.state, accountId: args.accountId, targetCurrency: args.targetCurrency);
}

final homeFlowForPeriodProvider = FutureProvider.family.autoDispose<({Money income, Money expense}), ({String period, String? accountId, String? targetCurrency})>((ref, args) async {
  final state = ref.watch(ledgerProvider);
  return compute(_flowForPeriodCompute, (state: state, period: args.period, accountId: args.accountId, targetCurrency: args.targetCurrency));
});

({Money income, Money expense}) _flowForPeriodCompute(({LedgerState state, String period, String? accountId, String? targetCurrency}) args) {
  return flowForPeriod(args.state, args.period, accountId: args.accountId, targetCurrency: args.targetCurrency);
}

final homeCurrencySnapshotProvider = FutureProvider.autoDispose<CurrencyConversionSnapshot>((ref) async {
  final state = ref.watch(ledgerProvider);
  return compute(currencyConversionSnapshot, state);
});

final homeNetWorthProvider = FutureProvider.autoDispose<({Money total, Money assets, Money liabilities})>((ref) async {
  final state = ref.watch(ledgerProvider);
  return compute(netWorth, state);
});

final homeBalanceTrendProvider = FutureProvider.family.autoDispose<List<BalanceTrendPoint>, ({DateTime? start, DateTime? end})>((ref, args) async {
  final state = ref.watch(ledgerProvider);
  return compute(_balanceTrendCompute, (state: state, start: args.start, end: args.end));
});

List<BalanceTrendPoint> _balanceTrendCompute(({LedgerState state, DateTime? start, DateTime? end}) args) {
  return balanceTrendForRange(args.state, start: args.start, end: args.end);
}

final homeAccountBalanceMapProvider = FutureProvider.autoDispose<Map<String, Money>>((ref) async {
  final state = ref.watch(ledgerProvider);
  return compute(accountBalanceMap, state);
});