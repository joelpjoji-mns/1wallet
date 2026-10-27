import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../common/full_screen_picker.dart';
import '../transactions/transaction_row.dart';
import 'calendar_forecast.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({required this.onMenuPressed, super.key});

  final VoidCallback onMenuPressed;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  var _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _accountFilter;
  String? _categoryFilter;
  Object? _cachedKey;
  List<DateTime>? _cachedDays;
  Map<String, List<TransactionRecord>>? _cachedSummaries;
  int _cachedIncome = 0;
  int _cachedExpense = 0;
  int _cachedNet = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final key = (state, _visibleMonth, _accountFilter, _categoryFilter);

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

    final locale = state.preferences.locale.replaceAll('_', '-');
    final selectedAccount = accountById(state, _accountFilter);
    final selectedCategory = categoryById(state, _categoryFilter);
    final bottomDockClearance =
        AppSizes.bottomBarClearance + MediaQuery.paddingOf(context).bottom;

    return AppScreen(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(
                  () => _visibleMonth = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month - 1,
                  ),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      DateFormat.yMMMM(locale).format(_visibleMonth),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      '${selectedCategory?.name ?? 'All categories'} · ${selectedAccount?.name ?? 'All accounts'}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(
                  () => _visibleMonth = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month + 1,
                  ),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SummaryPill(
                  label: 'Net',
                  money: convertMoneyForDisplay(
                    state,
                    Money(
                      amountMinor: net,
                      currency: state.preferences.baseCurrency,
                    ),
                  ),
                  tone: net >= 0 ? MetricTone.positive : MetricTone.danger,
                  locale: state.preferences.locale,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
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
              const SizedBox(width: AppSpacing.sm),
              Expanded(
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
          ),
          const SizedBox(height: AppSpacing.xs),

          Row(
            children: [
              Expanded(
                child: _CalendarFilterCard(
                  icon: Icons.category_outlined,
                  title: 'Category',
                  value: selectedCategory?.name ?? 'All categories',
                  subtitle: 'Filter by category',
                  active: _categoryFilter != null,
                  onTap: () => _showCategoryFilter(state),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CalendarFilterCard(
                  icon: Icons.account_balance_outlined,
                  title: 'Account',
                  value: selectedAccount?.name ?? 'All accounts',
                  subtitle: 'Filter by account',
                  active: _accountFilter != null,
                  onTap: () => _showAccountFilter(state),
                ),
              ),
            ],
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
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
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
                                return _DayCell(
                                  date: day,
                                  inMonth: day.month == _visibleMonth.month,
                                  records: records,
                                  state: state,
                                  onTap: () =>
                                      _showDay(context, state, day, records),
                                );
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
        ],
      ),
    );
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
      if (_categoryFilter != null && f.categoryId != _categoryFilter) {
        continue;
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
      if (_categoryFilter != null &&
          transaction.categoryId != _categoryFilter) {
        return false;
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

    // For past months, undo the effect of any transactions that happened after `through`
    if (through.isBefore(DateTime(now.year, now.month, now.day))) {
      // Ensure through covers the entire day of the month end by setting it to 23:59:59
      final endOfDayThrough = DateTime(
        through.year,
        through.month,
        through.day,
        23,
        59,
        59,
      );
      for (final tx in state.transactions) {
        if (tx.status != 'posted' && tx.status != 'cleared') continue;
        if (tx.occurredAt.isAfter(endOfDayThrough)) {
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
    final gridStart = first.subtract(Duration(days: startOffset));

    final nextMonth = DateTime(month.year, month.month + 1);
    final monthEnd = nextMonth.subtract(const Duration(days: 1));
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
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Calendar category',
      searchHint: 'Search categories',
      selectedValue: _categoryFilter ?? '__all__',
      options: [
        const PickerOption(
          value: '__all__',
          title: 'All categories',
          subtitle: 'Include every category in the calendar',
          icon: Icons.all_inclusive_rounded,
        ),
        for (final category in state.categories.where(
          (category) => !category.isArchived,
        ))
          PickerOption(
            value: category.id,
            title: category.name,
            subtitle: categoryPath(state, category),
            icon: categoryIcon(category),
            iconColor: categoryColor(category, context),
          ),
      ],
    );
    if (next == null) return;
    setState(() => _categoryFilter = next == '__all__' ? null : next);
  }

  void _showDay(
    BuildContext context,
    LedgerState state,
    DateTime date,
    List<TransactionRecord> records,
  ) {
    // Use end-of-day so the tapped day's own transactions are included in
    // its running balance instead of being treated as "after" it.
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    final balanceBaseMinor = _projectedNetThroughMonthEnd(
      state,
      through: endOfDay,
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
      return AppPanel(
        glass: true,
        radius: AppRadii.lg,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat.yMMMMd(
                      state.preferences.locale.replaceAll('_', '-'),
                    ).format(date),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                PrivacyText(
                  balanceDisplay,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: balanceMinor < 0 ? scheme.error : scheme.primary,
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(modalContext).pop(),
                  ),
                ],
              ],
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
      );
    }

    if (isDesktop) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          // The day panel draws its own (glass/opaque) surface.
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
    return AppPanel(
      glass: true,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: active
            ? BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.39),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: scheme.primary, width: 0.8),
              )
            : null,
        child: Row(
          children: [
            IconBubble(
              icon: icon,
              compact: true,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        decoration: BoxDecoration(
          color: isToday ? scheme.primaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: isToday ? scheme.primary : scheme.outlineVariant,
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${date.day}',
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface.withAlphaFactor(
                        inMonth ? 1.0 : 0.42,
                      ),
                    ),
                  ),
                ),
                if (records.isNotEmpty)
                  Icon(
                    Icons.circle_rounded,
                    size: 6,
                    color: scheme.primary.withAlphaFactor(inMonth ? 1.0 : 0.42),
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
    );
  }
}
