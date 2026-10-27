import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../common/category_hierarchy_picker.dart';
import '../common/full_screen_picker.dart';
import '../home/home_screen.dart';
import 'transactions_components.dart';
import 'transaction_row.dart';

final _filteredTransactionsProvider = Provider.autoDispose
    .family<List<TransactionRecord>, _TransactionFilterState>((ref, filter) {
      ref.watch(
        ledgerProvider.select(
          (s) => (
            s.transactions,
            s.categories,
            s.preferences.hideSkippedInHistory,
          ),
        ),
      );
      final state = ref.read(ledgerProvider);
      final query = filter.query;
      final categoryMatchIds = _selectedCategoryMatchIds(
        state,
        filter.categoryFilters,
      );
      final now = DateTime.now();
      RegExp? regex;
      if (query.isNotEmpty) {
        try {
          regex = RegExp(query, caseSensitive: false);
        } catch (_) {}
      }
      return sortedTransactions(state, includeScheduled: false)
          .where((transaction) {
            if (state.preferences.hideSkippedInHistory &&
                transaction.status == 'void' &&
                filter.statusFilter != 'void') {
              return false;
            }
            if (filter.statusFilter != 'all') {
              if (filter.statusFilter == 'cleared' &&
                  transaction.status != 'cleared') {
                return false;
              }
              if (filter.statusFilter == 'pending' &&
                  transaction.status != 'pending') {
                return false;
              }
              if (filter.statusFilter == 'void' &&
                  transaction.status != 'void') {
                return false;
              }
            }
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
            if (!_matchesDateFilter(
              transaction.occurredAt,
              filter.dateFilter,
              now: now,
            )) {
              return false;
            }
            if (filter.accountFilter != null &&
                transaction.accountId != filter.accountFilter &&
                transaction.counterAccountId != filter.accountFilter) {
              return false;
            }
            if (isHiddenInterest(state, transaction)) {
              if (filter.accountFilter != transaction.accountId &&
                  filter.accountFilter != transaction.counterAccountId) {
                return false;
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
            if (filter.tagFilter != 'all') {
              if (!transaction.tags.contains(filter.tagFilter)) {
                return false;
              }
            }
            if (query.isEmpty) return true;

            final queryNorm = query.toLowerCase().trim();
            final queryTokens = queryNorm
                .split(RegExp(r'\s+'))
                .where((t) => t.isNotEmpty)
                .toList();

            final notes = transaction.notes?.toLowerCase() ?? '';
            final name = transaction.name?.toLowerCase() ?? '';
            final location = transaction.locationLabel?.toLowerCase() ?? '';
            final payment = transaction.paymentMethod?.toLowerCase() ?? '';
            final tags = transaction.tags.map((t) => t.toLowerCase()).join(' ');
            final cat = transaction.categoryId != null
                ? categoryById(
                        state,
                        transaction.categoryId,
                      )?.name.toLowerCase() ??
                      ''
                : '';
            final acc =
                accountById(state, transaction.accountId)?.name.toLowerCase() ??
                '';
            final counterAcc = transaction.counterAccountId != null
                ? accountById(
                        state,
                        transaction.counterAccountId,
                      )?.name.toLowerCase() ??
                      ''
                : '';
            final amountStr = formatMoney(
              transaction.amount,
              state.preferences.locale,
            ).toLowerCase();
            final rawAmount = (transaction.amount.amountMinor / 100).toString();

            final combined =
                '$notes $name $location $payment $tags $cat $acc $counterAcc $amountStr $rawAmount';

            final allTokensMatch = queryTokens.every(
              (token) => combined.contains(token),
            );
            if (allTokensMatch) return true;

            if (regex != null) {
              if (transaction.notes != null &&
                  regex.hasMatch(transaction.notes!)) {
                return true;
              }
              if (transaction.name != null &&
                  regex.hasMatch(transaction.name!)) {
                return true;
              }
              if (transaction.locationLabel != null &&
                  regex.hasMatch(transaction.locationLabel!)) {
                return true;
              }
            }
            return false;
          })
          .toList(growable: false);
    });

final _transactionsFlowProvider = Provider.autoDispose
    .family<({Money income, Money expense}), _TransactionFilterState>((
      ref,
      filter,
    ) {
      ref.watch(
        ledgerProvider.select(
          (s) => (
            s.preferences.baseCurrency,
            s.preferences.displayCurrency,
            s.exchangeRates,
          ),
        ),
      );
      final state = ref.read(ledgerProvider);
      final transactions = ref.watch(_filteredTransactionsProvider(filter));
      var income = 0;
      var expense = 0;
      for (final transaction in transactions) {
        if (transaction.status == 'scheduled' ||
            transaction.status == 'paused' ||
            transaction.status == 'void') {
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

final _monthlyStatsProvider = Provider.autoDispose
    .family<
      ({Map<String, int> monthlyBalances, Map<String, int> monthlyFlows}),
      ({String? accountFilter, String displayCurrency, String locale})
    >((ref, params) {
      ref.watch(
        ledgerProvider.select(
          (s) => (s.transactions, s.accounts, s.exchangeRates),
        ),
      );
      final state = ref.read(ledgerProvider);
      final includedAccounts = params.accountFilter != null
          ? {params.accountFilter}
          : {
              for (final a in state.accounts)
                if (!a.isArchived && a.includeInTotals) a.id,
            };

      var running = state.accounts
          .where((a) => includedAccounts.contains(a.id))
          .fold<int>(0, (sum, a) {
            final converted = convertMoneyForDisplay(
              state,
              a.openingBalance,
              params.displayCurrency,
            );
            if (converted.currency != params.displayCurrency) {
              return sum;
            }
            return sum + converted.amountMinor;
          });

      final monthlyBalances = <String, int>{};
      final monthlyFlows = <String, int>{};
      final monthFormat = DateFormat('MMM yyyy', params.locale);
      final fullLedger = sortedTransactions(
        state,
        includeScheduled: false,
      ).reversed;

      for (final t in fullLedger) {
        final monthStr = monthFormat.format(t.occurredAt).toUpperCase();
        final sourceIncluded = includedAccounts.contains(t.accountId);
        final counterIncluded =
            t.counterAccountId != null &&
            includedAccounts.contains(t.counterAccountId);

        var delta = 0;
        if (sourceIncluded) {
          final sourceConverted = convertMoneyForDisplay(
            state,
            Money(amountMinor: sourceDelta(t), currency: t.amount.currency),
            params.displayCurrency,
          );
          if (sourceConverted.currency == params.displayCurrency) {
            delta += sourceConverted.amountMinor;
          }
        }
        if (counterIncluded) {
          final counterConverted = convertMoneyForDisplay(
            state,
            Money(
              amountMinor: counterDelta(t),
              currency: (t.counterAmount ?? t.amount).currency,
            ),
            params.displayCurrency,
          );
          if (counterConverted.currency == params.displayCurrency) {
            delta += counterConverted.amountMinor;
          }
        }
        running += delta;
        monthlyBalances[monthStr] = running;

        if (t.status == 'scheduled' ||
            t.status == 'paused' ||
            t.status == 'void') {
          continue;
        }
        if (t.isExcludedFromReports) continue;
        if (!sourceIncluded && !counterIncluded) continue;

        int flowMinor = 0;
        if (t.type == 'transfer') {
          if (sourceIncluded && !counterIncluded) {
            final converted = convertMoneyForDisplay(
              state,
              t.amount,
              params.displayCurrency,
            );
            flowMinor = -converted.amountMinor;
          } else if (!sourceIncluded && counterIncluded) {
            final counterAmt = t.counterAmount ?? t.amount;
            final converted = convertMoneyForDisplay(
              state,
              counterAmt,
              params.displayCurrency,
            );
            flowMinor = converted.amountMinor;
          }
        } else if (incomeTypes.contains(t.type)) {
          if (sourceIncluded) {
            final converted = convertMoneyForDisplay(
              state,
              t.amount,
              params.displayCurrency,
            );
            flowMinor = converted.amountMinor;
          }
        } else if (expenseTypes.contains(t.type)) {
          if (sourceIncluded) {
            final converted = convertMoneyForDisplay(
              state,
              t.amount,
              params.displayCurrency,
            );
            flowMinor = -converted.amountMinor;
          }
        }

        if (flowMinor != 0) {
          monthlyFlows[monthStr] = (monthlyFlows[monthStr] ?? 0) + flowMinor;
        } else {
          monthlyFlows[monthStr] = monthlyFlows[monthStr] ?? 0;
        }
      }

      return (monthlyBalances: monthlyBalances, monthlyFlows: monthlyFlows);
    });

final transactionsTypeFilterProvider = StateProvider<String>((ref) => 'all');
final transactionsDateFilterProvider = StateProvider<String>(
  (ref) => 'this_year',
);
final transactionsStatusFilterProvider = StateProvider<String>((ref) => 'all');
final transactionsCategoryFilterProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);
final transactionsTagFilterProvider = StateProvider<String>((ref) => 'all');

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({required this.onMenuPressed, super.key});

  final VoidCallback onMenuPressed;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  static const _defaultDateFilter = 'this_year';

  var _query = '';
  final Set<String> _categoryFilters = <String>{};
  var _includeUncategorizedCategory = false;
  final Set<String> _selectedTransactionIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final accountFilter = ref.watch(homeSelectedAccountProvider);
    final typeFilter = ref.watch(transactionsTypeFilterProvider);
    final dateFilter = ref.watch(transactionsDateFilterProvider);
    final statusFilter = ref.watch(transactionsStatusFilterProvider);
    final tagFilter = ref.watch(transactionsTagFilterProvider);
    final globalCategoryFilter = ref.watch(transactionsCategoryFilterProvider);
    final effectiveCategoryFilters = globalCategoryFilter.isNotEmpty
        ? globalCategoryFilter
        : _categoryFilters;
    final filterState = _TransactionFilterState(
      query: _query,
      typeFilter: typeFilter,
      dateFilter: dateFilter,
      statusFilter: statusFilter,
      categoryFilterIds: effectiveCategoryFilters,
      includeUncategorizedCategory: _includeUncategorizedCategory,
      accountFilter: accountFilter,
      tagFilter: tagFilter,
    );
    final transactions = ref.watch(_filteredTransactionsProvider(filterState));
    final flow = ref.watch(_transactionsFlowProvider(filterState));
    final hasActiveFilters = _hasActiveFilters(accountFilter);
    final allLedgerTags =
        state.transactions
            .expand((t) => t.tags)
            .where((t) => t.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return AppScreen(
      title: _selectedTransactionIds.isNotEmpty
          ? '${_selectedTransactionIds.length} selected'
          : 'Transactions',
      maxWidth: 1400,
      onMenuPressed: widget.onMenuPressed,
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      actions: _selectedTransactionIds.isNotEmpty
          ? [
              if (_selectedTransactionIds.length >= 2)
                HeaderIconButton(
                  icon: Icons.call_merge_rounded,
                  onPressed: _showMergeDialog,
                  semanticLabel: 'Merge selected transactions',
                ),
              HeaderIconButton(
                icon: Icons.delete_outline_rounded,
                onPressed: _confirmDeleteSelected,
                semanticLabel: 'Delete selected transactions',
              ),
              HeaderIconButton(
                icon: Icons.close_rounded,
                onPressed: () =>
                    setState(() => _selectedTransactionIds.clear()),
                semanticLabel: 'Clear selection',
              ),
            ]
          : [
              HeaderIconButton(
                icon: Icons.currency_exchange_rounded,
                onPressed: () => _showDisplayCurrencyPicker(state),
                semanticLabel: 'Choose display currency',
              ),
            ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TransactionCommandStrip(
            query: _query,
            typeLabel: _typeFilterLabel(typeFilter),
            typeValue: typeFilter,
            dateLabel: _dateFilterLabel(dateFilter),
            dateValue: dateFilter,
            accountLabel:
                accountById(state, accountFilter)?.name ?? 'All accounts',
            categoryLabel: _categoryFilterLabel(state),
            categoryValue: _categoryFilters.isEmpty
                ? (_includeUncategorizedCategory ? 'uncategorized' : 'all')
                : (_categoryFilters.length == 1 &&
                          !_includeUncategorizedCategory
                      ? _categoryFilters.first
                      : null),
            categoryOptions: [
              const GlassDropdownOption('all', 'All categories'),
              const GlassDropdownOption(
                'uncategorized',
                'Uncategorized',
                icon: Icons.label_off_outlined,
              ),
              for (final cat in state.categories.where((c) => !c.isArchived))
                GlassDropdownOption(cat.id, cat.name, icon: categoryIcon(cat)),
            ],
            statusLabel: _statusFilterLabel(statusFilter),
            statusValue: statusFilter,
            tagLabel: tagFilter == 'all' ? 'All tags' : tagFilter,
            tagValue: tagFilter,
            tagActive: tagFilter != 'all',
            tagOptions: [
              const GlassDropdownOption('all', 'All tags'),
              for (final tag in allLedgerTags)
                GlassDropdownOption(
                  tag,
                  tag,
                  icon: Icons.label_outline_rounded,
                ),
            ],
            onTagSelected: (value) =>
                ref.read(transactionsTagFilterProvider.notifier).state = value,
            typeActive: typeFilter != 'all',
            dateActive: dateFilter != _defaultDateFilter,
            accountActive: accountFilter != null,
            categoryActive:
                _categoryFilters.isNotEmpty || _includeUncategorizedCategory,
            statusActive: statusFilter != 'all',
            hasActiveFilters: hasActiveFilters,
            onQueryChanged: (value) => setState(() => _query = value),
            onClear: _clearFilters,
            onTypeSelected: (value) =>
                ref.read(transactionsTypeFilterProvider.notifier).state = value,
            onDateSelected: (value) =>
                ref.read(transactionsDateFilterProvider.notifier).state = value,
            onAccountTap: () => _showAccountFilter(state, accountFilter),
            onCategoryTap: () => _showCategoryFilter(state),
            onCategorySelected: (value) {
              setState(() {
                if (value == 'all') {
                  _categoryFilters.clear();
                  _includeUncategorizedCategory = false;
                } else if (value == 'uncategorized') {
                  _categoryFilters.clear();
                  _includeUncategorizedCategory = true;
                } else {
                  _categoryFilters
                    ..clear()
                    ..add(value);
                  _includeUncategorizedCategory = false;
                }
              });
            },
            onStatusSelected: (value) =>
                ref.read(transactionsStatusFilterProvider.notifier).state =
                    value,
          ),
          if (transactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Filtered Total',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (flow.income.amountMinor > 0)
                            Text(
                              '+${formatMoney(flow.income, state.preferences.locale)}',
                              style: TextStyle(
                                color: positiveTone(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (flow.income.amountMinor > 0 &&
                              flow.expense.amountMinor > 0)
                            const SizedBox(width: AppSpacing.md),
                          if (flow.expense.amountMinor > 0)
                            Text(
                              '-${formatMoney(flow.expense, state.preferences.locale)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AppTopFadeMask(
              enabled: transactions.isNotEmpty,
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
                      actionIcon: hasActiveFilters
                          ? Icons.filter_alt_off_rounded
                          : Icons.add_rounded,
                      onAction: hasActiveFilters
                          ? _clearFilters
                          : () => context.push('/add'),
                    )
                  : Builder(
                      builder: (context) {
                        final stats = ref.watch(
                          _monthlyStatsProvider((
                            accountFilter: accountFilter,
                            displayCurrency: state.preferences.displayCurrency,
                            locale: state.preferences.locale.replaceAll(
                              '_',
                              '-',
                            ),
                          )),
                        );
                        final monthlyBalances = stats.monthlyBalances;
                        final monthlyFlows = stats.monthlyFlows;

                        final filteredMonthlyFlows = <String, int>{};
                        final filteredMonthlyCounts = <String, int>{};
                        final includedAccounts = accountFilter != null
                            ? {accountFilter}
                            : {
                                for (final a in state.accounts)
                                  if (!a.isArchived && a.includeInTotals) a.id,
                              };

                        final entries = <_HistoryEntry>[];
                        String? currentMonth;
                        DateTime? currentDay;
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final yesterday = today.subtract(
                          const Duration(days: 1),
                        );
                        final locale = state.preferences.locale.replaceAll(
                          '_',
                          '-',
                        );

                        final monthFormat = DateFormat('MMM yyyy', locale);
                        final dayFormat = DateFormat('EEE, d MMM', locale);

                        for (final t in transactions) {
                          final mStr = monthFormat
                              .format(t.occurredAt)
                              .toUpperCase();
                          filteredMonthlyCounts[mStr] =
                              (filteredMonthlyCounts[mStr] ?? 0) + 1;

                          if (t.status == 'scheduled' ||
                              t.status == 'paused' ||
                              t.status == 'void' ||
                              t.isExcludedFromReports) {
                            continue;
                          }

                          final sourceIncluded = includedAccounts.contains(
                            t.accountId,
                          );
                          final counterIncluded =
                              t.counterAccountId != null &&
                              includedAccounts.contains(t.counterAccountId);
                          if (!sourceIncluded && !counterIncluded) continue;

                          int flowMinor = 0;
                          if (t.type == 'transfer') {
                            if (sourceIncluded && !counterIncluded) {
                              final converted = convertMoneyForDisplay(
                                state,
                                t.amount,
                                state.preferences.displayCurrency,
                              );
                              flowMinor = -converted.amountMinor;
                            } else if (!sourceIncluded && counterIncluded) {
                              final counterAmt = t.counterAmount ?? t.amount;
                              final converted = convertMoneyForDisplay(
                                state,
                                counterAmt,
                                state.preferences.displayCurrency,
                              );
                              flowMinor = converted.amountMinor;
                            }
                          } else if (incomeTypes.contains(t.type)) {
                            if (sourceIncluded) {
                              final converted = convertMoneyForDisplay(
                                state,
                                t.amount,
                                state.preferences.displayCurrency,
                              );
                              flowMinor = converted.amountMinor;
                            }
                          } else if (expenseTypes.contains(t.type)) {
                            if (sourceIncluded) {
                              final converted = convertMoneyForDisplay(
                                state,
                                t.amount,
                                state.preferences.displayCurrency,
                              );
                              flowMinor = -converted.amountMinor;
                            }
                          }
                          filteredMonthlyFlows[mStr] =
                              (filteredMonthlyFlows[mStr] ?? 0) + flowMinor;
                        }

                        String? currentDayLabel;
                        List<TransactionRecord> currentDayTransactions = [];

                        void flushDay() {
                          if (currentDayTransactions.isNotEmpty &&
                              currentDayLabel != null) {
                            entries.add(
                              _DayGroupEntry(
                                dayLabel: currentDayLabel,
                                transactions: currentDayTransactions,
                              ),
                            );
                            currentDayTransactions = [];
                          }
                        }

                        for (final t in transactions) {
                          final monthStr = monthFormat
                              .format(t.occurredAt)
                              .toUpperCase();

                          final isNewMonth = currentMonth != monthStr;
                          if (isNewMonth) {
                            flushDay();
                            currentMonth = monthStr;

                            final int effectiveFlowMinor = hasActiveFilters
                                ? (filteredMonthlyFlows[monthStr] ?? 0)
                                : (monthlyFlows[monthStr] ?? 0);
                            final formattedFlow = formatMoney(
                              Money(
                                amountMinor: effectiveFlowMinor,
                                currency: state.preferences.displayCurrency,
                              ),
                              state.preferences.locale,
                            );
                            final flowStr =
                                (hasActiveFilters && effectiveFlowMinor > 0)
                                ? '+$formattedFlow'
                                : formattedFlow;

                            final balanceStr = hasActiveFilters
                                ? '${filteredMonthlyCounts[monthStr] ?? 0} record${(filteredMonthlyCounts[monthStr] ?? 0) == 1 ? '' : 's'}'
                                : formatMoney(
                                    Money(
                                      amountMinor:
                                          monthlyBalances[monthStr] ?? 0,
                                      currency:
                                          state.preferences.displayCurrency,
                                    ),
                                    state.preferences.locale,
                                  );

                            entries.add(
                              _MonthHeaderEntry(
                                monthStr: monthStr,
                                balanceStr: balanceStr,
                                flowStr: flowStr,
                                isFirst: entries.isEmpty,
                                isFiltered: hasActiveFilters,
                              ),
                            );
                          }

                          final occurredAt = t.occurredAt;
                          final day = DateTime(
                            occurredAt.year,
                            occurredAt.month,
                            occurredAt.day,
                          );
                          if (isNewMonth || currentDay != day) {
                            flushDay();
                            currentDay = day;
                            if (day == today) {
                              currentDayLabel = 'Today';
                            } else if (day == yesterday) {
                              currentDayLabel = 'Yesterday';
                            } else {
                              currentDayLabel = dayFormat.format(day);
                            }
                          }

                          currentDayTransactions.add(t);
                        }
                        flushDay();

                        return ListView.builder(
                          padding: EdgeInsets.only(
                            bottom:
                                AppSizes.bottomBarClearance +
                                MediaQuery.paddingOf(context).bottom,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final item = entries[index];
                            if (item is _MonthHeaderEntry) {
                              return Padding(
                                padding: EdgeInsets.fromLTRB(
                                  0,
                                  item.isFirst ? 0 : AppSpacing.md,
                                  0,
                                  AppSpacing.sm,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      item.monthStr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: PrivacyText(
                                            item.isFiltered
                                                ? item.balanceStr
                                                : 'Balance ${item.balanceStr}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                        PrivacyText(
                                          '∑ ${item.flowStr}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }

                            final dayGroup = item as _DayGroupEntry;
                            return RepaintBoundary(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: AppGroupedSection(
                                  header: dayGroup.dayLabel,
                                  children: [
                                    for (final entry
                                        in dayGroup.transactions.indexed) ...[
                                      if (entry.$1 > 0) const GlassDivider(),
                                      TransactionRow(
                                        state: state,
                                        transaction: entry.$2,
                                        selectedAccountId: accountFilter,
                                        showSurface: false,
                                        selected: _selectedTransactionIds
                                            .contains(entry.$2.id),
                                        onLongPress: () {
                                          setState(() {
                                            if (_selectedTransactionIds
                                                .contains(entry.$2.id)) {
                                              _selectedTransactionIds.remove(
                                                entry.$2.id,
                                              );
                                            } else {
                                              _selectedTransactionIds.add(
                                                entry.$2.id,
                                              );
                                            }
                                          });
                                        },
                                        onTap: () {
                                          if (_selectedTransactionIds
                                              .isNotEmpty) {
                                            setState(() {
                                              if (_selectedTransactionIds
                                                  .contains(entry.$2.id)) {
                                                _selectedTransactionIds.remove(
                                                  entry.$2.id,
                                                );
                                              } else {
                                                _selectedTransactionIds.add(
                                                  entry.$2.id,
                                                );
                                              }
                                            });
                                          } else {
                                            context.push(
                                              '/transaction/${entry.$2.id}',
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters(String? accountFilter) {
    final typeFilter = ref.read(transactionsTypeFilterProvider);
    final dateFilter = ref.read(transactionsDateFilterProvider);
    final statusFilter = ref.read(transactionsStatusFilterProvider);
    final tagFilter = ref.read(transactionsTagFilterProvider);
    return _query.trim().isNotEmpty ||
        typeFilter != 'all' ||
        dateFilter != _defaultDateFilter ||
        statusFilter != 'all' ||
        tagFilter != 'all' ||
        accountFilter != null ||
        _categoryFilters.isNotEmpty ||
        ref.read(transactionsCategoryFilterProvider).isNotEmpty ||
        _includeUncategorizedCategory;
  }

  void _clearFilters() {
    ref.read(transactionsCategoryFilterProvider.notifier).state = {};
    setState(() {
      _query = '';
      _categoryFilters.clear();
      _includeUncategorizedCategory = false;
    });
    ref.read(transactionsTypeFilterProvider.notifier).state = 'all';
    ref.read(transactionsDateFilterProvider.notifier).state =
        _defaultDateFilter;
    ref.read(transactionsStatusFilterProvider.notifier).state = 'all';
    ref.read(transactionsTagFilterProvider.notifier).state = 'all';
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
                '${accountTypeLabel(account.type)} · ${maskMoneyIfPrivate(state, formatMoney(accountBalanceFromMap(balances, account), state.preferences.locale))}',
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
                      AppSwitchListTile(
                        value: includeUncategorized,
                        onChanged: (value) =>
                            setDialogState(() => includeUncategorized = value),
                        title: const Text('Uncategorized'),
                        subtitle: const Text('Records without a category'),
                        secondary: const Icon(Icons.label_off_outlined),
                      ),
                      for (final category in categories)
                        AppSwitchListTile(
                          value: selected.contains(category.id),
                          onChanged: (value) => setDialogState(() {
                            if (value) {
                              selected.add(category.id);
                            } else {
                              selected.remove(category.id);
                            }
                          }),
                          title: Text(category.name),
                          subtitle: Text(categoryPath(state, category)),
                          secondary: Icon(
                            categoryIcon(category),
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

  Future<void> _confirmDeleteSelected() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete transactions?',
      message:
          'Are you sure you want to delete ${_selectedTransactionIds.length} transaction${_selectedTransactionIds.length == 1 ? '' : 's'}? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      final ids = Set<String>.from(_selectedTransactionIds);
      setState(() {
        _selectedTransactionIds.clear();
      });
      await ref.read(ledgerProvider.notifier).deleteTransactions(ids);
    }
  }

  Future<void> _showMergeDialog() async {
    final state = ref.read(ledgerProvider);
    final selectedList = state.transactions
        .where((t) => _selectedTransactionIds.contains(t.id))
        .toList();

    if (selectedList.length < 2) return;

    // Check constraint: All must belong to the same account
    final firstAccountId = selectedList.first.accountId;
    final allSameAccount = selectedList.every(
      (t) => t.accountId == firstAccountId,
    );
    if (!allSameAccount) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot merge'),
          content: const Text(
            'All selected transactions must belong to the same account to be merged.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final account = accountById(state, firstAccountId);
    final allSameCategory = selectedList.every(
      (t) => t.categoryId == selectedList.first.categoryId,
    );
    final initialCategoryId = allSameCategory
        ? selectedList.first.categoryId
        : null;

    final totalAmountMinor = selectedList.fold<int>(
      0,
      (sum, t) => sum + t.amount.amountMinor,
    );
    final totalMoney = Money(
      amountMinor: totalAmountMinor,
      currency: selectedList.first.amount.currency,
    );

    await showAppSheet<void>(
      context: context,
      builder: (sheetContext) => _MergeTransactionsSheet(
        state: state,
        selectedTransactions: selectedList,
        account: account,
        totalMoney: totalMoney,
        initialCategoryId: initialCategoryId,
        allSameCategory: allSameCategory,
        onMerge: ({String? categoryId, String? name, String? notes}) async {
          final ids = Set<String>.from(_selectedTransactionIds);
          setState(() {
            _selectedTransactionIds.clear();
          });
          try {
            await ref
                .read(ledgerProvider.notifier)
                .mergeTransactions(
                  transactionIds: ids,
                  categoryId: categoryId,
                  name: name,
                  notes: notes,
                );
            if (mounted) {
              showAppSnackBar(
                context,
                'Merged ${ids.length} transactions into one (${formatMoney(totalMoney, state.preferences.locale)}).',
              );
            }
          } catch (e) {
            if (mounted) {
              showAppSnackBar(context, 'Failed to merge transactions: $e');
            }
          }
        },
      ),
    );
  }
}

class _TransactionFilterState {
  _TransactionFilterState({
    required String query,
    required this.typeFilter,
    required this.dateFilter,
    required this.statusFilter,
    required Set<String> categoryFilterIds,
    required this.includeUncategorizedCategory,
    required this.accountFilter,
    this.tagFilter = 'all',
  }) : query = query.trim().toLowerCase(),
       categoryFilterIds = (categoryFilterIds.toList()..sort()).join('|');

  final String query;
  final String typeFilter;
  final String dateFilter;
  final String statusFilter;
  final String categoryFilterIds;
  final bool includeUncategorizedCategory;
  final String? accountFilter;
  final String tagFilter;

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
        other.statusFilter == statusFilter &&
        other.categoryFilterIds == categoryFilterIds &&
        other.includeUncategorizedCategory == includeUncategorizedCategory &&
        other.accountFilter == accountFilter &&
        other.tagFilter == tagFilter;
  }

  @override
  int get hashCode => Object.hash(
    query,
    typeFilter,
    dateFilter,
    statusFilter,
    categoryFilterIds,
    includeUncategorizedCategory,
    accountFilter,
    tagFilter,
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

bool _matchesDateFilter(DateTime date, String dateFilter, {DateTime? now}) {
  if (dateFilter == 'all') return true;
  final current = now ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  return switch (dateFilter) {
    'today' =>
      date.year == current.year &&
          date.month == current.month &&
          date.day == current.day,
    'this_week' => () {
      final diff = current.weekday - 1; // 0 for Monday
      final start = DateTime(
        current.year,
        current.month,
        current.day,
      ).subtract(Duration(days: diff));
      final end = start.add(const Duration(days: 7));
      return !date.isBefore(start) && date.isBefore(end);
    }(),
    'this_month' => date.year == current.year && date.month == current.month,
    'last_month' => () {
      final prevMonth = DateTime(current.year, current.month - 1);
      return date.year == prevMonth.year && date.month == prevMonth.month;
    }(),
    'last_30_days' => !day.isBefore(
      DateTime(
        current.year,
        current.month,
        current.day,
      ).subtract(const Duration(days: 30)),
    ),
    'this_year' => date.year == current.year,
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
    _ => 'All types',
  };
}

String _dateFilterLabel(String value) {
  return switch (value) {
    'today' => 'Today',
    'this_week' => 'This week',
    'this_month' => 'This month',
    'last_month' => 'Last month',
    'last_30_days' => 'Last 30 days',
    'this_year' => 'This year',
    _ => 'All time',
  };
}

String _statusFilterLabel(String value) {
  return switch (value) {
    'cleared' => 'Cleared',
    'pending' => 'Pending',
    'void' => 'Skipped / Void',
    _ => 'All statuses',
  };
}

class _MergeTransactionsSheet extends StatefulWidget {
  const _MergeTransactionsSheet({
    required this.state,
    required this.selectedTransactions,
    required this.account,
    required this.totalMoney,
    required this.initialCategoryId,
    required this.allSameCategory,
    required this.onMerge,
  });

  final LedgerState state;
  final List<TransactionRecord> selectedTransactions;
  final Account? account;
  final Money totalMoney;
  final String? initialCategoryId;
  final bool allSameCategory;
  final void Function({String? categoryId, String? name, String? notes})
  onMerge;

  @override
  State<_MergeTransactionsSheet> createState() =>
      _MergeTransactionsSheetState();
}

class _MergeTransactionsSheetState extends State<_MergeTransactionsSheet> {
  late String? _selectedCategoryId;
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;

    final defaultName =
        widget.selectedTransactions
            .where((t) => t.name != null && t.name!.trim().isNotEmpty)
            .firstOrNull
            ?.name ??
        'Merged transaction';
    _nameController = TextEditingController(text: defaultName);

    final defaultNotes =
        'Merged from ${widget.selectedTransactions.length} transactions:\n${widget.selectedTransactions.map((t) => '• ${t.name ?? "Transaction"}: ${t.amount.amountMinor / 100} (${t.occurredAt.toLocal().toString().split(" ").first})').join('\n')}';
    _notesController = TextEditingController(text: defaultNotes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = categoryById(widget.state, _selectedCategoryId);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return AppSheetSurface(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.call_merge_rounded,
                      color: scheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Merge transactions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Combine ${widget.selectedTransactions.length} transactions into one',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    // Summary card
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Sum total amount',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  formatMoney(
                                    widget.totalMoney,
                                    widget.state.preferences.locale,
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Account',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  widget.account?.name ?? 'Unknown account',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Category selection
                    Text(
                      'Category',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (widget.allSameCategory && _selectedCategoryId != null)
                      Text(
                        'All selected transactions share this category. Tap below if you want to change it.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Text(
                        'Transactions have different or missing categories. Please choose one for the merged transaction:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      onTap: () async {
                        final picked = await showCategoryHierarchyPicker(
                          context: context,
                          state: widget.state,
                          selectedCategoryId: _selectedCategoryId,
                          title: 'Choose category for merged',
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedCategoryId = picked.isEmpty
                                ? null
                                : picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(
                            color:
                                _selectedCategoryId == null &&
                                    !widget.allSameCategory
                                ? scheme.error.withValues(alpha: 0.47)
                                : scheme.outlineVariant.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              category != null
                                  ? categoryIcon(category)
                                  : Icons.category_outlined,
                              color: scheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                category?.name ??
                                    'No category selected (Tap to choose)',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: category != null
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Name field
                    Text(
                      'Transaction name',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Swiggy order batch',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Items to be merged preview
                    Text(
                      'Transactions being merged (${widget.selectedTransactions.length})',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          children: [
                            for (final t in widget.selectedTransactions) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.receipt_long_outlined,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        t.name ?? 'Transaction',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      formatMoney(
                                        t.amount,
                                        widget.state.preferences.locale,
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Notes
                    Text(
                      'Notes',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        contentPadding: const EdgeInsets.all(AppSpacing.md),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Action buttons
                    FilledButton.icon(
                      style: AppButtonStyles.cta,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onMerge(
                          categoryId: _selectedCategoryId,
                          name: _nameController.text.trim(),
                          notes: _notesController.text.trim(),
                        );
                      },
                      icon: const Icon(Icons.call_merge_rounded),
                      label: Text(
                        'Merge into ${formatMoney(widget.totalMoney, widget.state.preferences.locale)}',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

sealed class _HistoryEntry {}

class _MonthHeaderEntry extends _HistoryEntry {
  _MonthHeaderEntry({
    required this.monthStr,
    required this.balanceStr,
    required this.flowStr,
    required this.isFirst,
    this.isFiltered = false,
  });

  final String monthStr;
  final String balanceStr;
  final String flowStr;
  final bool isFirst;
  final bool isFiltered;
}

class _DayGroupEntry extends _HistoryEntry {
  _DayGroupEntry({required this.dayLabel, required this.transactions});

  final String dayLabel;
  final List<TransactionRecord> transactions;
}
