import 'package:flutter/material.dart';
import '../../auth/auth_controller.dart';
import '../onboarding/discovery_controller.dart';
import '../onboarding/feature_discovery_guide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../common/category_tree_picker.dart';
import '../common/full_screen_picker.dart';
import '../transactions/transaction_row.dart';
import 'calendar_forecast.dart';

final calendarVisibleMonthProvider = StateProvider<DateTime?>((ref) => null);

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({required this.onMenuPressed, super.key});

  final VoidCallback onMenuPressed;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  var _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _accountFilter;
  final _categoryFilters = <String>{};
  bool _includeUncategorizedCategory = false;
  Object? _cachedKey;
  List<DateTime>? _cachedDays;
  Map<String, List<TransactionRecord>>? _cachedSummaries;
  int _cachedIncome = 0;
  int _cachedExpense = 0;
  int _cachedNet = 0;

  @override
  void initState() {
    super.initState();
    final externalMonth = ref.read(calendarVisibleMonthProvider);
    if (externalMonth != null) {
      _visibleMonth = externalMonth;
    }
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

  @override
  Widget build(BuildContext context) {
    ref.listen<DateTime?>(calendarVisibleMonthProvider, (_, next) {
      if (next != null && next != _visibleMonth) {
        setState(() => _visibleMonth = next);
      }
    });
    final state = ref.watch(ledgerProvider);
    final key = (
      state,
      _visibleMonth,
      _accountFilter,
      _categoryFilters.join(','),
      _includeUncategorizedCategory,
    );

    if (_cachedKey != key || _cachedDays == null || _cachedSummaries == null) {
      final days = _calendarDays(_visibleMonth);
      final horizonStart = DateTime(_visibleMonth.year, _visibleMonth.month);
      final horizonEnd = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + 1,
        0,
        23,
        59,
        59,
      );
      final forecasts = forecastRecurringTransactions(
        state,
        horizonStart,
        horizonEnd,
      );
      final summaries = _summariesByDay(state, forecasts);
      final monthTransactions = days
          .where((day) => day.month == _visibleMonth.month)
          .expand((day) => summaries[_key(day)] ?? <TransactionRecord>[])
          .toList();
      final baseCurrency = state.preferences.baseCurrency;
      final income = monthTransactions
          .where((tx) => incomeTypes.contains(tx.type))
          .fold<int>(0, (sum, tx) {
            final converted = convertMoneyForDisplay(
              state,
              tx.amount,
              baseCurrency,
            );
            return sum + converted.amountMinor;
          });
      final expense = monthTransactions
          .where((tx) => expenseTypes.contains(tx.type))
          .fold<int>(0, (sum, tx) {
            final converted = convertMoneyForDisplay(
              state,
              tx.amount,
              baseCurrency,
            );
            return sum + converted.amountMinor;
          });

      final net = _projectedNetThroughMonthEnd(
        state,
        through: DateTime(_visibleMonth.year, _visibleMonth.month + 1),
      );

      _cachedKey = key;
      _cachedDays = days;
      _cachedSummaries = summaries;
      _cachedIncome = income;
      _cachedExpense = expense;
      _cachedNet = net;
    }

    final days = _cachedDays!;
    final summaries = _cachedSummaries!;
    final income = _cachedIncome;
    final expense = _cachedExpense;
    final net = _cachedNet;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = state.preferences.locale.replaceAll('_', '-');
    final selectedAccount = accountById(state, _accountFilter);
    final hasCategoryFilter =
        _categoryFilters.isNotEmpty || _includeUncategorizedCategory;
    final bottomDockClearance =
        AppSizes.bottomBarClearance + MediaQuery.paddingOf(context).bottom;

    final screen = AppScreen(
      maxWidth: 1400,
      title: 'Calendar',
      scrollable: false,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        bottomDockClearance,
      ),
      onMenuPressed: widget.onMenuPressed,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final heading = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.yMMMM(locale).format(_visibleMonth),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: AppSpacing.xxxs),
                        Text(
                          '${_categoryFilterLabel(state)} · ${selectedAccount?.name ?? 'All accounts'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    );
                    final controls = DiscoveryGuideAnchor(
                      id: 'calendar-month-controls',
                      child: g1455.GlassButtonGroup(
                        finish: ref.watch(toolbarsGlassFinishProvider),
                        items: [
                          g1455.GlassToolbarItem(
                            icon: Tooltip(
                              message: 'Previous month',
                              excludeFromSemantics: true,
                              child: Icon(
                                Icons.chevron_left_rounded,
                                size: 20,
                                color: scheme.onSurface,
                              ),
                            ),
                            label: 'Previous month',
                            onPressed: () => setState(
                              () => _visibleMonth = DateTime(
                                _visibleMonth.year,
                                _visibleMonth.month - 1,
                              ),
                            ),
                          ),
                          g1455.GlassToolbarItem(
                            icon: Tooltip(
                              message: 'Current month',
                              excludeFromSemantics: true,
                              child: Icon(
                                Icons.today_rounded,
                                size: 18,
                                color: scheme.onSurface,
                              ),
                            ),
                            label: 'Current month',
                            onPressed: () => setState(
                              () => _visibleMonth = DateTime(
                                DateTime.now().year,
                                DateTime.now().month,
                              ),
                            ),
                          ),
                          g1455.GlassToolbarItem(
                            icon: Tooltip(
                              message: 'Next month',
                              excludeFromSemantics: true,
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: scheme.onSurface,
                              ),
                            ),
                            label: 'Next month',
                            onPressed: () {
                              final next = DateTime(
                                _visibleMonth.year,
                                _visibleMonth.month + 1,
                              );
                              setState(() => _visibleMonth = next);
                              ref.read(calendarVisibleMonthProvider.notifier).state = next;
                            },
                          ),
                        ],
                      ),
                    );
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    if (constraints.maxWidth < 300 * textScale) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          const SizedBox(height: AppSpacing.xs),
                          controls,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: AppSpacing.xs),
                        controls,
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final stacked = constraints.maxWidth < 280 * textScale;
                    final width = stacked
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 2 * AppSpacing.sm) / 3;
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        SizedBox(
                          width: width,
                          child: DiscoveryGuideAnchor(
                            id: 'calendar-net',
                            child: Tooltip(
                              message:
                                  'Month-end balance for the selected accounts. '
                                  'Future balances include recurring forecasts; '
                                  'category filters affect income and expense only.',
                              child: SummaryPill(
                                label: 'Balance',
                                money: convertMoneyForDisplay(
                                  state,
                                  Money(
                                    amountMinor: net,
                                    currency: state.preferences.baseCurrency,
                                  ),
                                ),
                                tone: net >= 0
                                    ? MetricTone.positive
                                    : MetricTone.danger,
                                locale: state.preferences.locale,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: SummaryPill(
                            label: 'Income',
                            money: convertMoneyForDisplay(
                              state,
                              Money(
                                amountMinor: income,
                                currency: state.preferences.baseCurrency,
                              ),
                            ),
                            tone: MetricTone.positive,
                            locale: state.preferences.locale,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: SummaryPill(
                            label: 'Expense',
                            money: convertMoneyForDisplay(
                              state,
                              Money(
                                amountMinor: expense,
                                currency: state.preferences.baseCurrency,
                              ),
                            ),
                            tone: MetricTone.danger,
                            locale: state.preferences.locale,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xs),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final categoryCard = _CalendarFilterCard(
                      icon: Icons.category_outlined,
                      title: 'Category',
                      value: _categoryFilterLabel(state),
                      subtitle: 'Filter by category',
                      active: hasCategoryFilter,
                      onTap: () => _showCategoryFilter(state),
                    );
                    final accountCard = _CalendarFilterCard(
                      icon: Icons.account_balance_outlined,
                      title: 'Account',
                      value: selectedAccount?.name ?? 'All accounts',
                      subtitle: 'Filter by account',
                      active: _accountFilter != null,
                      onTap: () => _showAccountFilter(state),
                    );
                    return Row(
                      children: [
                        Expanded(child: categoryCard),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: accountCard),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    for (final day in [
                      'Sun',
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                    ])
                      Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox(
              height:
                  (days.length ~/ 7) * 48 +
                  (days.length ~/ 7 - 1) * AppSpacing.xxs,
              child: Column(
                children: [
                  for (var w = 0; w < days.length ~/ 7; w++) ...[
                    if (w > 0) const SizedBox(height: AppSpacing.xxs),
                    Expanded(
                      child: Row(
                        children: [
                          for (var d = 0; d < 7; d++) ...[
                            if (d > 0) const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final day = days[w * 7 + d];
                                  final records =
                                      summaries[_key(day)] ??
                                      const <TransactionRecord>[];
                                  final cell = _DayCell(
                                    date: day,
                                    inMonth: day.month == _visibleMonth.month,
                                    records: records,
                                    state: state,
                                    onTap: () =>
                                        _showDay(context, state, day, records),
                                  );
                                  final now = DateTime.now();
                                  final targetDay =
                                      now.year == _visibleMonth.year &&
                                          now.month == _visibleMonth.month
                                      ? now.day
                                      : 1;
                                  return day.month == _visibleMonth.month &&
                                          day.day == targetDay
                                      ? DiscoveryGuideAnchor(
                                          id: 'calendar-day',
                                          child: cell,
                                        )
                                      : cell;
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(
              height: AppSizes.islandActionSize + AppSizes.bottomBarGap,
            ),
          ),
        ],
      ),
    );
    return FeatureDiscoverySurface(feature: 'calendar-days', child: screen);
  }

  Map<String, List<TransactionRecord>> _summariesByDay(
    LedgerState state,
    List<TransactionRecord> forecasts,
  ) {
    final result = <String, List<TransactionRecord>>{};
    for (final transaction in _filteredTransactions(state)) {
      if (transaction.status == 'void' || transaction.status == 'paused') {
        continue;
      }
      if (transaction.status == 'scheduled' &&
          transaction.source == 'recurring') {
        continue;
      }

      result
          .putIfAbsent(_key(transaction.occurredAt), () => [])
          .add(transaction);
    }
    for (final f in forecasts) {
      if (_accountFilter != null &&
          f.accountId != _accountFilter &&
          f.counterAccountId != _accountFilter) {
        continue;
      }
      if (_categoryFilters.isNotEmpty || _includeUncategorizedCategory) {
        final catId = f.categoryId;
        final match =
            (catId == null && _includeUncategorizedCategory) ||
            (catId != null && _categoryFilters.contains(catId));
        if (!match) continue;
      }
      result.putIfAbsent(_key(f.occurredAt), () => []).add(f);
    }
    return result;
  }

  Iterable<TransactionRecord> _filteredTransactions(LedgerState state) {
    return state.transactions.where((transaction) {
      if (_accountFilter != null &&
          transaction.accountId != _accountFilter &&
          transaction.counterAccountId != _accountFilter) {
        return false;
      }
      if (_categoryFilters.isNotEmpty || _includeUncategorizedCategory) {
        final catId = transaction.categoryId;
        final match =
            (catId == null && _includeUncategorizedCategory) ||
            (catId != null && _categoryFilters.contains(catId));
        if (!match) return false;
      }
      if (isHiddenInterest(state, transaction)) {
        return false;
      }
      return true;
    });
  }

  int _projectedNetThroughMonthEnd(
    LedgerState state, {
    required DateTime through,
  }) {
    final selectedAccountIds = _selectedCalendarAccountIds(state);
    var balanceMinor = 0;

    for (final account in state.accounts) {
      if (!selectedAccountIds.contains(account.id)) continue;
      final balance = convertMoneyForDisplay(
        state,
        accountBalance(state, account),
        state.preferences.baseCurrency,
      );
      balanceMinor += balance.amountMinor;
    }

    final now = DateTime.now();

    // `through` is the exclusive local-midnight boundary after the target day.
    if (!through.isAfter(now)) {
      for (final tx in state.transactions) {
        if (tx.status == 'scheduled' ||
            tx.status == 'paused' ||
            tx.status == 'void' ||
            tx.status == 'finished') {
          continue;
        }
        if (!tx.occurredAt.isBefore(through)) {
          if (selectedAccountIds.contains(tx.accountId)) {
            final delta = convertMoneyForDisplay(
              state,
              Money(amountMinor: sourceDelta(tx), currency: tx.amount.currency),
              state.preferences.baseCurrency,
            );
            balanceMinor -= delta.amountMinor;
          }
          if (tx.counterAccountId != null &&
              selectedAccountIds.contains(tx.counterAccountId)) {
            final delta = convertMoneyForDisplay(
              state,
              Money(
                amountMinor: counterDelta(tx),
                currency: tx.counterAmount?.currency ?? tx.amount.currency,
              ),
              state.preferences.baseCurrency,
            );
            balanceMinor -= delta.amountMinor;
          }
        }
      }
      return balanceMinor;
    }

    final allForecasts = forecastRecurringTransactions(state, now, through);

    for (final forecast in allForecasts) {
      if (forecast.occurredAt.isBefore(now) ||
          !forecast.occurredAt.isBefore(through)) {
        continue;
      }

      if (selectedAccountIds.contains(forecast.accountId)) {
        final delta = convertMoneyForDisplay(
          state,
          Money(
            amountMinor: sourceDelta(forecast),
            currency: forecast.amount.currency,
          ),
          state.preferences.baseCurrency,
        );
        balanceMinor += delta.amountMinor;
      }

      if (forecast.counterAccountId != null &&
          selectedAccountIds.contains(forecast.counterAccountId)) {
        final delta = convertMoneyForDisplay(
          state,
          Money(
            amountMinor: counterDelta(forecast),
            currency:
                forecast.counterAmount?.currency ?? forecast.amount.currency,
          ),
          state.preferences.baseCurrency,
        );
        balanceMinor += delta.amountMinor;
      }
    }

    return balanceMinor;
  }

  Set<String> _selectedCalendarAccountIds(LedgerState state) {
    if (_accountFilter != null) return {_accountFilter!};
    return state.accounts
        .where((account) => !account.isArchived && account.includeInReports)
        .map((account) => account.id)
        .toSet();
  }

  List<DateTime> _calendarDays(DateTime month) {
    final first = DateTime(month.year, month.month);
    final startOffset = first.weekday % 7; // Sunday = 0
    final gridStart = DateTime(
      first.year,
      first.month,
      first.day - startOffset,
    );

    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final endOffset = 6 - (monthEnd.weekday % 7);
    final dayCount = monthEnd.day + startOffset + endOffset;

    return List.generate(
      dayCount,
      (index) =>
          DateTime(gridStart.year, gridStart.month, gridStart.day + index),
    );
  }

  String _key(DateTime date) => '${date.year}-${date.month}-${date.day}';

  Future<void> _showAccountFilter(LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Calendar account',
      searchHint: 'Search accounts',
      selectedValue: _accountFilter ?? '__all__',
      options: [
        const PickerOption(
          value: '__all__',
          title: 'All accounts',
          subtitle: 'Include every account in the calendar',
          icon: Icons.all_inclusive_rounded,
        ),
        for (final account in state.accounts.where(
          (account) => !account.isArchived,
        ))
          PickerOption(
            value: account.id,
            title: account.name,
            subtitle:
                '${accountTypeLabel(account.type)} · ${maskMoneyIfPrivate(state, formatMoney(accountBalance(state, account), state.preferences.locale))}',
            icon: accountIcon(account),
            iconColor: accountDisplayColor(account),
            searchText:
                '${account.institution ?? ''} ${account.groupName ?? ''}',
          ),
      ],
    );
    if (next == null) return;
    setState(() => _accountFilter = next == '__all__' ? null : next);
  }

  Future<void> _showCategoryFilter(LedgerState state) async {
    final result = await showCategoryTreeMultiSelectPicker(
      context: context,
      state: state,
      initialSelectedCategoryIds: _categoryFilters,
      initialIncludeUncategorized: _includeUncategorizedCategory,
      title: 'Calendar categories',
    );
    if (result == null) return;

    final hasUncategorized = result.contains(categoryTreeUncategorizedKey);
    final categoryIds = result
        .where((id) => id != categoryTreeUncategorizedKey)
        .toSet();

    setState(() {
      _categoryFilters
        ..clear()
        ..addAll(categoryIds);
      _includeUncategorizedCategory = hasUncategorized;
    });
  }

  Future<void> _showDay(
    BuildContext context,
    LedgerState state,
    DateTime date,
    List<TransactionRecord> records,
  ) async {
    final owner = ref.read(authControllerProvider).ownerId;
    if (owner != null) {
      final progress = ref.read(discoveryControllerProvider(owner));
      if (progress.requestedHint == 'calendar-days' &&
          progress.guideActive &&
          progress.guideStep == 0) {
        try {
          await ref
              .read(discoveryControllerProvider(owner).notifier)
              .setGuideStep(1);
        } catch (error, stack) {
          debugPrint('Could not update calendar guide: $error');
          debugPrintStack(stackTrace: stack);
          if (context.mounted) {
            showAppSnackBar(context, 'Could not save guide progress.');
          }
        }
        if (!mounted || !context.mounted) return;
      }
    }
    if (!mounted || !context.mounted) return;
    final nextDay = DateTime(date.year, date.month, date.day + 1);
    final balanceBaseMinor = _projectedNetThroughMonthEnd(
      state,
      through: nextDay,
    );
    final balanceDisplayMoney = convertMoneyForDisplay(
      state,
      Money(
        amountMinor: balanceBaseMinor,
        currency: state.preferences.baseCurrency,
      ),
    );
    final balanceMinor = balanceDisplayMoney.amountMinor;
    final balanceDisplay = formatMoney(
      balanceDisplayMoney,
      state.preferences.locale,
    );

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDesktop = AppResponsiveLayout.isDesktop(context);

    Widget buildCardContent(BuildContext modalContext) {
      final isDark = theme.brightness == Brightness.dark;
      final card = Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        clipBehavior: Clip.antiAlias,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: scheme.outlineVariant, width: 1.0),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DiscoveryGuideAnchor(
                  id: 'calendar-sheet',
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat.yMMMMd(
                                state.preferences.locale.replaceAll('_', '-'),
                              ).format(date),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'End-of-day balance',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            PrivacyText(
                              balanceDisplay,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: balanceMinor < 0
                                    ? scheme.error
                                    : (isDark
                                          ? scheme.primary
                                          : AppColors.positiveLight),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton.filledTonal(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(modalContext).pop(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (records.isEmpty)
                  const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No records on this day',
                    body: 'Nothing was posted or scheduled for this date.',
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: AppTopFadeMask(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: records.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final transaction = records[index];
                          return TransactionRow(
                            state: state,
                            transaction: transaction,
                            glass: false,
                            onTap: () {
                              if (transaction.status == 'forecast') {
                                final templateId =
                                    transaction.originalTransactionId;
                                if (templateId != null) {
                                  context.push('/recurring/$templateId/edit');
                                }
                              } else {
                                context.push('/transaction/${transaction.id}');
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      return FeatureDiscoverySurface(feature: 'calendar-days', child: card);
    }

    if (isDesktop) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: buildCardContent(dialogContext),
          ),
        ),
      );
    } else {
      showAppSheet<void>(
        context: context,
        maxWidth: 540,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: buildCardContent(sheetContext),
          ),
        ),
      );
    }
  }
}

class SummaryPill extends StatelessWidget {
  const SummaryPill({
    required this.label,
    required this.money,
    required this.tone,
    required this.locale,
    super.key,
  });

  final String label;
  final Money money;
  final MetricTone tone;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone.resolve(scheme, standard: scheme.onSurface);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: AppSurfaces.panel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          PrivacyText(
            formatCompactMoney(money, locale),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarFilterCard extends StatelessWidget {
  const _CalendarFilterCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 18;
    return Tooltip(
      message: '$subtitle: $value',
      excludeFromSemantics: true,
      child: AppPanel(
        glass: false,
        color: isDark ? scheme.surfaceContainer : Colors.white,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: active
                ? scheme.primaryContainer.withValues(
                    alpha: isDark ? 0.25 : 0.40,
                  )
                : (isDark ? scheme.surfaceContainer : scheme.surface),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: active
                  ? scheme.primary
                  : (isDark
                        ? scheme.outlineVariant.withValues(alpha: 0.5)
                        : scheme.outlineVariant),
              width: active ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      largeText
                          ? (title == 'Category' ? 'Cat.' : 'Acct.')
                          : title,
                      semanticsLabel: title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                largeText &&
                        (value == 'All categories' || value == 'All accounts')
                    ? 'All'
                    : value,
                semanticsLabel: value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.records,
    required this.state,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final List<TransactionRecord> records;
  final LedgerState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final baseCurrency = state.preferences.baseCurrency;
    final income = records
        .where((tx) => incomeTypes.contains(tx.type))
        .fold<int>(0, (sum, tx) {
          final converted = convertMoneyForDisplay(
            state,
            tx.amount,
            baseCurrency,
          );
          return sum + converted.amountMinor;
        });
    final expense = records
        .where((tx) => expenseTypes.contains(tx.type))
        .fold<int>(0, (sum, tx) {
          final converted = convertMoneyForDisplay(
            state,
            tx.amount,
            baseCurrency,
          );
          return sum + converted.amountMinor;
        });
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return MergeSemantics(
      child: Semantics(
        label: DateFormat.yMMMMEEEEd(
          state.preferences.locale.replaceAll('_', '-'),
        ).format(date),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: isToday
                  ? (isDark
                        ? scheme.primaryContainer.withValues(alpha: 0.55)
                        : scheme.primaryContainer.withValues(alpha: 0.70))
                  : (inMonth
                        ? (isDark
                              ? scheme.surfaceContainer.withValues(alpha: 0.70)
                              : scheme.surface)
                        : (isDark
                              ? scheme.surfaceContainer.withValues(alpha: 0.25)
                              : scheme.surfaceContainerLow)),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: isToday
                    ? (isDark
                          ? scheme.primary.withValues(alpha: 0.75)
                          : AppColors.positiveLight)
                    : (inMonth
                          ? (isDark
                                ? scheme.outlineVariant.withValues(alpha: 0.6)
                                : scheme.outlineVariant)
                          : (isDark
                                ? scheme.outlineVariant.withValues(alpha: 0.25)
                                : scheme.surfaceContainerLow)),
                width: isToday ? 1.5 : 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: ExcludeSemantics(
                        child: Text(
                          '${date.day}',
                          maxLines: 1,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? scheme.onSurface.withAlphaFactor(
                                    inMonth ? 1.0 : 0.42,
                                  )
                                : (inMonth ? scheme.onSurface : scheme.outline),
                          ),
                        ),
                      ),
                    ),
                    if (records.isNotEmpty)
                      Icon(
                        Icons.circle_rounded,
                        size: 6,
                        color: scheme.primary.withAlphaFactor(
                          inMonth ? 1.0 : 0.42,
                        ),
                      ),
                  ],
                ),
                // Day cells are fixed-size; scale the amounts down so they stay
                // whole instead of clipping or overflowing the cell.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.bottomStart,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (income > 0)
                            PrivacyText(
                              '+${formatCompactMoney(convertMoneyForDisplay(state, Money(amountMinor: income, currency: state.preferences.baseCurrency)), state.preferences.locale)}',
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: amountColor(
                                  context,
                                  income,
                                ).withAlphaFactor(inMonth ? 1.0 : 0.42),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          if (expense > 0)
                            PrivacyText(
                              '-${formatCompactMoney(convertMoneyForDisplay(state, Money(amountMinor: expense, currency: state.preferences.baseCurrency)), state.preferences.locale)}',
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: amountColor(
                                  context,
                                  -expense,
                                ).withAlphaFactor(inMonth ? 1.0 : 0.42),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
