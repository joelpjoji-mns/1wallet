import 'dart:math' as math;

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';

class BalanceTrendPoint {
  const BalanceTrendPoint({required this.date, required this.balance});

  final DateTime date;
  final Money balance;
}

class CurrencyConversionSnapshot {
  const CurrencyConversionSnapshot({
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.rate,
    required this.asOfDate,
    required this.sourceLabel,
    required this.isExplicitRate,
    required this.convertedUnit,
    required this.exposure,
  });

  final String baseCurrency;
  final String? quoteCurrency;
  final double? rate;
  final DateTime? asOfDate;
  final String sourceLabel;
  final bool isExplicitRate;
  final Money? convertedUnit;
  final List<Money> exposure;
}

List<BalanceTrendPoint> balanceTrendForRange(
  LedgerState state, {
  DateTime? start,
  DateTime? end,
}) {
  final now = DateTime.now();
  final rangeEnd = end ?? now;
  DateTime earliest = now;
  for (final tx in state.transactions) {
    if (tx.occurredAt.isBefore(earliest)) earliest = tx.occurredAt;
  }
  final rangeStart = start ?? earliest;
  if (rangeEnd.isBefore(rangeStart)) return const [];

  final includedAccounts = {
    for (final account in state.accounts)
      if (account.includeInNetWorth && account.type != 'loan') account.id,
  };
  final displayCurrency = state.preferences.displayCurrency;
  var running = state.accounts
      .where((account) => includedAccounts.contains(account.id))
      .fold<int>(0, (sum, account) {
        final converted = convertMoneyForDisplay(
          state,
          account.openingBalance,
          displayCurrency,
        );
        return sum + converted.amountMinor;
      });

  final txs = state.transactions
      .where((tx) => tx.status != 'scheduled' && tx.status != 'void')
      .toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  for (final tx in txs) {
    if (tx.occurredAt.isBefore(rangeStart)) {
      running += _includedTotalDelta(state, tx, includedAccounts);
    }
  }

  final points = <BalanceTrendPoint>[];
  points.add(
    BalanceTrendPoint(
      date: rangeStart,
      balance: Money(amountMinor: running, currency: displayCurrency),
    ),
  );

  DateTime? lastTime;
  for (final tx in txs) {
    if (tx.occurredAt.isBefore(rangeStart)) continue;
    if (tx.occurredAt.isAfter(rangeEnd)) break;
    
    final delta = _includedTotalDelta(state, tx, includedAccounts);
    if (delta == 0) continue;
    
    running += delta;
    
    if (lastTime == tx.occurredAt && points.isNotEmpty) {
      points.last = BalanceTrendPoint(
        date: tx.occurredAt,
        balance: Money(amountMinor: running, currency: displayCurrency),
      );
    } else {
      points.add(
        BalanceTrendPoint(
          date: tx.occurredAt,
          balance: Money(amountMinor: running, currency: displayCurrency),
        ),
      );
      lastTime = tx.occurredAt;
    }
  }

  if (points.last.date.isBefore(rangeEnd)) {
    points.add(
      BalanceTrendPoint(
        date: rangeEnd,
        balance: Money(amountMinor: running, currency: displayCurrency),
      ),
    );
  }

  return points;
}

List<Money> balanceBreakdownByCurrency(
  LedgerState state, {
  String? accountId,
}) {
  final accounts = accountId != null
      ? (accountId == 'cash_group'
            ? state.accounts.where((a) => a.type == 'cash' && !a.isArchived)
            : state.accounts.where((a) => a.id == accountId && !a.isArchived))
      : state.accounts.where(
          (account) => !account.isArchived && account.includeInTotals,
        );
  final totals = <String, int>{};
  for (final account in accounts) {
    for (final money in _accountCurrencyNet(state, account)) {
      _addMoney(totals, money);
    }
  }

  final items = totals.entries
      .map((entry) => Money(amountMinor: entry.value, currency: entry.key))
      .toList();
  final displayCurrency = state.preferences.displayCurrency.toUpperCase();
  items.sort((left, right) {
    final leftIsDisplay = left.currency.toUpperCase() == displayCurrency;
    final rightIsDisplay = right.currency.toUpperCase() == displayCurrency;
    if (leftIsDisplay && !rightIsDisplay) return -1;
    if (!leftIsDisplay && rightIsDisplay) return 1;
    final amountCompare = right.amountMinor.abs().compareTo(
      left.amountMinor.abs(),
    );
    return amountCompare == 0
        ? left.currency.compareTo(right.currency)
        : amountCompare;
  });
  return items;
}

List<Money> _accountCurrencyNet(LedgerState state, Account account) {
  final totals = <String, int>{};
  _addMoney(totals, account.openingBalance.copyWith(currency: account.currency));

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
      continue;
    }

    if (transaction.accountId == account.id) {
      final delta = sourceDelta(transaction);
      if (delta != 0) {
        final money = _sourceCurrencyMoney(transaction, account);
        _addSignedMoney(totals, money, delta);
      }
    }

    if (transaction.counterAccountId == account.id) {
      final delta = counterDelta(transaction);
      if (delta != 0) {
        final money = _counterCurrencyMoney(transaction, account);
        _addSignedMoney(totals, money, delta);
      }
    }
  }

  return totals.entries
      .map((entry) => Money(amountMinor: entry.value, currency: entry.key))
      .toList();
}

Money _sourceCurrencyMoney(TransactionRecord transaction, Account account) {
  if (account.type == 'cash') return cashSourceTransactionMoney(transaction);
  return transaction.amount;
}

Money _counterCurrencyMoney(TransactionRecord transaction, Account account) {
  if (account.type == 'cash') {
    return cashDestinationTransferMoney(transaction, account);
  }
  return transaction.counterAmount ?? transaction.amount;
}

void _addSignedMoney(Map<String, int> totals, Money money, int signedDelta) {
  final signedAmount = signedDelta < 0
      ? -money.amountMinor.abs()
      : money.amountMinor.abs();
  _addMoney(totals, money.copyWith(amountMinor: signedAmount));
}

void _addMoney(Map<String, int> totals, Money money) {
  final currency = money.currency.toUpperCase();
  totals.update(
    currency,
    (amountMinor) => amountMinor + money.amountMinor,
    ifAbsent: () => money.amountMinor,
  );
}

CurrencyConversionSnapshot currencyConversionSnapshot(LedgerState state) {
  final base = state.preferences.baseCurrency.toUpperCase();
  final exposure = foreignCurrencyExposure(state);
  final quote = _preferredQuoteCurrency(state, base, exposure);
  if (quote == null) {
    return CurrencyConversionSnapshot(
      baseCurrency: base,
      quoteCurrency: null,
      rate: null,
      asOfDate: null,
      sourceLabel: 'No foreign currency activity yet',
      isExplicitRate: false,
      convertedUnit: null,
      exposure: exposure,
    );
  }

  final explicit = _rateBetween(state, quote, base);
  final inferred = explicit ?? _inferredRateBetween(state, quote, base);
  final rate = inferred?.rate;
  final converted = rate == null
      ? null
      : Money(
          amountMinor: (rate * math.pow(10, minorUnits(base))).round(),
          currency: base,
        );
  return CurrencyConversionSnapshot(
    baseCurrency: base,
    quoteCurrency: quote,
    rate: rate,
    asOfDate: inferred?.asOfDate,
    sourceLabel: inferred?.sourceLabel ?? 'Add or refresh an FX rate',
    isExplicitRate: explicit != null,
    convertedUnit: converted,
    exposure: exposure,
  );
}

List<Money> foreignCurrencyExposure(LedgerState state) {
  final base = state.preferences.baseCurrency.toUpperCase();
  final totals = <String, int>{};
  final balances = accountBalanceMap(state);
  for (final account in state.accounts) {
    if (account.isArchived) continue;
    final currency = account.currency.toUpperCase();
    if (currency == base) continue;
    final balance = accountBalanceFromMap(balances, account);
    totals.update(
      currency,
      (value) => value + balance.amountMinor,
      ifAbsent: () => balance.amountMinor,
    );
  }
  final items = totals.entries
      .map((entry) => Money(amountMinor: entry.value, currency: entry.key))
      .toList();
  items.sort((left, right) {
    final amountCompare = right.amountMinor.abs().compareTo(
      left.amountMinor.abs(),
    );
    return amountCompare == 0
        ? left.currency.compareTo(right.currency)
        : amountCompare;
  });
  return items;
}

int _includedTotalDelta(
  LedgerState state,
  TransactionRecord transaction,
  Set<String> accountIds,
) {
  var delta = 0;
  if (accountIds.contains(transaction.accountId)) {
    delta += convertMoneyForDisplay(
      state,
      Money(
        amountMinor: sourceDelta(transaction),
        currency: transaction.amount.currency,
      ),
    ).amountMinor;
  }
  if (transaction.counterAccountId != null &&
      accountIds.contains(transaction.counterAccountId)) {
    delta += convertMoneyForDisplay(
      state,
      Money(
        amountMinor: counterDelta(transaction),
        currency: (transaction.counterAmount ?? transaction.amount).currency,
      ),
    ).amountMinor;
  }
  return delta;
}

_RateSnapshot? _rateBetween(LedgerState state, String base, String quote) {
  final direct = _latestExchangeRate(state, base, quote);
  if (direct != null) {
    return _RateSnapshot(
      rate: direct.rate,
      asOfDate: direct.asOfDate,
      sourceLabel: direct.provider ?? direct.source ?? 'Saved FX rate',
    );
  }
  final inverse = _latestExchangeRate(state, quote, base);
  if (inverse != null && inverse.rate != 0) {
    return _RateSnapshot(
      rate: 1 / inverse.rate,
      asOfDate: inverse.asOfDate,
      sourceLabel: inverse.provider ?? inverse.source ?? 'Saved FX rate',
    );
  }
  return null;
}

ExchangeRateRecord? _latestExchangeRate(
  LedgerState state,
  String base,
  String quote,
) {
  final matches = state.exchangeRates
      .where(
        (rate) =>
            rate.base.toUpperCase() == base.toUpperCase() &&
            rate.quote.toUpperCase() == quote.toUpperCase() &&
            rate.rate > 0,
      )
      .toList();
  matches.sort((left, right) {
    final leftDate = left.updatedAt ?? left.asOfDate;
    final rightDate = right.updatedAt ?? right.asOfDate;
    return rightDate.compareTo(leftDate);
  });
  return matches.isEmpty ? null : matches.first;
}

_RateSnapshot? _inferredRateBetween(
  LedgerState state,
  String base,
  String quote,
) {
  final transactions = sortedTransactions(state, includeScheduled: false);
  for (final transaction in transactions) {
    if (transaction.amount.currency.toUpperCase() == base.toUpperCase() &&
        transaction.baseAmount.currency.toUpperCase() == quote.toUpperCase() &&
        transaction.amount.amountMinor != 0) {
      final amount =
          transaction.amount.amountMinor.abs() /
          math.pow(10, minorUnits(transaction.amount.currency));
      final baseAmount =
          transaction.baseAmount.amountMinor.abs() /
          math.pow(10, minorUnits(transaction.baseAmount.currency));
      if (amount > 0 && baseAmount > 0) {
        return _RateSnapshot(
          rate: baseAmount / amount,
          asOfDate: transaction.occurredAt,
          sourceLabel: 'Latest ledger movement',
        );
      }
    }
  }
  return null;
}

String? _preferredQuoteCurrency(
  LedgerState state,
  String base,
  List<Money> exposure,
) {
  if (exposure.isNotEmpty) return exposure.first.currency;
  for (final rate in state.exchangeRates) {
    if (rate.base.toUpperCase() != base) return rate.base.toUpperCase();
    if (rate.quote.toUpperCase() != base) return rate.quote.toUpperCase();
  }
  for (final transaction in state.transactions) {
    final currency = transaction.amount.currency.toUpperCase();
    if (currency != base) return currency;
  }
  return null;
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

class _RateSnapshot {
  const _RateSnapshot({
    required this.rate,
    required this.asOfDate,
    required this.sourceLabel,
  });

  final double rate;
  final DateTime asOfDate;
  final String sourceLabel;
}
