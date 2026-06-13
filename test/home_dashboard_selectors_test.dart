import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_dashboard_selectors.dart';

void main() {
  test('balance trend applies cleared daily deltas and ignores scheduled', () {
    final state = _ledger(
      accounts: [
        _account(id: 'bank', openingMinor: 10000),
        _account(id: 'cash', type: 'cash', openingMinor: 0),
      ],
      transactions: [
        _tx(
          id: 'income',
          type: 'income',
          accountId: 'bank',
          amountMinor: 2000,
          date: DateTime(2026, 1, 2),
        ),
        _tx(
          id: 'expense',
          type: 'expense',
          accountId: 'bank',
          amountMinor: 500,
          date: DateTime(2026, 1, 3),
        ),
        _tx(
          id: 'transfer',
          type: 'transfer',
          accountId: 'bank',
          counterAccountId: 'cash',
          amountMinor: 1000,
          date: DateTime(2026, 1, 4),
        ),
        _tx(
          id: 'scheduled',
          type: 'expense',
          status: 'scheduled',
          accountId: 'bank',
          amountMinor: 3000,
          date: DateTime(2026, 1, 4),
        ),
      ],
    );

    final trend = balanceTrendForRange(
      state,
      start: DateTime(2026, 1),
      end: DateTime(2026, 1, 4),
    );

    expect(trend.map((point) => point.balance.amountMinor), [
      10000,
      12000,
      11500,
      11500,
    ]);
  });

  test('balance breakdown matches default total-balance account scope', () {
    final state = _ledger(
      accounts: [
        _account(id: 'bank', openingMinor: 10000),
        _account(
          id: 'gbp-excluded',
          currency: 'GBP',
          openingMinor: 2500,
          includeInTotals: false,
        ),
        _account(
          id: 'usd-archived',
          currency: 'USD',
          openingMinor: 9900,
          isArchived: true,
        ),
      ],
    );

    final breakdown = balanceBreakdownByCurrency(state);

    expect(breakdown.map((money) => money.currency), ['INR']);
    expect(breakdown.single.amountMinor, 10000);
  });

  test('balance breakdown includes every account currency in total scope', () {
    final state = _ledger(
      accounts: [
        _account(id: 'bank', openingMinor: 10000),
        _account(id: 'gbp', currency: 'GBP', openingMinor: 2500),
      ],
    );

    final breakdown = balanceBreakdownByCurrency(state);

    expect(breakdown.map((money) => money.currency), ['INR', 'GBP']);
    expect(breakdown.map((money) => money.amountMinor), [10000, 2500]);
  });

  test('balance breakdown reflects selected account scope', () {
    final state = _ledger(
      accounts: [
        _account(id: 'bank', openingMinor: 10000),
        _account(
          id: 'gbp-excluded',
          currency: 'GBP',
          openingMinor: 0,
          includeInTotals: false,
        ),
      ],
    );

    final allAccountsBreakdown = balanceBreakdownByCurrency(state);
    final selectedBreakdown = balanceBreakdownByCurrency(
      state,
      accountId: 'gbp-excluded',
    );

    expect(allAccountsBreakdown.map((money) => money.currency), ['INR']);
    expect(selectedBreakdown.map((money) => money.currency), ['GBP']);
    expect(selectedBreakdown.single.amountMinor, 0);
  });

  test('balance breakdown shows every native currency net in selected scope', () {
    final state = _ledger(
      accounts: [
        _account(id: 'cash', type: 'cash', currency: 'INR', openingMinor: 0),
      ],
      transactions: [
        _tx(
          id: 'cash-gbp-in',
          type: 'income',
          accountId: 'cash',
          amountMinor: 500,
          currency: 'GBP',
          baseAmountMinor: 52500,
          date: DateTime(2026, 6, 1),
        ),
        _tx(
          id: 'cash-gbp-out',
          type: 'expense',
          accountId: 'cash',
          amountMinor: 500,
          currency: 'GBP',
          baseAmountMinor: 52500,
          date: DateTime(2026, 6, 2),
        ),
        _tx(
          id: 'cash-usd-in',
          type: 'income',
          accountId: 'cash',
          amountMinor: 1200,
          currency: 'USD',
          baseAmountMinor: 100000,
          date: DateTime(2026, 6, 3),
        ),
      ],
    );

    final breakdown = balanceBreakdownByCurrency(state, accountId: 'cash');

    expect(breakdown.map((money) => money.currency), ['INR', 'USD', 'GBP']);
    expect(breakdown.map((money) => money.amountMinor), [0, 1200, 0]);
  });

  test('currency snapshot prefers explicit latest exchange rate', () {
    final state = _ledger(
      accounts: [_account(id: 'gbp', currency: 'GBP', openingMinor: 2500)],
      exchangeRates: [
        ExchangeRateRecord(
          base: 'GBP',
          quote: 'INR',
          rate: 127.88,
          asOfDate: DateTime(2026, 6, 9),
          provider: 'frankfurter.app',
          source: 'refresh',
        ),
      ],
    );

    final snapshot = currencyConversionSnapshot(state);

    expect(snapshot.quoteCurrency, 'GBP');
    expect(snapshot.isExplicitRate, isTrue);
    expect(snapshot.convertedUnit?.amountMinor, 12788);
    expect(snapshot.exposure.single.currency, 'GBP');
  });

  test('currency snapshot can infer rate from latest foreign movement', () {
    final state = _ledger(
      transactions: [
        _tx(
          id: 'coffee',
          type: 'expense',
          accountId: 'bank',
          amountMinor: 100,
          currency: 'GBP',
          baseAmountMinor: 12800,
          date: DateTime(2026, 6, 8),
        ),
      ],
    );

    final snapshot = currencyConversionSnapshot(state);

    expect(snapshot.quoteCurrency, 'GBP');
    expect(snapshot.isExplicitRate, isFalse);
    expect(snapshot.convertedUnit?.amountMinor, 12800);
    expect(snapshot.sourceLabel, 'Latest ledger movement');
  });
}

LedgerState _ledger({
  List<Account>? accounts,
  List<TransactionRecord>? transactions,
  List<ExchangeRateRecord>? exchangeRates,
}) {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: const LedgerPreferences(),
    accounts: accounts ?? [_account(id: 'bank', openingMinor: 0)],
    categories: const [],
    transactions: transactions ?? const [],
    budgets: const [],
    goals: const [],
    captureCandidates: const [],
    exchangeRates: exchangeRates ?? const [],
  );
}

Account _account({
  required String id,
  String type = 'bank',
  String currency = 'INR',
  required int openingMinor,
  bool includeInTotals = true,
  bool isArchived = false,
}) {
  return Account(
    id: id,
    name: id,
    type: type,
    currency: currency,
    openingBalance: Money(amountMinor: openingMinor, currency: currency),
    includeInTotals: includeInTotals,
    isArchived: isArchived,
  );
}

TransactionRecord _tx({
  required String id,
  required String type,
  String status = 'cleared',
  required String accountId,
  String? counterAccountId,
  required int amountMinor,
  int? baseAmountMinor,
  String currency = 'INR',
  required DateTime date,
}) {
  return TransactionRecord(
    id: id,
    type: type,
    status: status,
    source: 'test',
    accountId: accountId,
    counterAccountId: counterAccountId,
    amount: Money(amountMinor: amountMinor, currency: currency),
    baseAmount: Money(
      amountMinor: baseAmountMinor ?? amountMinor,
      currency: 'INR',
    ),
    occurredAt: date,
  );
}
