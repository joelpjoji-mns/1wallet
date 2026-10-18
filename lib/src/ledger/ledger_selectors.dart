import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/ledger_models.dart';
import '../design/tokens.dart';

const incomeTypes = {
  'income',
  'refund',
  'interest_in',
  'cashback',
  'borrowed',
  'investment_sell',
};

const expenseTypes = {
  'expense',
  'fee',
  'interest_out',
  'lent',
  'investment_buy',
  'card_payment',
  'loan_repayment',
};

const transferTypes = {'transfer'};

bool isHiddenInterest(LedgerState state, TransactionRecord transaction) {
  if (transaction.type != 'interest_in' && transaction.type != 'interest_out') {
    return false;
  }

  final account = accountById(state, transaction.accountId);
  if (account != null && account.type == 'loan') {
    if (account.loanDetails?.hideInterestInLedger ?? true) return true;
  }

  final counterAccount = accountById(state, transaction.counterAccountId);
  if (counterAccount != null && counterAccount.type == 'loan') {
    if (counterAccount.loanDetails?.hideInterestInLedger ?? true) return true;
  }

  return false;
}

final _sortedIncludeScheduledExpando = Expando<List<TransactionRecord>>();
final _sortedExcludeScheduledExpando = Expando<List<TransactionRecord>>();

List<TransactionRecord> sortedTransactions(
  LedgerState state, {
  bool includeScheduled = true,
  bool hideInterest = false,
}) {
  final canCache = !hideInterest;
  if (canCache) {
    final cached = includeScheduled
        ? _sortedIncludeScheduledExpando[state]
        : _sortedExcludeScheduledExpando[state];
    if (cached != null) return cached;
  }

  final items = state.transactions
      .where(
        (transaction) =>
            includeScheduled ||
            (transaction.status != 'scheduled' &&
                transaction.status != 'paused'),
      )
      .where(
        (transaction) => !hideInterest || !isHiddenInterest(state, transaction),
      )
      .toList();
  items.sort((left, right) => right.occurredAt.compareTo(left.occurredAt));

  if (canCache) {
    if (includeScheduled) {
      _sortedIncludeScheduledExpando[state] = items;
    } else {
      _sortedExcludeScheduledExpando[state] = items;
    }
  }

  return items;
}

final _accountBalanceMapExpando = Expando<Map<String, Money>>();

Map<String, Money> accountBalanceMap(LedgerState state) {
  final cached = _accountBalanceMapExpando[state];
  if (cached != null) return cached;

  final balances = <String, Money>{
    for (final account in state.accounts)
      account.id: account.openingBalance.copyWith(currency: account.currency),
  };

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' ||
        transaction.status == 'paused' ||
        transaction.status == 'void') {
      continue;
    }

    final sourceBalance = balances[transaction.accountId];
    if (sourceBalance != null) {
      balances[transaction.accountId] = sourceBalance.copyWith(
        amountMinor: sourceBalance.amountMinor + sourceDelta(transaction),
      );
    }

    final counterAccountId = transaction.counterAccountId;
    if (counterAccountId != null) {
      final counterBalance = balances[counterAccountId];
      if (counterBalance != null) {
        balances[counterAccountId] = counterBalance.copyWith(
          amountMinor: counterBalance.amountMinor + counterDelta(transaction),
        );
      }
    }
  }

  for (final account in state.accounts) {
    if (account.type == 'cash') {
      final cashBalances = cashCurrencyBalancesForAccount(state, account);
      var totalConvertedMinor = 0;
      for (final b in cashBalances) {
        final converted = convertMoneyForDisplay(state, b, account.currency);
        totalConvertedMinor += converted.amountMinor;
      }
      balances[account.id] = Money(
        amountMinor: totalConvertedMinor,
        currency: account.currency,
      );
    }
  }

  _accountBalanceMapExpando[state] = balances;
  return balances;
}

Money accountBalanceFromMap(Map<String, Money> balances, Account account) {
  return balances[account.id] ??
      account.openingBalance.copyWith(currency: account.currency);
}

Money accountBalance(LedgerState state, Account account) {
  // Reuse the memoized per-account balance map so repeated per-account calls
  // in list builds stay O(1) instead of O(transactions) each.
  final cached = accountBalanceMap(state)[account.id];
  if (cached != null) return cached;
  if (account.type == 'cash') {
    final cashBalances = cashCurrencyBalancesForAccount(state, account);
    var totalConvertedMinor = 0;
    for (final b in cashBalances) {
      final converted = convertMoneyForDisplay(state, b, account.currency);
      totalConvertedMinor += converted.amountMinor;
    }
    return Money(amountMinor: totalConvertedMinor, currency: account.currency);
  }
  var amountMinor = account.openingBalance.amountMinor;
  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' ||
        transaction.status == 'paused' ||
        transaction.status == 'void') {
      continue;
    }
    if (transaction.accountId == account.id) {
      amountMinor += sourceDelta(transaction);
    }
    if (transaction.counterAccountId == account.id) {
      amountMinor += counterDelta(transaction);
    }
  }
  return Money(amountMinor: amountMinor, currency: account.currency);
}

Money cashSourceTransactionMoney(TransactionRecord transaction) {
  final originalCurrency = transaction.originalAmount?.currency.toUpperCase();
  final amountCurrency = transaction.amount.currency.toUpperCase();

  if (transferTypes.contains(transaction.type)) {
    // For transfers out of a cash wallet, if there's a counter amount in a different currency
    // and an original amount is specified matching the counter amount, we should use that to reflect
    // the actual physical currency that left the wallet.
    // If no originalAmount is given, we might need to assume the counterAmount currency is what left the wallet
    // IF the wallet is considered multi-currency. But safely, if originalCurrency differs, we use it.
    if (originalCurrency != null && originalCurrency != amountCurrency) {
      return transaction.originalAmount!;
    }
    return transaction.amount;
  }

  return originalCurrency != null && originalCurrency != amountCurrency
      ? transaction.originalAmount!
      : transaction.amount;
}

Money cashDestinationTransferMoney(
  TransactionRecord transaction,
  Account cashAccount,
) {
  return transaction.counterAmount ?? transaction.amount;
}

List<Money> cashCurrencyBalancesForAccount(LedgerState state, Account account) {
  if (account.type != 'cash') return [];

  final balancesByCurrency = <String, Money>{};
  void addMoney(Money? money, int direction) {
    if (money == null || money.amountMinor == 0) return;
    final currency = money.currency.toUpperCase();
    final current =
        balancesByCurrency[currency] ??
        Money(amountMinor: 0, currency: currency);
    balancesByCurrency[currency] = current.copyWith(
      amountMinor: current.amountMinor + (money.amountMinor * direction),
    );
  }

  for (final opening in account.effectiveOpeningBalances) {
    final currency = opening.currency.toUpperCase();
    balancesByCurrency.putIfAbsent(
      currency,
      () => Money(amountMinor: 0, currency: currency),
    );
    addMoney(opening, 1);
  }

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' ||
        transaction.status == 'paused' ||
        transaction.status == 'void') {
      continue;
    }

    if (transaction.accountId == account.id) {
      int direction = 0;
      if (incomeTypes.contains(transaction.type) ||
          transaction.type == 'adjustment') {
        direction = 1;
      } else if (expenseTypes.contains(transaction.type) ||
          transferTypes.contains(transaction.type)) {
        direction = -1;
      }
      if (direction != 0) {
        addMoney(cashSourceTransactionMoney(transaction), direction);
      }
    }

    if (transferTypes.contains(transaction.type) &&
        transaction.counterAccountId == account.id) {
      addMoney(cashDestinationTransferMoney(transaction, account), 1);
    }
  }

  final balances = balancesByCurrency.values
      .where(
        (m) =>
            m.amountMinor != 0 ||
            account.effectiveOpeningBalances.any(
              (o) => o.currency.toUpperCase() == m.currency.toUpperCase(),
            ),
      )
      .toList();
  balances.sort((left, right) {
    final accountCurrency = account.currency.toUpperCase();
    final leftIsAccount = left.currency.toUpperCase() == accountCurrency;
    final rightIsAccount = right.currency.toUpperCase() == accountCurrency;
    if (leftIsAccount && !rightIsAccount) return -1;
    if (!leftIsAccount && rightIsAccount) return 1;
    return right.amountMinor.compareTo(left.amountMinor);
  });

  return balances;
}

Money convertMoneyForDisplay(
  LedgerState state,
  Money money, [
  String? targetCurrency,
]) {
  final target = (targetCurrency ?? state.preferences.displayCurrency)
      .toUpperCase();
  final source = money.currency.toUpperCase();
  if (source == target) return money.copyWith(currency: target);
  final rate = rateBetween(state, source, target);
  if (rate == null || rate <= 0 || !rate.isFinite) {
    return money.copyWith(currency: source);
  }
  final sourceValue = money.amountMinor / math.pow(10, minorUnits(source));
  final convertedMinor = (sourceValue * rate * math.pow(10, minorUnits(target)))
      .round();
  return Money(amountMinor: convertedMinor, currency: target);
}

final _rateBetweenCacheExpando = Expando<Map<String, double?>>();

double? rateBetween(LedgerState state, String from, String to) {
  final source = from.toUpperCase();
  final target = to.toUpperCase();
  if (source == target) return 1;

  final cache = _rateBetweenCacheExpando[state] ??= <String, double?>{};
  final cacheKey = '$source|$target';
  if (cache.containsKey(cacheKey)) return cache[cacheKey];

  final direct = latestExchangeRate(state, source, target);
  if (direct != null) {
    cache[cacheKey] = direct.rate;
    return direct.rate;
  }
  final inverse = latestExchangeRate(state, target, source);
  if (inverse != null && inverse.rate > 0) {
    final result = 1 / inverse.rate;
    cache[cacheKey] = result;
    return result;
  }

  final base = state.preferences.baseCurrency.toUpperCase();
  if (source != base && target != base) {
    final r1 = rateBetween(state, source, base);
    final r2 = rateBetween(state, base, target);
    if (r1 != null && r2 != null && r1 > 0 && r2 > 0) {
      final result = r1 * r2;
      cache[cacheKey] = result;
      return result;
    }
  }

  final inferred = _inferredRateBetween(state, source, target);
  cache[cacheKey] = inferred;
  return inferred;
}

ExchangeRateRecord? latestExchangeRate(
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

int sourceDelta(TransactionRecord transaction) {
  if (incomeTypes.contains(transaction.type)) {
    return transaction.amount.amountMinor;
  }
  if (expenseTypes.contains(transaction.type) ||
      transferTypes.contains(transaction.type)) {
    return -transaction.amount.amountMinor.abs();
  }
  if (transaction.type == 'adjustment') return transaction.amount.amountMinor;
  return 0;
}

int counterDelta(TransactionRecord transaction) {
  if (transferTypes.contains(transaction.type)) {
    final counterAmt = transaction.counterAmount ?? transaction.amount;
    if (counterAmt.amountMinor == 0 && transaction.amount.amountMinor != 0) {
      if (transaction.counterAmount?.currency.toUpperCase() ==
          transaction.amount.currency.toUpperCase()) {
        return transaction.amount.amountMinor.abs();
      }
    }
    return counterAmt.amountMinor.abs();
  }
  if (transaction.type == 'card_payment' ||
      transaction.type == 'loan_repayment') {
    return transaction.amount.amountMinor.abs();
  }
  return 0;
}

Money totalBalance(
  LedgerState state, {
  String? accountId,
  String? targetCurrency,
}) {
  final currency = targetCurrency ?? state.preferences.displayCurrency;
  final balances = accountBalanceMap(state);
  final accounts = accountId != null
      ? (accountId == 'cash_group'
            ? state.accounts.where((a) => a.type == 'cash' && !a.isArchived && !a.isDeleted)
            : state.accounts.where((a) => a.id == accountId && !a.isDeleted))
      : state.accounts.where(
          (account) => !account.isArchived && !account.isDeleted && account.includeInTotals,
        );
  final total = accounts.fold<int>(0, (sum, account) {
    final converted = convertMoneyForDisplay(
      state,
      accountBalanceFromMap(balances, account),
      currency,
    );
    return sum + converted.amountMinor;
  });
  return Money(amountMinor: total, currency: currency);
}

({Money total, Money assets, Money liabilities}) netWorth(LedgerState state) {
  var assets = 0;
  var liabilities = 0;
  final balances = accountBalanceMap(state);
  for (final account in state.accounts) {
    if (account.isArchived || account.isDeleted || !account.includeInNetWorth) continue;
    final balance = convertMoneyForDisplay(
      state,
      accountBalanceFromMap(balances, account),
      state.preferences.displayCurrency,
    ).amountMinor;
    if (balance < 0) {
      liabilities += balance;
    } else {
      assets += balance;
    }
  }
  final currency = state.preferences.displayCurrency;
  return (
    total: Money(amountMinor: assets + liabilities, currency: currency),
    assets: Money(amountMinor: assets, currency: currency),
    liabilities: Money(amountMinor: liabilities, currency: currency),
  );
}

({Money income, Money expense}) flowForPeriod(
  LedgerState state,
  String period, {
  String? accountId,
  String? targetCurrency,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime start;
  DateTime end;

  switch (period) {
    case 'Today':
      start = today;
      end = today.add(const Duration(days: 1));
      break;
    case 'This week':
      final diff = now.weekday - 1; // 0 for Monday
      start = today.subtract(Duration(days: diff));
      end = start.add(const Duration(days: 7));
      break;
    case 'This year':
      start = DateTime(now.year);
      end = DateTime(now.year + 1);
      break;
    case 'This month':
    default:
      start = DateTime(now.year, now.month);
      end = DateTime(now.year, now.month + 1);
  }

  final displayCurrency = targetCurrency ?? state.preferences.displayCurrency;
  var income = 0;
  var expense = 0;
  final cashAccountIds = accountId == 'cash_group'
      ? state.accounts.where((a) => a.type == 'cash').map((a) => a.id).toSet()
      : const <String>{};

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' ||
        transaction.status == 'paused' ||
        transaction.status == 'void') {
      continue;
    }
    if (transaction.isExcludedFromReports) continue;
    if (isHiddenInterest(state, transaction)) continue;
    if (accountId != null) {
      if (accountId == 'cash_group') {
        if (!cashAccountIds.contains(transaction.accountId) &&
            !cashAccountIds.contains(transaction.counterAccountId)) {
          continue;
        }
      } else if (transaction.accountId != accountId &&
          transaction.counterAccountId != accountId) {
        continue;
      }
    }
    if (transaction.occurredAt.isBefore(start) ||
        !transaction.occurredAt.isBefore(end)) {
      continue;
    }

    if (accountId != null) {
      if (accountId == 'cash_group') {
        final hasSource = cashAccountIds.contains(transaction.accountId);
        final hasCounter = cashAccountIds.contains(
          transaction.counterAccountId,
        );
        if (hasSource && hasCounter) {
          continue;
        }
        if (hasSource) {
          final delta = sourceDelta(transaction);
          final converted = convertMoneyForDisplay(
            state,
            Money(
              amountMinor: delta.abs(),
              currency: transaction.amount.currency,
            ),
            displayCurrency,
          );
          if (delta > 0) income += converted.amountMinor;
          if (delta < 0) expense += converted.amountMinor;
        }
        if (hasCounter) {
          final delta = counterDelta(transaction);
          final converted = convertMoneyForDisplay(
            state,
            Money(
              amountMinor: delta.abs(),
              currency:
                  (transaction.counterAmount ?? transaction.amount).currency,
            ),
            displayCurrency,
          );
          if (delta > 0) income += converted.amountMinor;
          if (delta < 0) expense += converted.amountMinor;
        }
      } else {
        if (transaction.accountId == accountId) {
          final delta = sourceDelta(transaction);
          final converted = convertMoneyForDisplay(
            state,
            Money(
              amountMinor: delta.abs(),
              currency: transaction.amount.currency,
            ),
            displayCurrency,
          );
          if (delta > 0) income += converted.amountMinor;
          if (delta < 0) expense += converted.amountMinor;
        }
        if (transaction.counterAccountId == accountId) {
          final delta = counterDelta(transaction);
          final converted = convertMoneyForDisplay(
            state,
            Money(
              amountMinor: delta.abs(),
              currency:
                  (transaction.counterAmount ?? transaction.amount).currency,
            ),
            displayCurrency,
          );
          if (delta > 0) income += converted.amountMinor;
          if (delta < 0) expense += converted.amountMinor;
        }
      }
    } else {
      if (incomeTypes.contains(transaction.type)) {
        final converted = convertMoneyForDisplay(
          state,
          transaction.amount,
          displayCurrency,
        );
        income += converted.amountMinor;
      }
      if (expenseTypes.contains(transaction.type)) {
        final converted = convertMoneyForDisplay(
          state,
          transaction.amount,
          displayCurrency,
        );
        expense += converted.amountMinor;
      }
    }
  }
  return (
    income: Money(amountMinor: income, currency: displayCurrency),
    expense: Money(amountMinor: expense, currency: displayCurrency),
  );
}

final _scheduledTransactionsExpando = Expando<List<TransactionRecord>>();

List<TransactionRecord> scheduledTransactions(LedgerState state) {
  final cached = _scheduledTransactionsExpando[state];
  if (cached != null) return cached;

  final items = <TransactionRecord>[];
  for (final transaction in state.transactions) {
    if (transaction.status != 'scheduled' && transaction.status != 'paused') {
      continue;
    }
    if (transaction.type == 'loan_repayment') {
      final counterAccount = accountById(state, transaction.counterAccountId);
      if (counterAccount != null && isPastLoan(state, counterAccount)) {
        continue;
      }
    }
    items.add(transaction);
  }
  items.sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
  _scheduledTransactionsExpando[state] = items;
  return items;
}

bool isPastLoan(LedgerState state, Account loan) {
  if (loan.isArchived) return true;
  final remaining = accountBalance(state, loan).amountMinor;
  if (remaining >= 0) {
    final principalMinor =
        loan.loanDetails?.principal?.amountMinor.abs() ??
        loan.openingBalance.amountMinor.abs();
    if (principalMinor > 0) return true;
  }
  return false;
}

final _categoryByIdMapExpando = Expando<Map<String, Category>>();
final _accountByIdMapExpando = Expando<Map<String, Account>>();

Map<String, Category> _categoryByIdMap(LedgerState state) {
  final cached = _categoryByIdMapExpando[state];
  if (cached != null) return cached;
  final map = <String, Category>{};
  for (final category in state.categories) {
    map.putIfAbsent(category.id, () => category);
  }
  _categoryByIdMapExpando[state] = map;
  return map;
}

Map<String, Account> _accountByIdMap(LedgerState state) {
  final cached = _accountByIdMapExpando[state];
  if (cached != null) return cached;
  final map = <String, Account>{};
  for (final account in state.accounts) {
    map.putIfAbsent(account.id, () => account);
  }
  _accountByIdMapExpando[state] = map;
  return map;
}

Category? categoryById(LedgerState state, String? id) {
  if (id == null) return null;
  return _categoryByIdMap(state)[id];
}

Account? accountById(LedgerState state, String? id) {
  if (id == null) return null;
  return _accountByIdMap(state)[id];
}

final _categoryPathCacheExpando = Expando<Map<String, String>>();

String categoryPath(LedgerState state, Category? category) {
  if (category == null) return '';
  final cache = _categoryPathCacheExpando[state] ??= <String, String>{};
  final cached = cache[category.id];
  if (cached != null) return cached;

  final byId = _categoryByIdMap(state);
  final names = <String>[];
  Category? current = category;
  final seen = <String>{};
  while (current != null && seen.add(current.id)) {
    names.insert(0, current.name);
    current = byId[current.parentId];
  }
  final path = names.join(' > ');
  cache[category.id] = path;
  return path;
}

int compareCategories(Category left, Category right) {
  final orderCompare = left.sortOrder.compareTo(right.sortOrder);
  return orderCompare != 0
      ? orderCompare
      : left.name.toLowerCase().compareTo(right.name.toLowerCase());
}

int compareCategoriesByUsage(LedgerState state, Category left, Category right) {
  final leftUsage = categoryUsageCount(state, left, includeDescendants: true);
  final rightUsage = categoryUsageCount(state, right, includeDescendants: true);
  final usageCompare = rightUsage.compareTo(leftUsage);
  return usageCompare != 0 ? usageCompare : compareCategories(left, right);
}

final _directCategoryUsageExpando = Expando<Map<String, int>>();
final _descendantCategoryUsageExpando = Expando<Map<String, int>>();

Map<String, int> _directCategoryUsageMap(LedgerState state) {
  final cached = _directCategoryUsageExpando[state];
  if (cached != null) return cached;
  final counts = <String, int>{};
  for (final transaction in state.transactions) {
    if (transaction.status == 'void') continue;
    final categoryId = transaction.categoryId;
    if (categoryId != null) {
      counts[categoryId] = (counts[categoryId] ?? 0) + 1;
    }
  }
  _directCategoryUsageExpando[state] = counts;
  return counts;
}

Map<String, int> _descendantCategoryUsageMap(LedgerState state) {
  final cached = _descendantCategoryUsageExpando[state];
  if (cached != null) return cached;
  final direct = _directCategoryUsageMap(state);
  final childrenByParent = <String, List<String>>{};
  for (final cat in state.categories) {
    final parentId = cat.parentId;
    if (parentId != null) {
      (childrenByParent[parentId] ??= <String>[]).add(cat.id);
    }
  }
  final totals = <String, int>{};
  for (final cat in state.categories) {
    final visited = <String>{cat.id};
    final stack = <String>[cat.id];
    var sum = 0;
    while (stack.isNotEmpty) {
      final currentId = stack.removeLast();
      sum += direct[currentId] ?? 0;
      final children = childrenByParent[currentId];
      if (children != null) {
        for (final childId in children) {
          if (visited.add(childId)) {
            stack.add(childId);
          }
        }
      }
    }
    totals[cat.id] = sum;
  }
  _descendantCategoryUsageExpando[state] = totals;
  return totals;
}

int categoryUsageCount(
  LedgerState state,
  Category category, {
  bool includeDescendants = false,
}) {
  if (!includeDescendants) {
    return _directCategoryUsageMap(state)[category.id] ?? 0;
  }
  final totals = _descendantCategoryUsageMap(state);
  return totals[category.id] ??
      (_directCategoryUsageMap(state)[category.id] ?? 0);
}

List<Category> sortedCategoriesByUsage(
  LedgerState state,
  Iterable<Category> categories,
) {
  return categories.toList()
    ..sort((left, right) => compareCategoriesByUsage(state, left, right));
}

List<Category> activeCategories(LedgerState state) {
  return sortedCategoriesByUsage(
    state,
    state.categories.where((category) => !category.isArchived),
  );
}

List<Category> categoryLevel(
  LedgerState state, {
  String? parentId,
  bool includeArchived = false,
}) {
  final source = includeArchived
      ? state.categories
      : state.categories.where((category) => !category.isArchived).toList();
  final byId = {for (final category in source) category.id: category};
  return sortedCategoriesByUsage(
    state,
    source.where((category) {
      final directParentId =
          category.parentId != null && byId.containsKey(category.parentId)
          ? category.parentId
          : null;
      return directParentId == parentId;
    }),
  );
}

List<Category> rootCategories(
  LedgerState state, {
  bool includeArchived = false,
}) {
  return categoryLevel(state, includeArchived: includeArchived);
}

List<Category> childCategories(
  LedgerState state,
  String parentId, {
  bool includeArchived = false,
}) {
  return categoryLevel(
    state,
    parentId: parentId,
    includeArchived: includeArchived,
  );
}

Category rootCategoryFor(LedgerState state, Category category) {
  final byId = {for (final item in state.categories) item.id: item};
  var current = category;
  final seen = <String>{category.id};
  while (current.parentId != null) {
    final parent = byId[current.parentId];
    if (parent == null || !seen.add(parent.id)) break;
    current = parent;
  }
  return current;
}

Category? firstActiveCategory(LedgerState state, {String? preferred}) {
  final normalizedPreferred = preferred?.trim().toLowerCase();
  final active = activeCategories(state);
  if (normalizedPreferred != null && normalizedPreferred.isNotEmpty) {
    for (final category in active) {
      if (category.name.toLowerCase().contains(normalizedPreferred)) {
        return category;
      }
    }
  }
  return active.isEmpty ? null : active.first;
}

List<String> availableCurrencies(LedgerState state) {
  final values = <String>{
    state.preferences.baseCurrency.toUpperCase(),
    state.preferences.displayCurrency.toUpperCase(),
    for (final currency in state.preferences.enabledCurrencies)
      currency.toUpperCase(),
    for (final account in state.accounts) account.currency.toUpperCase(),
    for (final transaction in state.transactions) ...[
      transaction.amount.currency.toUpperCase(),
      transaction.baseAmount.currency.toUpperCase(),
      if (transaction.counterAmount != null)
        transaction.counterAmount!.currency.toUpperCase(),
      if (transaction.originalAmount != null)
        transaction.originalAmount!.currency.toUpperCase(),
    ],
    for (final rate in state.exchangeRates) ...[
      rate.base.toUpperCase(),
      rate.quote.toUpperCase(),
    ],
  };
  final items = values.where((value) => value.trim().isNotEmpty).toList()
    ..sort();
  return items;
}

final _currencyFormatCache = <String, NumberFormat>{};
final _dateFormatCache = <String, DateFormat>{};

NumberFormat _cachedSimpleCurrencyFormat(String normalizedLocale, String currency) {
  final key = '$normalizedLocale|$currency';
  return _currencyFormatCache.putIfAbsent(
    key,
    () => NumberFormat.simpleCurrency(locale: normalizedLocale, name: currency),
  );
}

DateFormat _cachedDateFormat(String pattern, [String? normalizedLocale]) {
  final key = normalizedLocale == null ? pattern : '$pattern|$normalizedLocale';
  return _dateFormatCache.putIfAbsent(
    key,
    () => normalizedLocale == null
        ? DateFormat(pattern)
        : DateFormat(pattern, normalizedLocale),
  );
}

String formatMoney(Money money, String locale) {
  final amount = money.amountMinor / math.pow(10, minorUnits(money.currency));
  final normalizedLocale = locale.replaceAll('_', '-');
  try {
    return _cachedSimpleCurrencyFormat(
      normalizedLocale,
      money.currency,
    ).format(amount);
  } catch (_) {
    return '${money.currency} ${amount.toStringAsFixed(minorUnits(money.currency))}';
  }
}

String formatCompactMoney(Money money, String locale) {
  final amount =
      money.amountMinor.abs() / math.pow(10, minorUnits(money.currency));
  final sign = money.amountMinor < 0 ? '-' : '';
  final normalizedLocale = locale.replaceAll('_', '-');
  String symbol;
  try {
    symbol = _cachedSimpleCurrencyFormat(
      normalizedLocale,
      money.currency,
    ).currencySymbol;
  } catch (_) {
    symbol = money.currency;
  }
  // Indian (lakh/crore) grouping only for INR; Western (M/B) for everything else.
  if (money.currency.toUpperCase() == 'INR') {
    if (amount >= 10000000) {
      return '$sign$symbol${(amount / 10000000).toStringAsFixed(1)}Cr';
    }
    if (amount >= 100000) {
      return '$sign$symbol${(amount / 100000).toStringAsFixed(1)}L';
    }
  } else {
    if (amount >= 1000000000) {
      return '$sign$symbol${(amount / 1000000000).toStringAsFixed(1)}B';
    }
    if (amount >= 1000000) {
      return '$sign$symbol${(amount / 1000000).toStringAsFixed(1)}M';
    }
  }
  if (amount >= 1000) {
    return '$sign$symbol${(amount / 1000).toStringAsFixed(1)}k';
  }
  return '$sign$symbol${amount.round()}';
}

String formatLedgerDate(DateTime date, String locale) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;

  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';

  final normalizedLocale = locale.replaceAll('_', '-');
  final formatStr = date.year == now.year ? 'MMMM d' : 'MMMM d, yyyy';
  try {
    return _cachedDateFormat(formatStr, normalizedLocale).format(date);
  } catch (_) {
    return _cachedDateFormat(formatStr).format(date);
  }
}

String formatDueDate(DateTime date, String locale) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;

  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  if (diff == -1) return 'Due yesterday';
  if (diff < -1 && diff > -30) return 'Due ${-diff} days ago';
  if (diff > 1 && diff < 30) return 'Due in $diff days';

  return formatLedgerDate(date, locale);
}

int minorUnits(String currency) => switch (currency.toUpperCase()) {
  'JPY' ||
  'KRW' ||
  'VND' ||
  'CLP' ||
  'ISK' ||
  'PYG' ||
  'UGX' ||
  'RWF' ||
  'XAF' ||
  'XOF' ||
  'XPF' ||
  'DJF' ||
  'GNF' ||
  'KMF' ||
  'BIF' ||
  'VUV' => 0,
  'BHD' || 'KWD' || 'OMR' || 'TND' || 'IQD' || 'JOD' || 'LYD' => 3,
  _ => 2,
};

double? _inferredRateBetween(LedgerState state, String from, String to) {
  // Falls back to scanning historical transactions for an implied rate when
  // no explicit exchange rate is on file. That scan is O(ledger size), so
  // memoize per (state, from, to): without this, rendering N transactions in
  // a currency lacking an explicit rate re-scans the whole transaction list
  // for every single one of them (O(n^2) on large ledgers). `state` is
  // immutable, so the result is safe to cache for its lifetime.
  final cache = _inferredRateCacheExpando[state] ??= <String, double?>{};
  final cacheKey = '$from|$to';
  if (cache.containsKey(cacheKey)) return cache[cacheKey];

  final transactions = sortedTransactions(state, includeScheduled: false);
  double? found;
  for (final transaction in transactions) {
    final rate =
        _rateFromPair(transaction.amount, transaction.baseAmount, from, to) ??
        (transaction.originalAmount == null
            ? null
            : _rateFromPair(
                transaction.originalAmount!,
                transaction.amount,
                from,
                to,
              )) ??
        (transaction.originalAmount == null
            ? null
            : _rateFromPair(
                transaction.originalAmount!,
                transaction.baseAmount,
                from,
                to,
              )) ??
        (transaction.counterAmount == null
            ? null
            : _rateFromPair(
                transaction.amount,
                transaction.counterAmount!,
                from,
                to,
              ));
    if (rate != null && rate > 0 && rate.isFinite) {
      found = rate;
      break;
    }
  }
  cache[cacheKey] = found;
  return found;
}

final _inferredRateCacheExpando = Expando<Map<String, double?>>();

double? _rateFromPair(Money left, Money right, String from, String to) {
  final leftCurrency = left.currency.toUpperCase();
  final rightCurrency = right.currency.toUpperCase();
  if (left.amountMinor == 0 || right.amountMinor == 0) return null;
  final leftValue =
      left.amountMinor.abs() / math.pow(10, minorUnits(leftCurrency));
  final rightValue =
      right.amountMinor.abs() / math.pow(10, minorUnits(rightCurrency));
  if (leftValue <= 0 || rightValue <= 0) return null;
  if (leftCurrency == from && rightCurrency == to) {
    return rightValue / leftValue;
  }
  if (leftCurrency == to && rightCurrency == from) {
    return leftValue / rightValue;
  }
  return null;
}

String transactionTypeLabel(String type) {
  return type
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String accountTypeLabel(String type) => transactionTypeLabel(type);

bool isLiabilityAccount(Account account) {
  return account.type == 'credit_card' ||
      account.type == 'card' ||
      account.type == 'loan' ||
      account.type == 'overdraft';
}

Color amountColor(BuildContext context, int amountMinor) {
  final theme = Theme.of(context);
  if (amountMinor > 0) {
    return theme.brightness == Brightness.dark
        ? AppColors.positiveDark
        : AppColors.positiveLight;
  }
  if (amountMinor < 0) return theme.colorScheme.error;
  return theme.colorScheme.onSurfaceVariant;
}

/// Theme-aware "positive"/success green, matching [amountColor] for positive
/// amounts. Prefer this over hardcoded greens so the color is consistent
/// across the app and adapts to light/dark.
Color positiveTone(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.positiveDark
      : AppColors.positiveLight;
}

IconData accountIcon(Account account) {
  return switch (account.type) {
    'cash' => Icons.payments_outlined,
    'bank' => Icons.account_balance_outlined,
    'credit_card' || 'card' => Icons.credit_card_outlined,
    'loan' || 'overdraft' => Icons.account_balance_outlined,
    'wallet' => Icons.account_balance_wallet_outlined,
    _ => Icons.wallet_outlined,
  };
}

final _categoryIconExpando = Expando<IconData>();

IconData categoryIcon(Category? category) {
  if (category == null) return Icons.folder_outlined;
  final cached = _categoryIconExpando[category];
  if (cached != null) return cached;
  final resolved = _resolveCategoryIcon(category);
  _categoryIconExpando[category] = resolved;
  return resolved;
}

IconData _resolveCategoryIcon(Category? category) {
  final key = _categoryIconKey(category);
  if (key.contains('income') || key.contains('salary')) {
    return Icons.payments_outlined;
  }
  if (key.contains('freelance') || key.contains('work business')) {
    return Icons.work_outline_rounded;
  }
  if (key.contains('business')) return Icons.storefront_outlined;
  if (key.contains('interest') || key.contains('dividend')) {
    return Icons.trending_up_rounded;
  }
  if (key.contains('refund') || key.contains('cashback')) {
    return Icons.replay_rounded;
  }
  if (key.contains('home') ||
      key.contains('rent') ||
      key.contains('mortgage') ||
      key.contains('furniture')) {
    return Icons.home_outlined;
  }
  if (key.contains('electricity') || key.contains('gas')) {
    return Icons.bolt_outlined;
  }
  if (key.contains('water')) return Icons.water_drop_outlined;
  if (key.contains('internet') || key.contains('mobile')) {
    return Icons.wifi_outlined;
  }
  if (key.contains('coffee') || key.contains('cafe')) {
    return Icons.local_cafe_outlined;
  }
  if (key.contains('delivery') || key.contains('takeout')) {
    return Icons.delivery_dining_outlined;
  }
  if (key.contains('snack') || key.contains('beverage')) {
    return Icons.fastfood_outlined;
  }
  if (key.contains('food') ||
      key.contains('grocer') ||
      key.contains('dining')) {
    return Icons.restaurant_outlined;
  }
  if (key.contains('fastag') || key.contains('toll')) {
    return Icons.toll_outlined;
  }
  if (key.contains('car wash') || key.contains('detailing')) {
    return Icons.local_car_wash_outlined;
  }
  if (key.contains('registration') || key.contains('road tax')) {
    return Icons.assignment_outlined;
  }
  if (key.contains('train') ||
      key.contains('rail') ||
      key.contains('metro') ||
      key.contains('subway')) {
    return Icons.train_outlined;
  }
  if (key.contains('bus') || key.contains('coach')) {
    return Icons.directions_bus_outlined;
  }
  if (key.contains('transport') ||
      key.contains('fuel') ||
      key.contains('taxi') ||
      key.contains('vehicle')) {
    return Icons.directions_car_outlined;
  }
  if (key.contains('transit')) return Icons.directions_bus_outlined;
  if (key.contains('laundry') || key.contains('dry clean')) {
    return Icons.local_laundry_service_outlined;
  }
  if (key.contains('housekeep') || key.contains('maid')) {
    return Icons.cleaning_services_outlined;
  }
  if (key.contains('hoa') || key.contains('society')) {
    return Icons.apartment_outlined;
  }
  if (key.contains('decor') || key.contains('appliance')) {
    return Icons.chair_outlined;
  }
  if (key.contains('lab test') || key.contains('diagnostic')) {
    return Icons.biotech_outlined;
  }
  if (key.contains('supplement') || key.contains('vitamin')) {
    return Icons.medication_outlined;
  }
  if (key.contains('health') ||
      key.contains('doctor') ||
      key.contains('pharmacy')) {
    return Icons.health_and_safety_outlined;
  }
  if (key.contains('fitness')) return Icons.fitness_center_rounded;
  if (key.contains('insurance')) return Icons.verified_user_outlined;
  if (key.contains('sip') ||
      key.contains('mutual fund') ||
      key.contains('stock') ||
      key.contains('equit') ||
      key.contains('crypto') ||
      key.contains('capital gain')) {
    return Icons.trending_up_rounded;
  }
  if (key.contains('loan') ||
      key.contains('debt') ||
      key.contains('emi') ||
      key.contains('credit card')) {
    return Icons.account_balance_outlined;
  }
  if (key.contains('investment') ||
      key.contains('emergency fund') ||
      key.contains('retirement')) {
    return Icons.savings_outlined;
  }
  if (key.contains('tax') || key.contains('fee')) {
    return Icons.receipt_long_outlined;
  }
  if (key.contains('luggage') || key.contains('bag')) {
    return Icons.luggage_outlined;
  }
  if (key.contains('shopping') ||
      key.contains('clothing') ||
      key.contains('footwear') ||
      key.contains('electronics') ||
      key.contains('personal care')) {
    return Icons.shopping_bag_outlined;
  }
  if (key.contains('haircut') || key.contains('barber')) {
    return Icons.content_cut_outlined;
  }
  if (key.contains('recreation') || key.contains('outdoor')) {
    return Icons.park_outlined;
  }
  if (key.contains('family') || key.contains('children')) {
    return Icons.family_restroom_rounded;
  }
  if (key.contains('pet')) return Icons.pets_outlined;
  if (key.contains('celebration') || key.contains('holiday')) {
    return Icons.festival_outlined;
  }
  if (key.contains('gift') || key.contains('charity')) {
    return Icons.card_giftcard_outlined;
  }
  if (key.contains('streaming')) return Icons.play_circle_outline_rounded;
  if (key.contains('cloud') || key.contains('software')) {
    return Icons.cloud_outlined;
  }
  if (key.contains('lifestyle') ||
      key.contains('movie') ||
      key.contains('event') ||
      key.contains('hobb')) {
    return Icons.celebration_outlined;
  }
  if (key.contains('subscription')) return Icons.subscriptions_outlined;
  if (key.contains('course') ||
      key.contains('book') ||
      key.contains('tutor')) {
    return Icons.school_outlined;
  }
  if (key.contains('shipping') || key.contains('courier')) {
    return Icons.local_shipping_outlined;
  }
  if (key.contains('government') || key.contains('legal')) {
    return Icons.gavel_outlined;
  }
  if (key.contains('travel') ||
      key.contains('flight') ||
      key.contains('hotel') ||
      key.contains('stay')) {
    return Icons.flight_takeoff_outlined;
  }
  if (key.contains('misc') || key.contains('uncategorized')) {
    return Icons.more_horiz_rounded;
  }
  return category?.parentId == null
      ? Icons.folder_outlined
      : Icons.label_outline_rounded;
}

final RegExp _nonAlphaNumericRegex = RegExp(r'[^a-z0-9]+');

String _categoryIconKey(Category? category) {
  if (category == null) return '';
  return '${category.id} ${category.name}'
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(_nonAlphaNumericRegex, ' ')
      .trim();
}

Color accountDisplayColor(Account account) {
  if (account.color != null) return account.color!;
  final source = '${account.id}|${account.name}|${account.type}';
  var hash = 0;
  for (final unit in source.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return AppColors.accountPalette[hash % AppColors.accountPalette.length];
}

List<Account> sortAccounts(Iterable<Account> accounts) {
  return accounts.toList()
    ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
}

Color categoryColor(Category? category, BuildContext context) {
  if (category?.color != null) return category!.color!;
  final colorScheme = Theme.of(context).colorScheme;
  if (category == null) return colorScheme.secondary;
  if (category.kind == 'income') return colorScheme.tertiary;
  if (category.kind == 'transfer') return colorScheme.primary;
  final source = '${category.id}|${category.name}|${category.parentId ?? ''}';
  var hash = 0;
  for (final unit in source.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return AppColors.accountPalette[hash % AppColors.accountPalette.length];
}

IconData transactionIcon(TransactionRecord transaction) {
  if (incomeTypes.contains(transaction.type)) {
    return Icons.arrow_downward_rounded;
  }
  if (transaction.type == 'transfer') return Icons.swap_horiz_rounded;
  if (transaction.type == 'card_payment') return Icons.credit_card_outlined;
  if (transaction.type == 'loan_repayment') {
    return Icons.account_balance_outlined;
  }
  return Icons.arrow_upward_rounded;
}

// Loan projection logic
AccountLoanDetails effectiveLoanDetails(LedgerState state, Account loan) {
  final fallbackPrincipal = Money(
    amountMinor: loan.openingBalance.amountMinor.abs(),
    currency: loan.currency,
  );
  final existing = loan.loanDetails;
  if (existing != null) {
    return existing.copyWith(
      principal: existing.principal ?? fallbackPrincipal,
      interestRatePercent:
          existing.interestRatePercent ??
          _doubleTagValue(loan.groupName, 'rate'),
      repaymentCount:
          existing.repaymentCount ?? _intTagValue(loan.groupName, 'tenure'),
    );
  }
  final existingEmi = existingLoanEmi(state, loan.id);
  return AccountLoanDetails(
    loanKind: loan.type,
    principal: fallbackPrincipal,
    repaymentAmount: existingEmi?.amount.copyWith(currency: loan.currency),
    interestRatePercent: _doubleTagValue(loan.groupName, 'rate'),
    repaymentCount: _intTagValue(loan.groupName, 'tenure'),
    repaymentStartsOn: existingEmi?.occurredAt,
    repaymentSourceAccountId: existingEmi?.accountId,
  );
}

TransactionRecord? existingLoanEmi(LedgerState state, String? loanId) {
  if (loanId == null) return null;
  TransactionRecord? earliest;
  for (final transaction in scheduledTransactions(state)) {
    if (transaction.type == 'loan_repayment' &&
        transaction.counterAccountId == loanId) {
      if (earliest == null ||
          transaction.occurredAt.isBefore(earliest.occurredAt)) {
        earliest = transaction;
      }
    }
  }
  return earliest;
}

LoanProjection loanProjection(LedgerState state, Account loan) {
  if (isPastLoan(state, loan)) {
    return const LoanProjection(
      monthlyEmi: 0,
      monthsRemaining: 0,
      estimatedInterestMinor: 0,
    );
  }

  final bal = accountBalance(state, loan).amountMinor;
  final remaining = bal < 0 ? -bal : 0;
  final details = effectiveLoanDetails(state, loan);
  final emiTx = existingLoanEmi(state, loan.id);
  final rawEmi =
      details.repaymentAmount?.amountMinor.abs() ??
      emiTx?.amount.amountMinor.abs() ??
      0;
  final frequency = emiTx?.recurrenceFrequency ?? details.recurrenceFrequency;
  final interval = emiTx?.recurrenceInterval ?? details.recurrenceInterval;

  double monthlyMultiplier = 1.0;
  if (frequency == 'yearly') {
    monthlyMultiplier = 1 / 12;
  } else if (frequency == 'weekly') {
    monthlyMultiplier = 52 / 12;
  } else if (frequency == 'daily') {
    monthlyMultiplier = 365 / 12;
  }
  final effectiveInterval = interval > 0 ? interval : 1;
  monthlyMultiplier = monthlyMultiplier / effectiveInterval;

  final emi = (rawEmi * monthlyMultiplier).round();
  final rate = details.interestRatePercent ?? 0;
  if (remaining == 0) {
    return const LoanProjection(
      monthlyEmi: 0,
      monthsRemaining: 0,
      estimatedInterestMinor: 0,
    );
  }
  if (emi <= 0) {
    return const LoanProjection(
      monthlyEmi: 0,
      monthsRemaining: null,
      estimatedInterestMinor: 0,
    );
  }
  final forecast = _simulateLoanForecast(
    principalMinor: remaining,
    monthlyEmiMinor: emi,
    annualRatePercent: rate,
  );
  return LoanProjection(
    monthlyEmi: emi,
    monthsRemaining: forecast.monthsRemaining,
    estimatedInterestMinor: forecast.totalInterestMinor,
  );
}

({int? monthsRemaining, int totalInterestMinor, int remainingMinor})
_simulateLoanForecast({
  required int principalMinor,
  required int monthlyEmiMinor,
  required double annualRatePercent,
  int maxMonths = 1200,
}) {
  var balance = principalMinor;
  var interest = 0;
  var months = 0;
  final monthlyRate = annualRatePercent <= 0 ? 0 : annualRatePercent / 100 / 12;
  while (balance > 0 && months < maxMonths) {
    final interestMinor = (balance * monthlyRate).round();
    final principalPaid = (monthlyEmiMinor - interestMinor)
        .clamp(0, balance)
        .toInt();
    if (principalPaid <= 0) break;
    balance -= principalPaid;
    interest += interestMinor;
    months++;
  }
  return (
    monthsRemaining: balance <= 0 ? months : null,
    totalInterestMinor: interest,
    remainingMinor: balance,
  );
}

class LoanProjection {
  const LoanProjection({
    required this.monthlyEmi,
    required this.monthsRemaining,
    required this.estimatedInterestMinor,
  });

  final int monthlyEmi;
  final int? monthsRemaining;
  final int estimatedInterestMinor;

  String get payoffLabel {
    final months = monthsRemaining;
    if (months == null) {
      if (monthlyEmi > 0) return 'EMI too low to cover interest';
      return 'Add an EMI to estimate payoff';
    }
    if (months == 0) return 'Paid off';
    final years = months ~/ 12;
    final extraMonths = months % 12;
    final monthsLabel = months == 1 ? '1 month' : '$months months';
    final yearsLabel = years == 1 ? '1 year' : '$years years';
    final extraMonthsLabel = extraMonths == 1
        ? '1 month'
        : '$extraMonths months';
    if (years == 0) return '$monthsLabel remaining';
    if (extraMonths == 0) return '$yearsLabel remaining';
    return '$yearsLabel $extraMonthsLabel remaining';
  }
}

String? _tagValue(String? source, String key) {
  if (source == null || source.trim().isEmpty) return null;
  for (final part in source.split('|')) {
    final separator = part.indexOf(':');
    if (separator <= 0) continue;
    final itemKey = part.substring(0, separator).trim();
    if (itemKey != key) continue;
    final value = part.substring(separator + 1).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

double? _doubleTagValue(String? source, String key) {
  final value = _tagValue(source, key);
  return value == null ? null : double.tryParse(value);
}

int? _intTagValue(String? source, String key) {
  final value = _tagValue(source, key);
  return value == null ? null : int.tryParse(value);
}

class CreditCardDueStatus {
  const CreditCardDueStatus({
    required this.account,
    required this.dueDate,
    this.statementDate,
    required this.daysUntilDue,
    required this.isPaid,
    required this.isDueSoon,
    required this.isOverdue,
    required this.cycleKey,
    this.isStatementGenerated = false,
  });

  final Account account;
  final DateTime dueDate;
  final DateTime? statementDate;
  final int daysUntilDue;
  final bool isPaid;
  final bool isDueSoon;
  final bool isOverdue;
  final String cycleKey;
  final bool isStatementGenerated;
}

/// Helper returning ordinal suffix for a day number ('st', 'nd', 'rd', 'th').
String daySuffix(int day) {
  if (day >= 11 && day <= 13) return 'th';
  switch (day % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

CreditCardDueStatus? creditCardDueStatus(
  LedgerState state,
  Account account, {
  DateTime? now,
}) {
  if (account.isArchived ||
      (account.type != 'credit_card' && account.type != 'card')) {
    return null;
  }

  // Must have at least dueDay or statementDay configured
  if (account.dueDay == null && account.statementDay == null) {
    return null;
  }

  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = account.dueDay;
  final statementDay = account.statementDay;

  DateTime targetDueDate;
  DateTime? statementDate;
  String cycleKey;

  if (dueDay != null) {
    final maxDayThisMonth = DateTime(current.year, current.month + 1, 0).day;
    final thisMonthDueDate = DateTime(
      current.year,
      current.month,
      dueDay.clamp(1, maxDayThisMonth),
    );

    final thisMonthCycleKey =
        '${thisMonthDueDate.year}-${thisMonthDueDate.month.toString().padLeft(2, '0')}';
    final thisMonthPaid = account.lastPaidBillMonth == thisMonthCycleKey;

    if (thisMonthPaid && today.isAfter(thisMonthDueDate)) {
      // This month's bill was already paid and its due date has passed.
      // Advance to next month's cycle.
      final nextMonth = DateTime(current.year, current.month + 1);
      final maxDayNextMonth =
          DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
      targetDueDate = DateTime(
        nextMonth.year,
        nextMonth.month,
        dueDay.clamp(1, maxDayNextMonth),
      );
    } else {
      // Focus on this month's due date (whether paid, upcoming, or overdue)
      targetDueDate = thisMonthDueDate;
    }

    cycleKey =
        '${targetDueDate.year}-${targetDueDate.month.toString().padLeft(2, '0')}';

    if (statementDay != null) {
      final stmtMonth = statementDay > dueDay
          ? DateTime(targetDueDate.year, targetDueDate.month - 1)
          : DateTime(targetDueDate.year, targetDueDate.month);
      final maxStmtDay = DateTime(stmtMonth.year, stmtMonth.month + 1, 0).day;
      statementDate = DateTime(
        stmtMonth.year,
        stmtMonth.month,
        statementDay.clamp(1, maxStmtDay),
      );
    }
  } else {
    // Only statementDay is configured (no explicit dueDay)
    final maxStmtDayThisMonth =
        DateTime(current.year, current.month + 1, 0).day;
    final thisMonthStmtDate = DateTime(
      current.year,
      current.month,
      statementDay!.clamp(1, maxStmtDayThisMonth),
    );

    final thisMonthCycleKey =
        '${thisMonthStmtDate.year}-${thisMonthStmtDate.month.toString().padLeft(2, '0')}';
    final thisMonthPaid = account.lastPaidBillMonth == thisMonthCycleKey;

    if (today.isBefore(thisMonthStmtDate)) {
      // The statement for this month has not been generated yet.
      // Check the previous month's statement cycle first.
      final lastMonth = DateTime(current.year, current.month - 1);
      final maxStmtDayLastMonth =
          DateTime(lastMonth.year, lastMonth.month + 1, 0).day;
      final lastMonthStmtDate = DateTime(
        lastMonth.year,
        lastMonth.month,
        statementDay.clamp(1, maxStmtDayLastMonth),
      );
      final lastMonthCycleKey =
          '${lastMonthStmtDate.year}-${lastMonthStmtDate.month.toString().padLeft(2, '0')}';
      final lastMonthPaid = account.lastPaidBillMonth == lastMonthCycleKey;

      if (!lastMonthPaid) {
        // Last month's statement bill is still unpaid (may be overdue or due soon)
        statementDate = lastMonthStmtDate;
      } else {
        // Last month was paid; focus on the upcoming statement this month
        statementDate = thisMonthStmtDate;
      }
    } else if (thisMonthPaid && today.isAfter(thisMonthStmtDate)) {
      final nextMonth = DateTime(current.year, current.month + 1);
      final maxStmtDayNextMonth =
          DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
      statementDate = DateTime(
        nextMonth.year,
        nextMonth.month,
        statementDay.clamp(1, maxStmtDayNextMonth),
      );
    } else {
      statementDate = thisMonthStmtDate;
    }

    // Default 20-day grace period after statement generation
    targetDueDate = statementDate.add(const Duration(days: 20));
    cycleKey =
        '${statementDate.year}-${statementDate.month.toString().padLeft(2, '0')}';
  }

  final isPaid = account.lastPaidBillMonth == cycleKey;
  final daysDiff = targetDueDate.difference(today).inDays;
  final notifyDays = account.notifyDaysBeforeDue ??
      (account.statementDay != null ? 3 : 7);

  final isOverdue = !isPaid && daysDiff < 0;
  final isDueSoon = !isPaid && (daysDiff >= 0 && daysDiff <= notifyDays);
  final isStatementGenerated = !isPaid &&
      statementDate != null &&
      (today.isAfter(statementDate) || today.isAtSameMomentAs(statementDate));

  return CreditCardDueStatus(
    account: account,
    dueDate: targetDueDate,
    statementDate: statementDate,
    daysUntilDue: daysDiff,
    isPaid: isPaid,
    isDueSoon: isDueSoon,
    isOverdue: isOverdue,
    cycleKey: cycleKey,
    isStatementGenerated: isStatementGenerated,
  );
}

int creditCardsDueSoonCount(LedgerState state, {DateTime? now}) {
  final currentTime = now ?? DateTime.now();
  final todayKey =
      '${currentTime.year}-${currentTime.month.toString().padLeft(2, '0')}-${currentTime.day.toString().padLeft(2, '0')}';
  final dismissedIds = state.preferences.dismissedNotificationIds.toSet();

  var count = 0;
  for (final account in state.accounts) {
    final status = creditCardDueStatus(state, account, now: currentTime);
    if (status == null || status.isPaid) continue;
    if (status.isDueSoon || status.isOverdue || status.isStatementGenerated) {
      final isDismissed =
          dismissedIds.contains('card_overdue_${account.id}_$todayKey') ||
          dismissedIds.contains('card_due_${account.id}_$todayKey') ||
          dismissedIds.contains(
            'card_statement_${account.id}_${status.cycleKey}_$todayKey',
          );
      if (!isDismissed) {
        count++;
      }
    }
  }
  return count;
}

