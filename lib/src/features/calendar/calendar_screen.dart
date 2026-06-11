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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
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
    final income = monthTransactions
        .where((tx) => incomeTypes.contains(tx.type))
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);
    final expense = monthTransactions
        .where((tx) => expenseTypes.contains(tx.type))
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);

    final net = _projectedNetThroughMonthEnd(
      state,
      through: DateTime(_visibleMonth.year, _visibleMonth.month + 1),
    );
    final plannedCount = monthTransactions
        .where((tx) => tx.status == 'forecast')
        .length;

    final locale = state.preferences.locale.replaceAll('_', '-');
    final selectedAccount = accountById(state, _accountFilter);
    final selectedCategory = categoryById(state, _categoryFilter);

    return AppScreen(
      title: 'Calendar',
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        115.0,
      ),
      onMenuPressed: widget.onMenuPressed,
      actions: [
        HeaderIconButton(
          icon: Icons.add_rounded,
          onPressed: () => context.push('/add'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
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
                    const SizedBox(height: 2),
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
                  money: Money(
                    amountMinor: net,
                    currency: state.preferences.baseCurrency,
                  ),
                  tone: net >= 0 ? MetricTone.positive : MetricTone.danger,
                  locale: state.preferences.locale,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SummaryPill(
                  label: 'Income',
                  money: Money(
                    amountMinor: income,
                    currency: state.preferences.baseCurrency,
                  ),
                  tone: MetricTone.positive,
                  locale: state.preferences.locale,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SummaryPill(
                  label: 'Expense',
                  money: Money(
                    amountMinor: expense,
                    currency: state.preferences.baseCurrency,
                  ),
                  tone: MetricTone.danger,
                  locale: state.preferences.locale,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            plannedCount > 0
                ? '$plannedCount planned records included'
                : 'Actual records only',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _CalendarFilterCard(
                  icon: Icons.category_outlined,
                  title: 'Category',
                  value: selectedCategory?.name ?? 'All categories',
                  subtitle: 'Month forecast',
                  active: _categoryFilter != null,
                  onTap: () => _showCategoryFilter(state),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CalendarFilterCard(
                  icon: Icons.account_balance_outlined,
                  title: 'Accounts',
                  value: selectedAccount?.name ?? 'All accounts',
                  subtitle: 'Running Net',
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
                  if (w > 0) const SizedBox(height: 4),
                  Expanded(
                    child: Row(
                      children: [
                        for (var d = 0; d < 7; d++) ...[
                          if (d > 0) const SizedBox(width: 4),
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
                                  onTap: records.isEmpty
                                      ? null
                                      : () => _showDay(
                                          context,
                                          state,
                                          day,
                                          records,
                                        ),
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
      if (transaction.status == 'void') {
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
      if (transaction.type == 'interest_in' || transaction.type == 'interest_out') {
        final account = accountById(state, transaction.accountId);
        if (account?.loanDetails?.hideInterestInLedger == true) {
          if (_accountFilter != account?.id) {
            return false;
          }
        }
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
    if (through.isBefore(now)) return balanceMinor;

    final allForecasts = forecastRecurringTransactions(state, now, through);

    for (final forecast in allForecasts) {
      if (forecast.occurredAt.isBefore(now) ||
          !forecast.occurredAt.isBefore(through)) {
        continue;
      }
      
      if (selectedAccountIds.contains(forecast.accountId)) {
        final delta = convertMoneyForDisplay(
          state,
          Money(amountMinor: sourceDelta(forecast), currency: forecast.amount.currency),
          state.preferences.baseCurrency,
        );
        balanceMinor += delta.amountMinor;
      }
      
      if (forecast.counterAccountId != null && selectedAccountIds.contains(forecast.counterAccountId)) {
        final delta = convertMoneyForDisplay(
          state,
          Money(
            amountMinor: counterDelta(forecast), 
            currency: forecast.counterAmount?.currency ?? forecast.amount.currency
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
                '${accountTypeLabel(account.type)} · ${formatMoney(accountBalance(state, account), state.preferences.locale)}',
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
            subtitle: category.kind,
            icon: Icons.category_outlined,
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.yMMMMd(
                  state.preferences.locale.replaceAll('_', '-'),
                ).format(date),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final transaction in records) ...[
                TransactionRow(
                  state: state,
                  transaction: transaction,
                  onTap: () {
                    if (transaction.status == 'forecast') {
                      final templateId = transaction.id.split('-')[1];
                      context.push('/recurring/$templateId/edit');
                    } else {
                      context.push('/transaction/${transaction.id}');
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
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
    final color = switch (tone) {
      MetricTone.positive =>
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.positiveDark
            : AppColors.positiveLight,
      MetricTone.danger => scheme.error,
      MetricTone.warning => scheme.secondary,
      MetricTone.standard => scheme.onSurface,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
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
          Text(
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant,
            ),
          ),
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
    final income = records
        .where((tx) => incomeTypes.contains(tx.type))
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);
    final expense = records
        .where((tx) => expenseTypes.contains(tx.type))
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isToday ? scheme.primaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: isToday ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Opacity(
          opacity: inMonth ? 1 : 0.42,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${date.day}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  if (records.isNotEmpty)
                    Icon(Icons.circle, size: 6, color: scheme.primary),
                ],
              ),
              const Spacer(),
              if (income > 0)
                Text(
                  '+${formatCompactMoney(Money(amountMinor: income, currency: state.preferences.baseCurrency), state.preferences.locale)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9,
                    color: amountColor(context, income),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (expense > 0)
                Text(
                  '-${formatCompactMoney(Money(amountMinor: expense, currency: state.preferences.baseCurrency), state.preferences.locale)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9,
                    color: amountColor(context, -expense),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
