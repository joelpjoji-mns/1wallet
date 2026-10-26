import 'package:flutter/foundation.dart';
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
      ref.watch(
        ledgerProvider.select(
          (s) => (
            s.accounts,
            s.transactions,
            s.exchangeRates,
            s.preferences.displayCurrency,
          ),
        ),
      );
      final state = ref.read(ledgerProvider);
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
      ref.watch(
        ledgerProvider.select(
          (s) => (
            s.accounts,
            s.transactions,
            s.exchangeRates,
            s.preferences.displayCurrency,
          ),
        ),
      );
      final state = ref.read(ledgerProvider);
      return flowForPeriod(
        state,
        args.period,
        accountId: args.accountId,
        targetCurrency: args.targetCurrency,
      );
    });

final homeBalanceTrendProvider = FutureProvider.family
    .autoDispose<List<BalanceTrendPoint>, ({DateTime? start, DateTime? end})>((
      ref,
      args,
    ) async {
      final state = ref.watch(ledgerProvider);
      return await compute((msg) {
        return balanceTrendForRange(msg.state, start: msg.start, end: msg.end);
      }, (state: state, start: args.start, end: args.end));
    });

final homeBalanceFutureTrendProvider = FutureProvider.family
    .autoDispose<List<BalanceTrendPoint>, ({DateTime start, DateTime end})>((
      ref,
      args,
    ) async {
      final state = ref.watch(ledgerProvider);
      return await compute((msg) {
        return balanceFutureTrendForRange(
          msg.state,
          start: msg.start,
          end: msg.end,
        );
      }, (state: state, start: args.start, end: args.end));
    });

final homeAccountBalanceMapProvider = Provider.autoDispose<Map<String, Money>>((
  ref,
) {
  ref.watch(
    ledgerProvider.select(
      (s) => (s.accounts, s.transactions),
    ),
  );
  final state = ref.read(ledgerProvider);
  return accountBalanceMap(state);
});

final homeCurrencyBreakdownProvider = Provider.family
    .autoDispose<List<Money>, String?>((ref, accountId) {
      ref.watch(
        ledgerProvider.select(
          (s) => (s.accounts, s.transactions),
        ),
      );
      final state = ref.read(ledgerProvider);
      return balanceBreakdownByCurrency(state, accountId: accountId);
    });
