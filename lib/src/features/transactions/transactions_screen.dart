import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/full_screen_picker.dart';
import '../home/home_screen.dart';
import 'transactions_components.dart';
import 'transaction_row.dart';

final _filteredTransactionsProvider = Provider.autoDispose
    .family<List<TransactionRecord>, _TransactionFilterState>((ref, filter) {
      final state = ref.watch(ledgerProvider);
      final query = filter.query;
      final categoryMatchIds = _selectedCategoryMatchIds(
        state,
        filter.categoryFilters,
      );
      return sortedTransactions(state, includeScheduled: false)
          .where((transaction) {
            if (filter.typeFilter == 'income' &&
                !incomeTypes.contains(transaction.type)) {
              return false;
            }
            if (filter.typeFilter == 'expense' &&
                !expenseTypes.contains(transaction.type)) {
              return false;
            }
            if (filter.typeFilter == 'transfer' &&
                transaction.type != 'transfer') {
              return false;
            }
            if (filter.typeFilter == 'adjustment' &&
                transaction.type != 'adjustment') {
              return false;
            }
            if (!_matchesDateFilter(
              transaction.occurredAt,
              filter.dateFilter,
            )) {
              return false;
            }
            if (filter.accountFilter != null &&
                transaction.accountId != filter.accountFilter &&
                transaction.counterAccountId != filter.accountFilter) {
              return false;
            }
            if (transaction.type == 'interest_in' || transaction.type == 'interest_out') {
              final account = accountById(state, transaction.accountId);
              if (account?.loanDetails?.hideInterestInLedger == true) {
                if (filter.accountFilter != account?.id) {
                  return false;
                }
              }
            }
            if (filter.categoryFilterIds.isNotEmpty ||
                filter.includeUncategorizedCategory) {
              final categoryId = transaction.categoryId;
              if (categoryId == null || categoryId.trim().isEmpty) {
                if (!filter.includeUncategorizedCategory) return false;
              } else if (!categoryMatchIds.contains(categoryId)) {
                return false;
              }
            }
            if (query.isEmpty) return true;
            final account = accountById(state, transaction.accountId);
            final counterAccount = accountById(
              state,
              transaction.counterAccountId,
            );
            final category = categoryById(state, transaction.categoryId);
            final haystack = [
              transactionTypeLabel(transaction.type),
              transaction.source,
              account?.name,
              counterAccount?.name,
              category?.name,
              transaction.paymentMethod,
              transaction.notes,
            ].whereType<String>().join(' ').toLowerCase();
            return haystack.contains(query);
          })
          .toList(growable: false);
    });

final _transactionsFlowProvider = Provider.autoDispose
    .family<({Money income, Money expense}), _TransactionFilterState>((
      ref,
      filter,
    ) {
      final state = ref.watch(ledgerProvider);
      final transactions = ref.watch(_filteredTransactionsProvider(filter));
      var income = 0;
      var expense = 0;
      for (final transaction in transactions) {
        if (transaction.status == 'scheduled' || transaction.status == 'void') {
          continue;
        }
        if (transaction.isExcludedFromReports) continue;
        if (incomeTypes.contains(transaction.type)) {
          income += transaction.baseAmount.amountMinor;
        }
        if (expenseTypes.contains(transaction.type)) {
          expense += transaction.baseAmount.amountMinor;
        }
      }
      final baseIncome = Money(
        amountMinor: income,
        currency: state.preferences.baseCurrency,
      );
      final baseExpense = Money(
        amountMinor: expense,
        currency: state.preferences.baseCurrency,
      );
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
    });

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({required this.onMenuPressed, super.key});

  final VoidCallback onMenuPressed;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  static const _defaultDateFilter = 'this_year';

  var _query = '';
  var _typeFilter = 'all';
  var _dateFilter = _defaultDateFilter;
  final Set<String> _categoryFilters = <String>{};
  var _includeUncategorizedCategory = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final accountFilter = ref.watch(homeSelectedAccountProvider);
    final filterState = _TransactionFilterState(
      query: _query,
      typeFilter: _typeFilter,
      dateFilter: _dateFilter,
      categoryFilterIds: _categoryFilters,
      includeUncategorizedCategory: _includeUncategorizedCategory,
      accountFilter: accountFilter,
    );
    final transactions = ref.watch(_filteredTransactionsProvider(filterState));
    final flow = ref.watch(_transactionsFlowProvider(filterState));
    final hasActiveFilters = _hasActiveFilters(accountFilter);

    return AppScreen(
      title: 'Transactions',
      onMenuPressed: widget.onMenuPressed,
      floatingActionButton: IslandFloatingActionButton(
        icon: Icons.add_rounded,
        tooltip: 'Add record',
        onPressed: () => context.push('/add'),
      ),
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      actions: [
        HeaderIconButton(
          icon: Icons.currency_exchange_rounded,
          onPressed: () => _showDisplayCurrencyPicker(state),
        ),
        HeaderIconButton(
          icon: Icons.add_rounded,
          onPressed: () => context.push('/add'),
        ),
        HeaderIconButton(
          icon: Icons.dashboard_customize_outlined,
          onPressed: () => context.push('/widgets'),
        ),
      ],
      child: Column(
        children: [
          TransactionCommandStrip(
            query: _query,
            income: formatCompactMoney(flow.income, state.preferences.locale),
            expense: formatCompactMoney(flow.expense, state.preferences.locale),
            net: formatCompactMoney(
              Money(
                amountMinor: flow.income.amountMinor - flow.expense.amountMinor,
                currency: flow.income.currency,
              ),
              state.preferences.locale,
            ),
            typeLabel: _typeFilterLabel(_typeFilter),
            dateLabel: _dateFilterLabel(_dateFilter),
            accountLabel:
                accountById(state, accountFilter)?.name ?? 'All accounts',
            categoryLabel: _categoryFilterLabel(state),
            typeActive: _typeFilter != 'all',
            dateActive: _dateFilter != _defaultDateFilter,
            accountActive: accountFilter != null,
            categoryActive:
                _categoryFilters.isNotEmpty || _includeUncategorizedCategory,
            hasActiveFilters: hasActiveFilters,
            onQueryChanged: (value) => setState(() => _query = value),
            onClear: _clearFilters,
            onTypeTap: () => _showTypeFilter(state),
            onDateTap: _showDateFilter,
            onAccountTap: () => _showAccountFilter(state, accountFilter),
            onCategoryTap: () => _showCategoryFilter(state),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: transactions.isEmpty
                ? EmptyState(
                    icon: Icons.format_list_bulleted_rounded,
                    title: 'No matching transactions',
                    body: hasActiveFilters
                        ? 'Clear filters to see the full ledger.'
                        : 'Add a new record to start building your ledger.',
                    actionLabel: hasActiveFilters
                        ? 'Clear filters'
                        : 'Add transaction',
                    onAction: hasActiveFilters
                        ? _clearFilters
                        : () => context.push('/add'),
                  )
                : Builder(
                    builder: (context) {
                      final monthlyFlows = <String, int>{};
                      for (final t in transactions) {
                        final monthStr = DateFormat('MMM yyyy', state.preferences.locale.replaceAll('_', '-')).format(t.occurredAt).toUpperCase();
                        final sign = (incomeTypes.contains(t.type) || t.type == 'transferIn') ? 1 : -1;
                        final converted = convertMoneyForDisplay(state, t.amount, state.preferences.displayCurrency);
                        monthlyFlows[monthStr] = (monthlyFlows[monthStr] ?? 0) + (converted.amountMinor * sign);
                      }

                      final includedAccounts = accountFilter != null 
                          ? {accountFilter} 
                          : { for (final a in state.accounts) if (!a.isArchived && a.includeInTotals) a.id };
                          
                      var running = state.accounts
                          .where((a) => includedAccounts.contains(a.id))
                          .fold<int>(0, (sum, a) => sum + convertMoneyForDisplay(state, a.openingBalance, state.preferences.displayCurrency).amountMinor);
                          
                      final monthlyBalances = <String, int>{};
                      final fullLedger = sortedTransactions(state, includeScheduled: false).reversed;
                      
                      for (final t in fullLedger) {
                          final monthStr = DateFormat('MMM yyyy', state.preferences.locale.replaceAll('_', '-')).format(t.occurredAt).toUpperCase();
                          var delta = 0;
                          if (includedAccounts.contains(t.accountId)) {
                              delta += convertMoneyForDisplay(state, Money(amountMinor: sourceDelta(t), currency: t.amount.currency), state.preferences.displayCurrency).amountMinor;
                          }
                          if (t.counterAccountId != null && includedAccounts.contains(t.counterAccountId)) {
                              delta += convertMoneyForDisplay(state, Money(amountMinor: counterDelta(t), currency: (t.counterAmount ?? t.amount).currency), state.preferences.displayCurrency).amountMinor;
                          }
                          running += delta;
                          monthlyBalances[monthStr] = running;
                      }

                      final items = <Object>[];
                      String? currentMonth;
                      for (final t in transactions) {
                        final monthStr = DateFormat('MMM yyyy', state.preferences.locale.replaceAll('_', '-')).format(t.occurredAt).toUpperCase();
                        if (currentMonth != monthStr) {
                          currentMonth = monthStr;
                          items.add(_MonthHeaderItem(
                            monthStr: monthStr,
                            netFlow: monthlyFlows[monthStr] ?? 0,
                            balance: monthlyBalances[monthStr] ?? 0,
                          ));
                        }
                        items.add(t);
                      }
                      
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSizes.bottomBarClearance),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          if (item is _MonthHeaderItem) {
                            final balanceStr = formatMoney(Money(amountMinor: item.balance, currency: state.preferences.displayCurrency), state.preferences.locale);
                            final flowStr = formatMoney(Money(amountMinor: item.netFlow, currency: state.preferences.displayCurrency), state.preferences.locale);
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.lg, AppSpacing.sm, AppSpacing.xs),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    item.monthStr,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Balance $balanceStr',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '∑ $flowStr',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }
                          
                          final transaction = item as TransactionRecord;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: TransactionRow(
                              state: state,
                              transaction: transaction,
                              selectedAccountId: accountFilter,
                              onTap: () => context.push('/transaction/${transaction.id}'),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters(String? accountFilter) {
    return _query.trim().isNotEmpty ||
        _typeFilter != 'all' ||
        _dateFilter != _defaultDateFilter ||
        accountFilter != null ||
        _categoryFilters.isNotEmpty ||
        _includeUncategorizedCategory;
  }

  void _clearFilters() {
    setState(() {
      _query = '';
      _typeFilter = 'all';
      _dateFilter = _defaultDateFilter;
      _categoryFilters.clear();
      _includeUncategorizedCategory = false;
    });
    ref.read(homeSelectedAccountProvider.notifier).state = null;
  }

  Future<void> _showDisplayCurrencyPicker(LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Display currency',
      searchHint: 'Search currencies',
      selectedValue: state.preferences.displayCurrency,
      options: [
        for (final currency in availableCurrencies(state))
          PickerOption(
            value: currency,
            title: currency,
            subtitle: currency == state.preferences.baseCurrency
                ? 'Base currency'
                : 'Show totals and ≈ values in $currency',
            icon: Icons.currency_exchange_outlined,
          ),
      ],
    );
    if (next == null) return;
    await ref.read(ledgerProvider.notifier).setDisplayCurrency(next);
  }

  Future<void> _showTypeFilter(LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Choose type',
      searchable: false,
      selectedValue: _typeFilter,
      options: const [
        PickerOption(
          value: 'all',
          title: 'All records',
          icon: Icons.all_inclusive_rounded,
        ),
        PickerOption(
          value: 'income',
          title: 'Income',
          icon: Icons.trending_up_rounded,
        ),
        PickerOption(
          value: 'expense',
          title: 'Expense',
          icon: Icons.trending_down_rounded,
        ),
        PickerOption(
          value: 'transfer',
          title: 'Transfer',
          icon: Icons.swap_horiz_rounded,
        ),
        PickerOption(
          value: 'adjustment',
          title: 'Adjustment',
          icon: Icons.tune_rounded,
        ),
      ],
    );
    if (next != null) setState(() => _typeFilter = next);
  }

  Future<void> _showDateFilter() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Choose date range',
      searchable: false,
      selectedValue: _dateFilter,
      options: const [
        PickerOption(
          value: 'all',
          title: 'All time',
          icon: Icons.all_inclusive_rounded,
        ),
        PickerOption(
          value: 'this_month',
          title: 'This month',
          icon: Icons.calendar_month_outlined,
        ),
        PickerOption(
          value: 'last_30_days',
          title: 'Last 30 days',
          icon: Icons.history_rounded,
        ),
        PickerOption(
          value: 'this_year',
          title: 'This year',
          icon: Icons.event_note_outlined,
        ),
      ],
    );
    if (next != null) setState(() => _dateFilter = next);
  }

  Future<void> _showAccountFilter(
    LedgerState state,
    String? accountFilter,
  ) async {
    final balances = accountBalanceMap(state);
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Choose account',
      searchHint: 'Search accounts',
      selectedValue: accountFilter ?? '__all__',
      options: [
        const PickerOption(
          value: '__all__',
          title: 'All accounts',
          subtitle: 'Include every account',
          icon: Icons.all_inclusive_rounded,
        ),
        for (final account in state.accounts.where(
          (account) => !account.isArchived,
        ))
          PickerOption(
            value: account.id,
            title: account.name,
            subtitle:
                '${accountTypeLabel(account.type)} · ${formatMoney(accountBalanceFromMap(balances, account), state.preferences.locale)}',
            icon: accountIcon(account),
            iconColor: accountDisplayColor(account),
            searchText:
                '${account.institution ?? ''} ${account.groupName ?? ''}',
          ),
      ],
    );
    if (next == null) return;
    ref.read(homeSelectedAccountProvider.notifier).state = next == '__all__'
        ? null
        : next;
  }

  Future<void> _showCategoryFilter(LedgerState state) async {
    final selected = Set<String>.from(_categoryFilters);
    var includeUncategorized = _includeUncategorizedCategory;
    final result = await showDialog<_CategoryFilterResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final categories = state.categories
                .where((category) => !category.isArchived)
                .toList();
            return AlertDialog(
              title: const Text('Choose categories'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        value: includeUncategorized,
                        onChanged: (value) => setDialogState(
                          () => includeUncategorized = value ?? false,
                        ),
                        title: const Text('Uncategorized'),
                        subtitle: const Text('Records without a category'),
                        secondary: const Icon(Icons.label_off_outlined),
                      ),
                      for (final category in categories)
                        CheckboxListTile(
                          value: selected.contains(category.id),
                          onChanged: (value) => setDialogState(() {
                            if (value ?? false) {
                              selected.add(category.id);
                            } else {
                              selected.remove(category.id);
                            }
                          }),
                          title: Text(category.name),
                          subtitle: Text(category.kind),
                          secondary: Icon(
                            Icons.category_outlined,
                            color: categoryColor(category, context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const _CategoryFilterResult(
                      categoryIds: <String>{},
                      includeUncategorized: false,
                    ),
                  ),
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _CategoryFilterResult(
                      categoryIds: Set<String>.from(selected),
                      includeUncategorized: includeUncategorized,
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() {
      _categoryFilters
        ..clear()
        ..addAll(result.categoryIds);
      _includeUncategorizedCategory = result.includeUncategorized;
    });
  }

  String _categoryFilterLabel(LedgerState state) {
    final count =
        _categoryFilters.length + (_includeUncategorizedCategory ? 1 : 0);
    if (count == 0) return 'All categories';
    if (count == 1 && _includeUncategorizedCategory) return 'Uncategorized';
    if (count == 1) {
      final category = categoryById(state, _categoryFilters.first);
      return category?.name ?? '1 category';
    }
    return '$count categories';
  }
}

class _TransactionFilterState {
  _TransactionFilterState({
    required String query,
    required this.typeFilter,
    required this.dateFilter,
    required Set<String> categoryFilterIds,
    required this.includeUncategorizedCategory,
    required this.accountFilter,
  }) : query = query.trim().toLowerCase(),
       categoryFilterIds = (categoryFilterIds.toList()..sort()).join('|');

  final String query;
  final String typeFilter;
  final String dateFilter;
  final String categoryFilterIds;
  final bool includeUncategorizedCategory;
  final String? accountFilter;

  List<String> get categoryFilters => categoryFilterIds.isEmpty
      ? const <String>[]
      : categoryFilterIds.split('|');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TransactionFilterState &&
        other.query == query &&
        other.typeFilter == typeFilter &&
        other.dateFilter == dateFilter &&
        other.categoryFilterIds == categoryFilterIds &&
        other.includeUncategorizedCategory == includeUncategorizedCategory &&
        other.accountFilter == accountFilter;
  }

  @override
  int get hashCode => Object.hash(
    query,
    typeFilter,
    dateFilter,
    categoryFilterIds,
    includeUncategorizedCategory,
    accountFilter,
  );
}

Set<String> _selectedCategoryMatchIds(
  LedgerState state,
  List<String> categoryFilters,
) {
  final ids = <String>{};
  void addWithDescendants(String id) {
    if (!ids.add(id)) return;
    for (final category in state.categories) {
      if (category.parentId == id) addWithDescendants(category.id);
    }
  }

  for (final id in categoryFilters) {
    addWithDescendants(id);
  }
  return ids;
}

bool _matchesDateFilter(DateTime date, String dateFilter) {
  final now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  return switch (dateFilter) {
    'this_month' => date.year == now.year && date.month == now.month,
    'last_30_days' => !day.isBefore(
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)),
    ),
    'this_year' => date.year == now.year,
    _ => true,
  };
}

class _CategoryFilterResult {
  const _CategoryFilterResult({
    required this.categoryIds,
    required this.includeUncategorized,
  });

  final Set<String> categoryIds;
  final bool includeUncategorized;
}

String _typeFilterLabel(String value) {
  return switch (value) {
    'income' => 'Income',
    'expense' => 'Expense',
    'transfer' => 'Transfer',
    'adjustment' => 'Adjustment',
    _ => 'All types',
  };
}

String _dateFilterLabel(String value) {
  return switch (value) {
    'this_month' => 'This month',
    'last_30_days' => 'Last 30 days',
    'this_year' => 'This year',
    _ => 'All time',
  };
}

class _MonthHeaderItem {
  final String monthStr;
  final int balance;
  final int netFlow;
  
  _MonthHeaderItem({
    required this.monthStr,
    required this.balance,
    required this.netFlow,
  });
}
