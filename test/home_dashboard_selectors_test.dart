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
}) {
  return Account(
    id: id,
    name: id,
    type: type,
    currency: currency,
    openingBalance: Money(amountMinor: openingMinor, currency: currency),
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
