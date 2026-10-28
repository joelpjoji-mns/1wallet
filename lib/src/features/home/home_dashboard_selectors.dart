import 'dart:math' as math;

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import '../calendar/calendar_forecast.dart';

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
  String? accountId,
  String? targetCurrency,
}) {
  final includedAccounts = accountId != null
      ? (accountId == 'cash_group'
            ? {
                for (final account in state.accounts)
                  if (account.type == 'cash' &&
                      !account.isArchived &&
                      !account.isDeleted)
                    account.id,
              }
            : {
                for (final account in state.accounts)
                  if (account.id == accountId && !account.isDeleted) account.id,
              })
      : {
          for (final account in state.accounts)
            if (!account.isArchived &&
                !account.isDeleted &&
                account.includeInReports)
              account.id,
        };

  if (includedAccounts.isEmpty) return const [];

  final displayCurrency =
      targetCurrency ??
      (accountId != null && accountId != 'cash_group'
          ? (accountById(state, accountId)?.currency ??
              state.preferences.displayCurrency)
          : state.preferences.displayCurrency);

  final now = DateTime.now();
  final rangeEndRaw = end ?? now;
  DateTime earliest = now;
  for (final tx in state.transactions) {
    if (tx.status == 'scheduled' || tx.status == 'void') continue;
    if (includedAccounts.isNotEmpty) {
      if (!includedAccounts.contains(tx.accountId) &&
          !includedAccounts.contains(tx.counterAccountId)) {
        continue;
      }
    }
    if (tx.occurredAt.isBefore(earliest)) earliest = tx.occurredAt;
  }
  final rangeStartRaw = start ?? earliest;
  if (rangeEndRaw.isBefore(rangeStartRaw)) return const [];

  final rangeStart = DateTime(
    rangeStartRaw.year,
    rangeStartRaw.month,
    rangeStartRaw.day,
  );
  final rangeEnd = DateTime(
    rangeEndRaw.year,
    rangeEndRaw.month,
    rangeEndRaw.day,
  );

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

  final txs =
      state.transactions
          .where((tx) => tx.status != 'scheduled' && tx.status != 'void')
          .where(
            (tx) =>
                includedAccounts.contains(tx.accountId) ||
                (tx.counterAccountId != null &&
                    includedAccounts.contains(tx.counterAccountId)),
          )
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  int txIndex = 0;
  while (txIndex < txs.length && txs[txIndex].occurredAt.isBefore(rangeStart)) {
    running += _includedTotalDelta(
      state,
      txs[txIndex],
      includedAccounts,
      displayCurrency,
    );
    txIndex++;
  }

  final points = <BalanceTrendPoint>[];
  DateTime current = rangeStart;

  while (!current.isAfter(rangeEnd)) {
    final nextDay = DateTime(current.year, current.month, current.day + 1);
    while (txIndex < txs.length && txs[txIndex].occurredAt.isBefore(nextDay)) {
      running += _includedTotalDelta(
        state,
        txs[txIndex],
        includedAccounts,
        displayCurrency,
      );
      txIndex++;
    }
    points.add(
      BalanceTrendPoint(
        date: current,
        balance: Money(amountMinor: running, currency: displayCurrency),
      ),
    );
    current = nextDay;
  }

  return points;
}

/// Projects balance forward from [start] (usually now) to [end] using
/// scheduled / paused calendar transactions as future events.
List<BalanceTrendPoint> balanceFutureTrendForRange(
  LedgerState state, {
  required DateTime start,
  required DateTime end,
  String? accountId,
  String? targetCurrency,
}) {
  if (end.isBefore(start)) return const [];

  final rangeStart = DateTime(start.year, start.month, start.day);
  final rangeEnd = DateTime(end.year, end.month, end.day);

  final includedAccounts = accountId != null
      ? (accountId == 'cash_group'
            ? {
                for (final account in state.accounts)
                  if (account.type == 'cash' &&
                      !account.isArchived &&
                      !account.isDeleted)
                    account.id,
              }
            : {
                for (final account in state.accounts)
                  if (account.id == accountId && !account.isDeleted) account.id,
              })
      : {
          for (final account in state.accounts)
            if (!account.isArchived &&
                !account.isDeleted &&
                account.includeInReports)
              account.id,
        };

  if (includedAccounts.isEmpty) return const [];

  final displayCurrency =
      targetCurrency ??
      (accountId != null && accountId != 'cash_group'
          ? (accountById(state, accountId)?.currency ??
              state.preferences.displayCurrency)
          : state.preferences.displayCurrency);

  // Seed running balance from all posted transactions (same as balanceTrendForRange)
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

  final postedTxs =
      state.transactions
          .where((tx) => tx.status != 'scheduled' && tx.status != 'void')
          .where(
            (tx) =>
                includedAccounts.contains(tx.accountId) ||
                (tx.counterAccountId != null &&
                    includedAccounts.contains(tx.counterAccountId)),
          )
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  for (final tx in postedTxs) {
    running += _includedTotalDelta(
      state,
      tx,
      includedAccounts,
      displayCurrency,
    );
  }

  // Gather scheduled/paused transactions due in [start..end]
  final futureTxs = state.transactions
      .where(
        (tx) =>
            (tx.status == 'scheduled' || tx.status == 'paused') &&
            tx.source != 'recurring' &&
            !tx.occurredAt.isBefore(rangeStart) &&
            !tx.occurredAt.isAfter(rangeEnd),
      )
      .where(
        (tx) =>
            includedAccounts.contains(tx.accountId) ||
            (tx.counterAccountId != null &&
                includedAccounts.contains(tx.counterAccountId)),
      )
      .toList();

  futureTxs.addAll(
    forecastRecurringTransactions(state, rangeStart, rangeEnd).where(
      (tx) =>
          includedAccounts.contains(tx.accountId) ||
          (tx.counterAccountId != null &&
              includedAccounts.contains(tx.counterAccountId)),
    ),
  );
  futureTxs.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  final points = <BalanceTrendPoint>[];
  DateTime current = rangeStart;
  int txIndex = 0;

  while (!current.isAfter(rangeEnd)) {
    final nextDay = DateTime(current.year, current.month, current.day + 1);
    while (txIndex < futureTxs.length &&
        futureTxs[txIndex].occurredAt.isBefore(nextDay)) {
      running += _includedTotalDelta(
        state,
        futureTxs[txIndex],
        includedAccounts,
        displayCurrency,
      );
      txIndex++;
    }
    points.add(
      BalanceTrendPoint(
        date: current,
        balance: Money(amountMinor: running, currency: displayCurrency),
      ),
    );
    current = nextDay;
  }

  return points;
}

List<Money> balanceBreakdownByCurrency(LedgerState state, {String? accountId}) {
  final accounts = accountId != null
      ? (accountId == 'cash_group'
            ? state.accounts.where((a) => a.type == 'cash' && !a.isArchived)
            : state.accounts.where((a) => a.id == accountId && !a.isArchived))
      : state.accounts.where(
          (account) => !account.isArchived && account.includeInTotals,
        );
  final accountMap = <String, Account>{};
  final totals = <String, int>{};
  for (final account in accounts) {
    accountMap[account.id] = account;
    _addMoney(
      totals,
      account.openingBalance.copyWith(currency: account.currency),
    );
  }

  if (accountMap.isNotEmpty) {
    for (final transaction in state.transactions) {
      if (transaction.status == 'scheduled' ||
          transaction.status == 'paused' ||
          transaction.status == 'void') {
        continue;
      }

      final sourceAccount = accountMap[transaction.accountId];
      if (sourceAccount != null) {
        final delta = sourceDelta(transaction);
        if (delta != 0) {
          final money = _sourceCurrencyMoney(transaction, sourceAccount);
          _addSignedMoney(totals, money, delta);
        }
      }

      final counterAccountId = transaction.counterAccountId;
      if (counterAccountId != null) {
        final counterAccount = accountMap[counterAccountId];
        if (counterAccount != null) {
          final delta = counterDelta(transaction);
          if (delta != 0) {
            final money = _counterCurrencyMoney(transaction, counterAccount);
            _addSignedMoney(totals, money, delta);
          }
        }
      }
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
  Set<String> accountIds, [
  String? targetCurrency,
]) {
  var delta = 0;
  if (accountIds.contains(transaction.accountId)) {
    delta += convertMoneyForDisplay(
      state,
      Money(
        amountMinor: sourceDelta(transaction),
        currency: transaction.amount.currency,
      ),
      targetCurrency,
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
      targetCurrency,
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
  final targetBase = base.toUpperCase();
  final targetQuote = quote.toUpperCase();
  ExchangeRateRecord? latest;
  DateTime? latestDate;
  for (final rate in state.exchangeRates) {
    if (rate.rate <= 0 ||
        rate.base.toUpperCase() != targetBase ||
        rate.quote.toUpperCase() != targetQuote) {
      continue;
    }
    final rateDate = rate.updatedAt ?? rate.asOfDate;
    if (latest == null || rateDate.isAfter(latestDate!)) {
      latest = rate;
      latestDate = rateDate;
    }
  }
  return latest;
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
