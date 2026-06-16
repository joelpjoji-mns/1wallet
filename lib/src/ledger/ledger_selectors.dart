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

List<TransactionRecord> sortedTransactions(
  LedgerState state, {
  bool includeScheduled = true,
  bool hideInterest = false,
}) {
  final items = state.transactions
      .where(
        (transaction) => includeScheduled || transaction.status != 'scheduled',
      )
      .where(
        (transaction) => !hideInterest || !isHiddenInterest(state, transaction),
      )
      .toList();
  items.sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
  return items;
}

List<TransactionRecord> transactionsForAccount(
  LedgerState state,
  String accountId,
) {
  return sortedTransactions(state).where((transaction) {
    return transaction.accountId == accountId ||
        transaction.counterAccountId == accountId;
  }).toList();
}

Map<String, Money> accountBalanceMap(LedgerState state) {
  final balances = <String, Money>{
    for (final account in state.accounts)
      account.id: account.openingBalance.copyWith(currency: account.currency),
  };

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
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

  return balances;
}

Money accountBalanceFromMap(Map<String, Money> balances, Account account) {
  return balances[account.id] ??
      account.openingBalance.copyWith(currency: account.currency);
}

Money accountBalance(LedgerState state, Account account) {
  var amountMinor = account.openingBalance.amountMinor;
  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
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
  if (transaction.counterAmount == null) return transaction.amount;
  final cashCurrency = cashAccount.currency.toUpperCase();
  final sourceCurrency = transaction.amount.currency.toUpperCase();
  final counterCurrency = transaction.counterAmount!.currency.toUpperCase();
  return counterCurrency == cashCurrency && sourceCurrency != cashCurrency
      ? transaction.amount
      : transaction.counterAmount!;
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

  addMoney(account.openingBalance, 1);

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
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
      .where((m) => m.amountMinor != 0)
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

double? rateBetween(LedgerState state, String from, String to) {
  final source = from.toUpperCase();
  final target = to.toUpperCase();
  if (source == target) return 1;

  final direct = latestExchangeRate(state, source, target);
  if (direct != null) return direct.rate;
  final inverse = latestExchangeRate(state, target, source);
  if (inverse != null && inverse.rate > 0) return 1 / inverse.rate;

  return _inferredRateBetween(state, source, target);
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
    return (transaction.counterAmount ?? transaction.amount).amountMinor.abs();
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
            ? state.accounts.where((a) => a.type == 'cash' && !a.isArchived)
            : state.accounts.where((a) => a.id == accountId))
      : state.accounts.where(
          (account) => account.includeInNetWorth && account.type != 'loan',
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
    if (account.isArchived || !account.includeInNetWorth) continue;
    final balance = convertMoneyForDisplay(
      state,
      accountBalanceFromMap(balances, account),
      state.preferences.displayCurrency,
    ).amountMinor;
    if (isLiabilityAccount(account)) {
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

({Money income, Money expense}) flowForCurrentMonth(LedgerState state) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  var income = 0;
  var expense = 0;
  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
      continue;
    }
    if (transaction.isExcludedFromReports) continue;
    if (isHiddenInterest(state, transaction)) continue;
    if (transaction.occurredAt.isBefore(start) ||
        !transaction.occurredAt.isBefore(end)) {
      continue;
    }
    if (incomeTypes.contains(transaction.type)) {
      income += transaction.baseAmount.amountMinor;
    }
    if (expenseTypes.contains(transaction.type)) {
      expense += transaction.baseAmount.amountMinor;
    }
  }
  final currency = state.preferences.baseCurrency;
  final baseIncome = Money(amountMinor: income, currency: currency);
  final baseExpense = Money(amountMinor: expense, currency: currency);
  return (
    income: convertMoneyForDisplay(
      state,
      baseIncome,
      state.preferences.displayCurrency,
    ),
    expense: convertMoneyForDisplay(
      state,
      baseExpense,
      state.preferences.displayCurrency,
    ),
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

  var income = 0;
  var expense = 0;
  final cashAccountIds = accountId == 'cash_group'
      ? state.accounts.where((a) => a.type == 'cash').map((a) => a.id).toSet()
      : const <String>{};

  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
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
        if (cashAccountIds.contains(transaction.accountId)) {
          final delta = sourceDelta(transaction);
          if (delta > 0) income += transaction.baseAmount.amountMinor;
          if (delta < 0) expense += transaction.baseAmount.amountMinor;
        }
        if (cashAccountIds.contains(transaction.counterAccountId)) {
          final delta = counterDelta(transaction);
          if (delta > 0) income += transaction.baseAmount.amountMinor;
          if (delta < 0) expense += transaction.baseAmount.amountMinor;
        }
      } else {
        if (transaction.accountId == accountId) {
          final delta = sourceDelta(transaction);
          if (delta > 0) income += transaction.baseAmount.amountMinor;
          if (delta < 0) expense += transaction.baseAmount.amountMinor;
        }
        if (transaction.counterAccountId == accountId) {
          final delta = counterDelta(transaction);
          if (delta > 0) income += transaction.baseAmount.amountMinor;
          if (delta < 0) expense += transaction.baseAmount.amountMinor;
        }
      }
    } else {
      if (incomeTypes.contains(transaction.type)) {
        income += transaction.baseAmount.amountMinor;
      }
      if (expenseTypes.contains(transaction.type)) {
        expense += transaction.baseAmount.amountMinor;
      }
    }
  }
  final currency = state.preferences.baseCurrency;
  final baseIncome = Money(amountMinor: income, currency: currency);
  final baseExpense = Money(amountMinor: expense, currency: currency);
  return (
    income: convertMoneyForDisplay(
      state,
      baseIncome,
      targetCurrency ?? state.preferences.displayCurrency,
    ),
    expense: convertMoneyForDisplay(
      state,
      baseExpense,
      targetCurrency ?? state.preferences.displayCurrency,
    ),
  );
}

List<TransactionRecord> scheduledTransactions(LedgerState state) {
  final items = sortedTransactions(
      state,
    ).where((transaction) => transaction.status == 'scheduled' || transaction.status == 'paused').toList();
  items.sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
  return items;
}

Category? categoryById(LedgerState state, String? id) {
  if (id == null) return null;
  for (final category in state.categories) {
    if (category.id == id) return category;
  }
  return null;
}

Account? accountById(LedgerState state, String? id) {
  if (id == null) return null;
  for (final account in state.accounts) {
    if (account.id == id) return account;
  }
  return null;
}

String categoryPath(LedgerState state, Category? category) {
  if (category == null) return '';
  final byId = {for (final item in state.categories) item.id: item};
  final names = <String>[];
  Category? current = category;
  final seen = <String>{};
  while (current != null && seen.add(current.id)) {
    names.insert(0, current.name);
    current = byId[current.parentId];
  }
  return names.join(' > ');
}

int compareCategories(Category left, Category right) {
  final orderCompare = left.sortOrder.compareTo(right.sortOrder);
  return orderCompare != 0
      ? orderCompare
      : left.name.toLowerCase().compareTo(right.name.toLowerCase());
}

int compareCategoriesByUsage(
  LedgerState state,
  Category left,
  Category right,
) {
  final leftUsage = categoryUsageCount(state, left, includeDescendants: true);
  final rightUsage = categoryUsageCount(state, right, includeDescendants: true);
  final usageCompare = rightUsage.compareTo(leftUsage);
  return usageCompare != 0 ? usageCompare : compareCategories(left, right);
}

int categoryUsageCount(
  LedgerState state,
  Category category, {
  bool includeDescendants = false,
}) {
  final categoryIds = <String>{category.id};
  if (includeDescendants) {
    void collectChildren(String parentId) {
      for (final child in state.categories) {
        if (child.parentId != parentId || categoryIds.contains(child.id)) {
          continue;
        }
        categoryIds.add(child.id);
        collectChildren(child.id);
      }
    }

    collectChildren(category.id);
  }
  return state.transactions.where((transaction) {
    if (transaction.status == 'void') return false;
    final categoryId = transaction.categoryId;
    return categoryId != null && categoryIds.contains(categoryId);
  }).length;
}

List<Category> sortedCategories(Iterable<Category> categories) {
  return categories.toList()..sort(compareCategories);
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

String formatMoney(Money money, String locale) {
  final amount = money.amountMinor / math.pow(10, minorUnits(money.currency));
  try {
    return NumberFormat.simpleCurrency(
      locale: locale.replaceAll('_', '-'),
      name: money.currency,
    ).format(amount);
  } catch (_) {
    return '${money.currency} ${amount.toStringAsFixed(minorUnits(money.currency))}';
  }
}

String formatCompactMoney(Money money, String locale) {
  final amount =
      money.amountMinor.abs() / math.pow(10, minorUnits(money.currency));
  final sign = money.amountMinor < 0 ? '-' : '';
  final symbol = NumberFormat.simpleCurrency(
    locale: locale.replaceAll('_', '-'),
    name: money.currency,
  ).currencySymbol;
  if (amount >= 10000000) {
    return '$sign${(amount / 10000000).toStringAsFixed(1)}Cr';
  }
  if (amount >= 100000) return '$sign${(amount / 100000).toStringAsFixed(1)}L';
  if (amount >= 1000) return '$sign${(amount / 1000).toStringAsFixed(1)}k';
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
    return DateFormat(formatStr, normalizedLocale).format(date);
  } catch (_) {
    return DateFormat(formatStr).format(date);
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
  'JPY' => 0,
  _ => 2,
};

double? _inferredRateBetween(LedgerState state, String from, String to) {
  final transactions = sortedTransactions(state, includeScheduled: false);
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
    if (rate != null && rate > 0 && rate.isFinite) return rate;
  }
  return null;
}

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

IconData accountIcon(Account account) {
  return switch (account.type) {
    'cash' => Icons.payments_outlined,
    'bank' => Icons.account_balance_outlined,
    'credit_card' => Icons.credit_card_outlined,
    'loan' || 'overdraft' => Icons.account_balance_outlined,
    'wallet' => Icons.account_balance_wallet_outlined,
    _ => Icons.wallet_outlined,
  };
}

IconData categoryIcon(Category? category) {
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
  if (key.contains('food') ||
      key.contains('grocer') ||
      key.contains('dining') ||
      key.contains('coffee')) {
    return Icons.restaurant_outlined;
  }
  if (key.contains('transport') ||
      key.contains('fuel') ||
      key.contains('taxi') ||
      key.contains('vehicle')) {
    return Icons.directions_car_outlined;
  }
  if (key.contains('transit')) return Icons.directions_bus_outlined;
  if (key.contains('health') ||
      key.contains('doctor') ||
      key.contains('pharmacy')) {
    return Icons.health_and_safety_outlined;
  }
  if (key.contains('fitness')) return Icons.fitness_center_rounded;
  if (key.contains('insurance')) return Icons.verified_user_outlined;
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
  if (key.contains('shopping') ||
      key.contains('clothing') ||
      key.contains('electronics') ||
      key.contains('personal care')) {
    return Icons.shopping_bag_outlined;
  }
  if (key.contains('family') || key.contains('children')) {
    return Icons.family_restroom_rounded;
  }
  if (key.contains('pet')) return Icons.pets_outlined;
  if (key.contains('gift') || key.contains('charity')) {
    return Icons.card_giftcard_outlined;
  }
  if (key.contains('lifestyle') ||
      key.contains('movie') ||
      key.contains('event') ||
      key.contains('hobb')) {
    return Icons.celebration_outlined;
  }
  if (key.contains('subscription')) return Icons.subscriptions_outlined;
  if (key.contains('course') || key.contains('book')) {
    return Icons.school_outlined;
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

String _categoryIconKey(Category? category) {
  if (category == null) return '';
  return '${category.id} ${category.name}'
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
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
