import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../ledger/ledger_selectors.dart';
import 'home_dashboard_selectors.dart';

final homeTotalBalanceProvider = Provider.family
    .autoDispose<Money, ({String? accountId, String? targetCurrency})>((
      ref,
      args,
    ) {
      final state = ref.watch(ledgerProvider);
      return totalBalance(
        state,
        accountId: args.accountId,
        targetCurrency: args.targetCurrency,
      );
    });

final homeFlowForPeriodProvider = Provider.family
    .autoDispose<
      ({Money income, Money expense}),
      ({String period, String? accountId, String? targetCurrency})
    >((ref, args) {
      final state = ref.watch(ledgerProvider);
      return flowForPeriod(
        state,
        args.period,
        accountId: args.accountId,
        targetCurrency: args.targetCurrency,
      );
    });

final homeCurrencySnapshotProvider =
    Provider.autoDispose<CurrencyConversionSnapshot?>((ref) {
      final state = ref.watch(ledgerProvider);
      return currencyConversionSnapshot(state);
    });

final homeNetWorthProvider =
    Provider.autoDispose<({Money total, Money assets, Money liabilities})>((
      ref,
    ) {
      final state = ref.watch(ledgerProvider);
      return netWorth(state);
    });

final homeBalanceTrendProvider = Provider.family
    .autoDispose<List<BalanceTrendPoint>, ({DateTime? start, DateTime? end})>((
      ref,
      args,
    ) {
      final state = ref.watch(ledgerProvider);
      return balanceTrendForRange(state, start: args.start, end: args.end);
    });

final homeAccountBalanceMapProvider = Provider.autoDispose<Map<String, Money>>((
  ref,
) {
  final state = ref.watch(ledgerProvider);
  return accountBalanceMap(state);
});

final homeCurrencyBreakdownProvider = Provider.family
    .autoDispose<List<Money>, String?>((ref, accountId) {
      final state = ref.watch(ledgerProvider);
      return balanceBreakdownByCurrency(state, accountId: accountId);
    });
