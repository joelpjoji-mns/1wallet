import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'home_screen.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../transactions/transaction_row.dart';
import 'home_async_providers.dart';
import 'home_components.dart';
import 'home_dashboard_selectors.dart';
import 'home_widget_card.dart';
import 'home_widget_models.dart';


final _homeScheduledTransactionsProvider =
    Provider.autoDispose<List<TransactionRecord>>((ref) {
      final state = ref.watch(ledgerProvider);
      return scheduledTransactions(state);
    });

final _homeSortedTransactionsProvider =
    Provider.autoDispose<List<TransactionRecord>>((ref) {
      final state = ref.watch(ledgerProvider);
      return sortedTransactions(state, includeScheduled: false);
    });

final _homeCurrentMonthFlowProvider =
    Provider.autoDispose<({Money income, Money expense})>((ref) {
      final state = ref.watch(ledgerProvider);
      return flowForCurrentMonth(state);
    });

Widget buildHomeDashboardWidget({
  required BuildContext context,
  required HomeDashboardWidgetId id,
  required LedgerState state,
  required ValueChanged<int> onTabSelected,
}) {
  return switch (id) {
    HomeDashboardWidgetId.balanceHero => BalanceHomeWidget(state: state),
    HomeDashboardWidgetId.accountGrid => AccountGridHomeWidget(
      state: state,
      onManage: () => onTabSelected(4),
    ),
    HomeDashboardWidgetId.recentRecords => RecentRecordsHomeWidget(
      state: state,
      onView: () => onTabSelected(1),
    ),
    HomeDashboardWidgetId.balanceTrend => BalanceTrendHomeWidget(state: state),
    HomeDashboardWidgetId.currencyValues => CurrencyValuesHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.summaryTiles => FinanceSummaryHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.upcomingScheduled => UpcomingDueHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.dueNow => UpcomingDueHomeWidget(state: state),
    HomeDashboardWidgetId.billWatch => UpcomingDueHomeWidget(state: state),
    HomeDashboardWidgetId.emiTracker => LoansAndEmisHomeWidget(state: state),
    HomeDashboardWidgetId.loanPayoff => LoansAndEmisHomeWidget(state: state),
    HomeDashboardWidgetId.plannedPaymentsTile => PlannedPaymentsHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.loansTile => LoansHomeWidget(state: state),
    HomeDashboardWidgetId.cardDebt => CardsHomeWidget(state: state),
    HomeDashboardWidgetId.cardPaymentPlan => CardsHomeWidget(state: state),
    HomeDashboardWidgetId.cashflowForecast => CashflowForecastHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.accountGroups => AccountGroupsHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.reviewQueue => AutomationReviewHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.automationHealth => AutomationReviewHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.savingsRunway => SavingsRunwayHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.cashflowBook => CashflowBookHomeWidget(state: state),
    HomeDashboardWidgetId.topCategories => TopCategoriesHomeWidget(
      state: state,
      onRecords: () => onTabSelected(1),
    ),
    HomeDashboardWidgetId.incomeMix => IncomeMixHomeWidget(
      state: state,
      onRecords: () => onTabSelected(1),
    ),
    HomeDashboardWidgetId.budgetPressure => BudgetPressureHomeWidget(
      state: state,
    ),
    HomeDashboardWidgetId.goalProgress => GoalProgressHomeWidget(state: state),
    HomeDashboardWidgetId.currencyExposure => CurrencyExposureHomeWidget(
      state: state,
    ),
  };
}

class BalanceHomeWidget extends ConsumerStatefulWidget {
  const BalanceHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  ConsumerState<BalanceHomeWidget> createState() => _BalanceHomeWidgetState();
}

class _BalanceHomeWidgetState extends ConsumerState<BalanceHomeWidget> {
  String _period = 'This month';

  @override
  Widget build(BuildContext context) {
    final selectedAccountId = ref.watch(homeSelectedAccountProvider);
    final scheme = Theme.of(context).colorScheme;

    final allCurrencies = availableCurrencies(widget.state);

    String? forcedCurrency;
    if (selectedAccountId != null && selectedAccountId != 'cash_group') {
      forcedCurrency = accountById(
        widget.state,
        selectedAccountId,
      )?.currency.toUpperCase();
    }

    var displayCurrency =
        forcedCurrency ??
        widget.state.preferences.displayCurrency.toUpperCase();
    if (forcedCurrency == null &&
        !allCurrencies.contains(displayCurrency) &&
        allCurrencies.isNotEmpty) {
      displayCurrency = allCurrencies.first;
    }

    final total = ref.watch(
      homeTotalBalanceProvider((
        accountId: selectedAccountId,
        targetCurrency: displayCurrency,
      )),
    );

    final flow = ref.watch(
      homeFlowForPeriodProvider((
        period: _period,
        accountId: selectedAccountId,
        targetCurrency: displayCurrency,
      )),
    );

    final currencyBreakdown = balanceBreakdownByCurrency(
      widget.state,
      accountId: selectedAccountId,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 178),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HomeWidgetReorderableIcon(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: scheme.primary,
                size: 32,
                iconSize: 18,
                borderRadius: AppRadii.sm,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Balance',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                initialValue: _period,
                onSelected: (value) => setState(() => _period = value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Today', child: Text('Today')),
                  PopupMenuItem(value: 'This week', child: Text('This week')),
                  PopupMenuItem(value: 'This month', child: Text('This month')),
                  PopupMenuItem(value: 'This year', child: Text('This year')),
                ],
                child: HomeBalancePill(
                  label: _period,
                  icon: Icons.calendar_month,
                  showChevron: true,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (allCurrencies.length > 1 && forcedCurrency == null)
                PopupMenuButton<String>(
                  initialValue: displayCurrency,
                  onSelected: (val) {
                    ref.read(ledgerProvider.notifier).setDisplayCurrency(val);
                  },
                  itemBuilder: (context) => allCurrencies
                      .map((c) => PopupMenuItem(value: c, child: Text(c)))
                      .toList(),
                  child: HomeBalancePill(
                    label: displayCurrency,
                    icon: Icons.currency_exchange_outlined,
                    showChevron: true,
                  ),
                )
              else
                HomeBalancePill(
                  label: displayCurrency,
                  icon: Icons.currency_exchange_outlined,
                  showChevron: false,
                ),
            ],
          ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(
              begin: total.amountMinor.toDouble(),
              end: total.amountMinor.toDouble(),
            ),
            builder: (context, value, child) {
              return Text(
                formatMoney(
                  total.copyWith(amountMinor: value.round()),
                  widget.state.preferences.locale,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 24,
            child: currencyBreakdown.isNotEmpty
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final money in currencyBreakdown) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Text(
                              '${money.currency} ${formatMoney(money, widget.state.preferences.locale)}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (money != currencyBreakdown.last)
                            const SizedBox(width: AppSpacing.xs),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: HomeFlowPanel(
                  label: 'Income',
                  value: flow.income,
                  locale: widget.state.preferences.locale,
                  tone: MetricTone.positive,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: HomeFlowPanel(
                  label: 'Expense',
                  value: flow.expense,
                  locale: widget.state.preferences.locale,
                  tone: MetricTone.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccountGridHomeWidget extends ConsumerWidget {
  const AccountGridHomeWidget({
    required this.state,
    required this.onManage,
    super.key,
  });

  final LedgerState state;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAccountId = ref.watch(homeSelectedAccountProvider);
    final balances = ref.watch(homeAccountBalanceMapProvider);
    final accounts =
        state.accounts
            .where((account) => !account.isArchived && account.showOnHome)
            .toList()
          ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return HomeWidgetCard(
      title: 'All accounts',
      subtitle: selectedAccountId != null
          ? 'Tap selected account again to show all'
          : 'Choose an account to filter the rest of Home',
      icon: Icons.grid_view_rounded,
      iconColor: Theme.of(context).colorScheme.primary,
      actionLabel: 'Manage',
      onAction: selectedAccountId != null
          ? () => context.push('/account/$selectedAccountId')
          : onManage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          const columns = 3;
          const spacing = AppSpacing.xs;
          final tileWidth =
              (availableWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final account in accounts)
                SizedBox(
                  width: tileWidth.clamp(0, availableWidth),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity:
                        selectedAccountId == null ||
                            selectedAccountId == account.id
                        ? 1.0
                        : 0.35,
                    child: _AccountTile(
                      state: state,
                      account: account,
                      balances: balances,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RecentRecordsHomeWidget extends ConsumerWidget {
  const RecentRecordsHomeWidget({
    required this.state,
    required this.onView,
    super.key,
  });

  final LedgerState state;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAccountId = ref.watch(homeSelectedAccountProvider);
    final recent = ref
        .watch(_homeSortedTransactionsProvider)
        .where(
          (t) =>
              selectedAccountId == null ||
              t.accountId == selectedAccountId ||
              t.counterAccountId == selectedAccountId,
        )
        .take(5)
        .toList();
    return HomeWidgetCard(
      title: 'Recent records',
      icon: Icons.format_list_bulleted_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      actionLabel: 'View',
      onAction: onView,
      child: recent.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No records yet',
              body: 'Your latest transactions will appear here.',
            )
          : Column(
              children: [
                for (final transaction in recent) ...[
                  TransactionRow(
                    state: state,
                    transaction: transaction,
                    onTap: () => context.push('/transaction/${transaction.id}'),
                  ),
                  if (transaction != recent.last)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
    );
  }
}

class BalanceTrendHomeWidget extends ConsumerStatefulWidget {
  const BalanceTrendHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  ConsumerState<BalanceTrendHomeWidget> createState() => _BalanceTrendHomeWidgetState();
}

class _BalanceTrendHomeWidgetState extends ConsumerState<BalanceTrendHomeWidget> {
  String _period = 'This year';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime? start;
    switch (_period) {
      case 'This week':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'This month':
        start = now.subtract(const Duration(days: 30));
        break;
      case 'This year':
        start = DateTime(now.year);
        break;
      case 'All time':
        start = null;
        break;
    }

    final trend = ref.watch(homeBalanceTrendProvider((start: start, end: now)));
    final values = trend.map((point) => point.balance.amountMinor).toList();
    final periodLabel = trend.isEmpty
        ? _period
        : '${_shortDate(trend.first.date)} to ${_shortDate(trend.last.date)}';

    var minY = values.isEmpty ? 0.0 : values.reduce(math.min).toDouble();
    var maxY = values.isEmpty ? 0.0 : values.reduce(math.max).toDouble();
    
    if (maxY == minY) {
      maxY += 100000;
      minY -= 100000;
    } else {
      final span = maxY - minY;
      maxY += span * 0.2;
      minY -= span * 0.2;
    }

    if (values.isNotEmpty) {
      final finalValue = values.last.toDouble();
      final span = maxY - minY;
      final percentile = (finalValue - minY) / span;

      if (percentile > 0.8) {
        maxY = (finalValue - 0.2 * minY) / 0.8;
      } else if (percentile < 0.2) {
        minY = (finalValue - 0.2 * maxY) / 0.8;
      }
    }

    String formatCompact(num amountMinor) {
      if (amountMinor == 0) return '0';
      final absVal = (amountMinor / 100.0).abs();
      final sign = amountMinor < 0 ? '-' : '';
      if (absVal >= 100000) {
        final l = absVal / 100000;
        return '$sign${l.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}L';
      } else if (absVal >= 1000) {
        final k = absVal / 1000;
        return '$sign${k.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
      }
      return '$sign${absVal.toInt()}';
    }

    final yLabels = [
      formatCompact(maxY),
      formatCompact(minY + (maxY - minY) * 2 / 3),
      formatCompact(minY + (maxY - minY) * 1 / 3),
      formatCompact(minY),
    ];

    final xLabels = [
      if (start != null) _shortDate(start) else trend.isNotEmpty ? _shortDate(trend.first.date) : '',
      '${trend.length} moves',
      _shortDate(now),
    ];

    return HomeWidgetCard(
      title: 'Balance trend',
      subtitle: periodLabel,
      icon: Icons.bar_chart_rounded,
      iconColor: Theme.of(context).colorScheme.tertiary,
      actionLabel: _period,
      onAction: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select period'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'This week'),
                child: const Text('This week'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'This month'),
                child: const Text('This month'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'This year'),
                child: const Text('This year'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'All time'),
                child: const Text('All time'),
              ),
            ],
          ),
        );
        if (result != null) {
          setState(() => _period = result);
        }
      },
      child: GestureDetector(
        onTap: () => context.push('/balance-trend'),
        child: Column(
          children: [
            MiniLineChart(
              values: values,
              color: Theme.of(context).colorScheme.primary,
              yAxisLabels: yLabels,
              xAxisLabels: xLabels,
              minY: minY,
              maxY: maxY,
              tooltipFormatter: (val) => formatMoney(
                Money(
                  amountMinor: val.toInt(),
                  currency: widget.state.preferences.displayCurrency,
                ),
                widget.state.preferences.locale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurrencyValuesHomeWidget extends ConsumerStatefulWidget {
  const CurrencyValuesHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  ConsumerState<CurrencyValuesHomeWidget> createState() =>
      _CurrencyValuesHomeWidgetState();
}

class _CurrencyValuesHomeWidgetState extends ConsumerState<CurrencyValuesHomeWidget> {
  final _baseController = TextEditingController(text: '1');
  final _quoteController = TextEditingController();
  double _rate = 1.0;
  bool _initialized = false;

  void _updateQuote() {
    final baseVal = double.tryParse(_baseController.text) ?? 0.0;
    _quoteController.text = (baseVal * _rate).toStringAsFixed(5);
  }

  void _updateBase() {
    final quoteVal = double.tryParse(_quoteController.text) ?? 0.0;
    if (_rate > 0) {
      _baseController.text = (quoteVal / _rate).toStringAsFixed(5);
    }
  }

  @override
  void dispose() {
    _baseController.dispose();
    _quoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(homeCurrencySnapshotProvider);
    
    if (snapshot?.rate != null) {
      if (!_initialized || _rate != snapshot!.rate!) {
        _rate = snapshot!.rate!;
        _initialized = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateQuote();
        });
      }
    }

    if (snapshot == null) {
      return const HomeWidgetCard(
        title: 'Currency values',
        icon: Icons.currency_pound_rounded,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final quote = snapshot.quoteCurrency;

    if (quote == null || snapshot.rate == null) {
      return const HomeWidgetCard(
        title: 'Currency values',
        icon: Icons.currency_pound_rounded,
        child: EmptyState(
          icon: Icons.currency_exchange_outlined,
          title: 'No foreign currency yet',
          body: 'Foreign accounts or refreshed rates will appear here.',
        ),
      );
    }

    final rates =
        widget.state.exchangeRates
            .where(
              (r) =>
                  r.base.toUpperCase() == quote.toUpperCase() &&
                  r.quote.toUpperCase() ==
                      snapshot.baseCurrency.toUpperCase() &&
                  r.rate > 0,
            )
            .toList()
          ..sort((a, b) => a.asOfDate.compareTo(b.asOfDate));

    final values = rates.map((r) => r.rate).toList();

    final yLabels = values.isEmpty
        ? <String>[]
        : [
            values.reduce(math.max).toStringAsFixed(1),
            values.reduce(math.min).toStringAsFixed(1),
          ];
    final xLabels = rates.isEmpty
        ? <String>[]
        : [
            _shortDate(rates.first.asOfDate),
            '${rates.length} changes',
            _shortDate(rates.last.asOfDate),
          ];

    final scheme = Theme.of(context).colorScheme;

    return HomeWidgetCard(
      title: 'Currency values',
      subtitle: '1 rates to ${snapshot.baseCurrency}',
      icon: Icons.currency_pound_rounded,
      iconColor: scheme.tertiary,
      actionLabel: 'Rates',
      onAction: () => context.push('/currencies'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '1 $quote',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          Text(
            formatMoney(
              snapshot.convertedUnit!,
              widget.state.preferences.locale,
            ),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          if (values.length >= 2) ...[
            const SizedBox(height: AppSpacing.sm),
            MiniLineChart(
              values: values,
              color: scheme.error,
              yAxisLabels: yLabels,
              xAxisLabels: xLabels,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Latest ${_shortDate(DateTime.now())} 1 $quote = ${_rate.toStringAsFixed(2)} ${snapshot.baseCurrency}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.sm),
          _CurrencyInput(
            label: quote,
            controller: _baseController,
            onChanged: (_) => _updateQuote(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _CurrencyInput(
            label: 'Active input\n${snapshot.baseCurrency}',
            controller: _quoteController,
            onChanged: (_) => _updateBase(),
          ),
          if (snapshot.exposure.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final money in snapshot.exposure.take(2)) ...[
              HomeDetailRow(
                icon: Icons.account_balance_wallet_outlined,
                title: '${money.currency} exposure',
                subtitle: 'Foreign-currency account balance',
                trailing: _formatDisplayMoney(widget.state, money),
                iconColor: scheme.tertiary,
              ),
              if (money != snapshot.exposure.take(2).last)
                const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ],
      ),
    );
  }
}

class _CurrencyInput extends StatelessWidget {
  const _CurrencyInput({
    required this.label,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlphaFactor(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 20, color: scheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FinanceSummaryHomeWidget extends ConsumerWidget {
  const FinanceSummaryHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worth = ref.watch(homeNetWorthProvider);
    final scheduled = ref
        .watch(_homeScheduledTransactionsProvider)
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);
    return HomeWidgetCard(
      title: 'Finance summary',
      icon: Icons.grid_view_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      child: Row(
        children: [
          Expanded(
            child: HomeMetricTile(
              label: 'Planned',
              value: _formatDisplayBaseMoney(state, scheduled),
              icon: Icons.event_repeat_outlined,
              tone: MetricTone.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: HomeMetricTile(
              label: 'Debts',
              value: formatMoney(
                worth.liabilities.copyWith(
                  amountMinor: worth.liabilities.amountMinor.abs(),
                ),
                state.preferences.locale,
              ),
              icon: Icons.credit_card_outlined,
              tone: MetricTone.danger,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: HomeMetricTile(
              label: 'Net worth',
              value: formatMoney(worth.total, state.preferences.locale),
              icon: Icons.balance_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class UpcomingDueHomeWidget extends ConsumerWidget {
  const UpcomingDueHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAccountId = ref.watch(homeSelectedAccountProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduled = ref
        .watch(_homeScheduledTransactionsProvider)
        .where(
          (t) =>
              selectedAccountId == null ||
              t.accountId == selectedAccountId ||
              t.counterAccountId == selectedAccountId,
        )
        .toList();
    final due = scheduled.where((transaction) {
      final day = DateTime(
        transaction.occurredAt.year,
        transaction.occurredAt.month,
        transaction.occurredAt.day,
      );
      return !day.isAfter(today);
    }).toList();
    final next = scheduled.take(4).toList();
    final dueAmount = due.fold<int>(
      0,
      (sum, transaction) => sum + transaction.baseAmount.amountMinor,
    );
    return HomeWidgetCard(
      title: 'Upcoming & due',
      subtitle: 'Scheduled payments and bills',
      icon: Icons.event_available_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      actionLabel: 'Open',
      onAction: () => context.push('/recurring'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Due now',
                  value: '${due.length}',
                  icon: Icons.event_busy_outlined,
                  tone: due.isEmpty ? MetricTone.standard : MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Amount',
                  value: _formatDisplayBaseMoney(state, dueAmount),
                  icon: Icons.payments_outlined,
                  tone: MetricTone.danger,
                ),
              ),
            ],
          ),
          if (next.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No scheduled records yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            for (final transaction in next) ...[
              TransactionRow(
                state: state,
                transaction: transaction,
                onTap: () => context.push('/transaction/${transaction.id}'),
              ),
              if (transaction != next.last)
                const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ],
      ),
    );
  }
}

class LoansAndEmisHomeWidget extends ConsumerWidget {
  const LoansAndEmisHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = state.accounts
        .where(
          (account) => account.type == 'loan' || account.type == 'overdraft',
        )
        .toList();
    final remaining = loans.fold<int>(
      0,
      (sum, account) =>
          sum + _displayAccountBalanceMinor(state, account, absolute: true),
    );
    final monthEnd = DateTime.now().add(const Duration(days: 30));
    final emis = ref
        .watch(_homeScheduledTransactionsProvider)
        .where(
          (transaction) =>
              transaction.type == 'loan_repayment' &&
              !transaction.occurredAt.isAfter(monthEnd),
        )
        .toList();
    final emiTotal = emis.fold<int>(
      0,
      (sum, transaction) => sum + transaction.baseAmount.amountMinor,
    );
    final next = emis.isEmpty ? null : emis.first;
    return HomeWidgetCard(
      title: 'Loans & EMIs',
      subtitle: 'Merged EMI tracker and payoff',
      icon: Icons.account_balance_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      actionLabel: 'Loans',
      onAction: () => context.push('/loans'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Remaining',
                  value: formatMoney(
                    Money(
                      amountMinor: remaining,
                      currency: state.preferences.displayCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.account_balance_outlined,
                  tone: MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'EMIs',
                  value: _formatDisplayBaseMoney(state, emiTotal),
                  icon: Icons.event_repeat_outlined,
                  tone: MetricTone.warning,
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: AppSpacing.sm),
            HomeDetailRow(
              icon: Icons.event_available_outlined,
              title: 'Next EMI',
              subtitle: _shortDate(next.occurredAt),
              trailing: _formatDisplayMoney(state, next.baseAmount),
              iconColor: Theme.of(context).colorScheme.error,
              tone: MetricTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

// New widget: PlannedPaymentsHomeWidget
class PlannedPaymentsHomeWidget extends ConsumerWidget {
  const PlannedPaymentsHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planned = ref
        .watch(_homeScheduledTransactionsProvider)
        .where((tx) => tx.type == 'payment' || tx.type == 'scheduled')
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);
    return HomeWidgetCard(
      title: 'Planned payments',
      subtitle: 'Upcoming scheduled payments',
      icon: Icons.event_repeat_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      actionLabel: 'Planned',
      onAction: () => context.push('/planned'),
      child: HomeMetricTile(
        label: 'Planned',
        value: _formatDisplayBaseMoney(state, planned),
        icon: Icons.event_repeat_outlined,
        tone: MetricTone.warning,
      ),
    );
  }
}

// New widget: LoansHomeWidget
class LoansHomeWidget extends ConsumerWidget {
  const LoansHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = state.accounts
        .where(
          (account) => account.type == 'loan' || account.type == 'overdraft',
        )
        .toList();
    final remaining = loans.fold<int>(
      0,
      (sum, account) =>
          sum + _displayAccountBalanceMinor(state, account, absolute: true),
    );
    final monthEnd = DateTime.now().add(const Duration(days: 30));
    final emis = ref
        .watch(_homeScheduledTransactionsProvider)
        .where(
          (transaction) =>
              transaction.type == 'loan_repayment' &&
              !transaction.occurredAt.isAfter(monthEnd),
        )
        .toList();
    final emiTotal = emis.fold<int>(
      0,
      (sum, transaction) => sum + transaction.baseAmount.amountMinor,
    );
    final next = emis.isEmpty ? null : emis.first;
    return HomeWidgetCard(
      title: 'Loans & EMIs',
      subtitle: 'Merged EMI tracker and payoff',
      icon: Icons.account_balance_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      actionLabel: 'Loans',
      onAction: () => context.push('/loans'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Remaining',
                  value: formatMoney(
                    Money(
                      amountMinor: remaining,
                      currency: state.preferences.displayCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.account_balance_outlined,
                  tone: MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'EMIs',
                  value: _formatDisplayBaseMoney(state, emiTotal),
                  icon: Icons.event_repeat_outlined,
                  tone: MetricTone.warning,
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: AppSpacing.sm),
            HomeDetailRow(
              icon: Icons.event_available_outlined,
              title: 'Next EMI',
              subtitle: _shortDate(next.occurredAt),
              trailing: _formatDisplayMoney(state, next.baseAmount),
              iconColor: Theme.of(context).colorScheme.error,
              tone: MetricTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

class CardsHomeWidget extends ConsumerWidget {
  const CardsHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(homeAccountBalanceMapProvider);
    final cards = state.accounts
        .where(
          (account) => account.type == 'credit_card' && !account.isArchived,
        )
        .toList();
    final debt = cards.fold<int>(
      0,
      (sum, account) =>
          sum +
          _displayAccountBalanceMinor(
            state,
            account,
            absolute: true,
            balances: balances,
          ),
    );
    Account? highest;
    for (final card in cards) {
      if (highest == null ||
          _displayAccountBalanceMinor(
                state,
                card,
                absolute: true,
                balances: balances,
              ) >
              _displayAccountBalanceMinor(
                state,
                highest,
                absolute: true,
                balances: balances,
              )) {
        highest = card;
      }
    }
    final payments = ref
        .watch(_homeScheduledTransactionsProvider)
        .where((transaction) => transaction.type == 'card_payment')
        .toList();
    final planned = payments.fold<int>(
      0,
      (sum, transaction) => sum + transaction.baseAmount.amountMinor,
    );
    return HomeWidgetCard(
      title: 'Cards',
      subtitle: 'Debt and payment plan',
      icon: Icons.credit_card_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      actionLabel: 'Cards',
      onAction: () => context.push('/cards'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Card debt',
                  value: formatMoney(
                    Money(
                      amountMinor: debt,
                      currency: state.preferences.displayCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.credit_card_outlined,
                  tone: MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Planned',
                  value: _formatDisplayBaseMoney(state, planned),
                  icon: Icons.payments_outlined,
                  tone: MetricTone.warning,
                ),
              ),
            ],
          ),
          if (highest != null) ...[
            const SizedBox(height: AppSpacing.sm),
            HomeDetailRow(
              icon: Icons.priority_high_rounded,
              title: 'Highest card',
              subtitle: highest.name,
              trailing: formatMoney(
                _displayMoney(
                  state,
                  accountBalanceFromMap(balances, highest),
                ).copyWith(
                  amountMinor: _displayAccountBalanceMinor(
                    state,
                    highest,
                    absolute: true,
                    balances: balances,
                  ),
                ),
                state.preferences.locale,
              ),
              iconColor: Theme.of(context).colorScheme.error,
              tone: MetricTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

class CashflowForecastHomeWidget extends ConsumerWidget {
  const CashflowForecastHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final end = DateTime.now().add(const Duration(days: 30));
    final upcoming = ref
        .watch(_homeScheduledTransactionsProvider)
        .where((transaction) => !transaction.occurredAt.isAfter(end))
        .toList();
    var income = 0;
    var outflow = 0;
    for (final transaction in upcoming) {
      if (incomeTypes.contains(transaction.type)) {
        income += transaction.baseAmount.amountMinor;
      } else {
        outflow += transaction.baseAmount.amountMinor;
      }
    }
    final next = upcoming.isEmpty ? null : upcoming.first;
    return HomeWidgetCard(
      title: '30-day forecast',
      subtitle: 'Next 30 days',
      icon: Icons.calendar_month_outlined,
      iconColor: Theme.of(context).colorScheme.tertiary,
      actionLabel: 'Plan',
      onAction: () => context.push('/recurring'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Income',
                  value: _formatDisplayBaseMoney(state, income),
                  icon: Icons.arrow_downward_rounded,
                  tone: MetricTone.positive,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Outflow',
                  value: _formatDisplayBaseMoney(state, outflow),
                  icon: Icons.arrow_upward_rounded,
                  tone: MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Net',
                  value: _formatDisplayBaseMoney(state, income - outflow),
                  icon: Icons.swap_vert_rounded,
                  tone: income >= outflow
                      ? MetricTone.positive
                      : MetricTone.danger,
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: AppSpacing.sm),
            HomeDetailRow(
              icon: Icons.schedule_outlined,
              title: 'Next scheduled',
              subtitle:
                  '${_shortDate(next.occurredAt)} · ${transactionTypeLabel(next.type)}',
              trailing: _formatDisplayMoney(state, next.baseAmount),
              iconColor: Theme.of(context).colorScheme.error,
              tone: incomeTypes.contains(next.type)
                  ? MetricTone.positive
                  : MetricTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

class AccountGroupsHomeWidget extends StatelessWidget {
  const AccountGroupsHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final groups = _accountGroupSummaries(state).take(5).toList();
    return HomeWidgetCard(
      title: 'Account groups',
      icon: Icons.account_tree_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      child: groups.isEmpty
          ? const EmptyState(
              icon: Icons.account_tree_outlined,
              title: 'No accounts yet',
              body: 'Groups appear after accounts are restored or added.',
            )
          : Column(
              children: [
                for (final group in groups) ...[
                  HomeDetailRow(
                    icon: Icons.folder_outlined,
                    title: '${group.label} · ${group.count}',
                    trailing: formatMoney(
                      group.balance,
                      state.preferences.locale,
                    ),
                    iconColor: group.balance.amountMinor < 0
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    tone: group.balance.amountMinor < 0
                        ? MetricTone.danger
                        : MetricTone.standard,
                  ),
                  if (group != groups.last)
                    const Divider(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class AutomationReviewHomeWidget extends StatelessWidget {
  const AutomationReviewHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final pending = state.captureCandidates
        .where((candidate) => candidate.status == 'pending')
        .toList();
    final sources = pending.map((candidate) => candidate.source).toSet().length;
    final warnings =
        state.importBatches.fold<int>(
          0,
          (sum, batch) => sum + batch.warningCount,
        ) +
        pending.fold<int>(
          0,
          (sum, candidate) => sum + candidate.warnings.length,
        );
    return HomeWidgetCard(
      title: 'Automation & review',
      subtitle: 'Queue, imports, and warnings',
      icon: Icons.verified_user_outlined,
      iconColor: Theme.of(context).colorScheme.tertiary,
      actionLabel: 'Review',
      onAction: () => context.push('/review'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Review',
                  value: '${pending.length}',
                  icon: Icons.smart_toy_outlined,
                  tone: pending.isEmpty
                      ? MetricTone.standard
                      : MetricTone.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Warnings',
                  value: '$warnings',
                  icon: Icons.warning_amber_rounded,
                  tone: warnings == 0 ? MetricTone.standard : MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Sources',
                  value: '$sources',
                  icon: Icons.hub_outlined,
                  tone: MetricTone.standard,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          HomeDetailRow(
            icon: Icons.import_export_outlined,
            title: 'Import batches',
            subtitle: 'CSV, SMS, and migration imports',
            trailing: '${state.importBatches.length}',
            iconColor: Theme.of(context).colorScheme.secondary,
          ),
        ],
      ),
    );
  }
}

class SavingsRunwayHomeWidget extends StatelessWidget {
  const SavingsRunwayHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final liquid = state.accounts
        .where(
          (account) =>
              !account.isArchived &&
              !isLiabilityAccount(account) &&
              {'bank', 'cash', 'wallet'}.contains(account.type),
        )
        .fold<int>(
          0,
          (sum, account) => sum + _displayAccountBalanceMinor(state, account),
        );
    final since = DateTime.now().subtract(const Duration(days: 30));
    final expenses = state.transactions
        .where((transaction) {
          return transaction.status != 'scheduled' &&
              transaction.status != 'void' &&
              expenseTypes.contains(transaction.type) &&
              !transaction.isExcludedFromReports &&
              !transaction.occurredAt.isBefore(since);
        })
        .fold<int>(
          0,
          (sum, transaction) =>
              sum +
              _displayBaseMinor(state, transaction.baseAmount.amountMinor),
        );
    final dailyBurn = (expenses / 30).round();
    final runway = dailyBurn <= 0 ? null : (liquid / dailyBurn).floor();
    return HomeWidgetCard(
      title: 'Savings runway',
      subtitle: 'Liquid cash vs last 30 days',
      icon: Icons.hourglass_bottom_rounded,
      iconColor: Theme.of(context).colorScheme.secondary,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Liquid',
                  value: formatMoney(
                    Money(
                      amountMinor: liquid,
                      currency: state.preferences.displayCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  tone: MetricTone.positive,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Runway',
                  value: runway == null ? '—' : '${runway}d',
                  icon: Icons.hourglass_empty_rounded,
                  tone: MetricTone.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          HomeDetailRow(
            icon: Icons.trending_up_rounded,
            title: 'Daily burn',
            subtitle: 'Based on cleared expenses',
            trailing: formatMoney(
              Money(
                amountMinor: dailyBurn,
                currency: state.preferences.displayCurrency,
              ),
              state.preferences.locale,
            ),
            iconColor: Theme.of(context).colorScheme.error,
            tone: MetricTone.danger,
          ),
        ],
      ),
    );
  }
}

class CashflowBookHomeWidget extends ConsumerWidget {
  const CashflowBookHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(_homeCurrentMonthFlowProvider);
    final net = flow.income.amountMinor - flow.expense.amountMinor;
    return HomeWidgetCard(
      title: 'Cashflow book',
      subtitle: _monthRangeLabel(DateTime.now()),
      icon: Icons.receipt_long_outlined,
      iconColor: Theme.of(context).colorScheme.error,
      child: Column(
        children: [
          HomeDetailRow(
            icon: Icons.arrow_downward_rounded,
            title: 'Income',
            trailing: formatMoney(flow.income, state.preferences.locale),
            iconColor: Theme.of(context).colorScheme.tertiary,
            tone: MetricTone.positive,
          ),
          const SizedBox(height: AppSpacing.md),
          HomeDetailRow(
            icon: Icons.arrow_upward_rounded,
            title: 'Expenses',
            trailing: formatMoney(flow.expense, state.preferences.locale),
            iconColor: Theme.of(context).colorScheme.error,
            tone: MetricTone.danger,
          ),
          const SizedBox(height: AppSpacing.md),
          HomeDetailRow(
            icon: Icons.swap_vert_rounded,
            title: 'Net',
            trailing: formatMoney(
              Money(
                amountMinor: net,
                currency: state.preferences.displayCurrency,
              ),
              state.preferences.locale,
            ),
            iconColor: net >= 0
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.error,
            tone: net >= 0 ? MetricTone.positive : MetricTone.danger,
          ),
        ],
      ),
    );
  }
}

class TopCategoriesHomeWidget extends StatelessWidget {
  const TopCategoriesHomeWidget({
    required this.state,
    required this.onRecords,
    super.key,
  });

  final LedgerState state;
  final VoidCallback onRecords;

  @override
  Widget build(BuildContext context) {
    final items = _categoryTotals(state, income: false).take(5).toList();
    return _CategoryListWidget(
      state: state,
      title: 'Top categories',
      icon: Icons.category_outlined,
      iconColor: Theme.of(context).colorScheme.error,
      actionLabel: 'Records',
      onRecords: onRecords,
      items: items,
    );
  }
}

class IncomeMixHomeWidget extends StatelessWidget {
  const IncomeMixHomeWidget({
    required this.state,
    required this.onRecords,
    super.key,
  });

  final LedgerState state;
  final VoidCallback onRecords;

  @override
  Widget build(BuildContext context) {
    final items = _categoryTotals(state, income: true).take(4).toList();
    return _CategoryListWidget(
      state: state,
      title: 'Income mix',
      icon: Icons.donut_large_outlined,
      iconColor: Theme.of(context).colorScheme.tertiary,
      actionLabel: 'Records',
      onRecords: onRecords,
      items: items,
    );
  }
}

class BudgetPressureHomeWidget extends StatelessWidget {
  const BudgetPressureHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    return HomeWidgetCard(
      title: 'Budget pressure',
      icon: Icons.speed_outlined,
      iconColor: Theme.of(context).colorScheme.secondary,
      actionLabel: 'Planner',
      onAction: () => context.push('/budgets/new'),
      child: state.budgets.isEmpty
          ? Text(
              'No budgets yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final budget in state.budgets.take(4)) ...[
                  HomeProgressRow(
                    label: budget.name,
                    value: _formatDisplayMoney(state, budget.spent),
                    progress: budget.amount.amountMinor == 0
                        ? 0
                        : budget.spent.amountMinor / budget.amount.amountMinor,
                    color: budget.spent.amountMinor > budget.amount.amountMinor
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  if (budget != state.budgets.take(4).last)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class GoalProgressHomeWidget extends StatelessWidget {
  const GoalProgressHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    return HomeWidgetCard(
      title: 'Goal progress',
      icon: Icons.track_changes_outlined,
      iconColor: Theme.of(context).colorScheme.tertiary,
      actionLabel: 'Planner',
      onAction: () => context.push('/goals/new'),
      child: state.goals.isEmpty
          ? Text(
              'No goals yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final goal in state.goals.take(4)) ...[
                  HomeProgressRow(
                    label: goal.name,
                    value: _formatDisplayMoney(state, goal.saved),
                    progress: goal.target.amountMinor == 0
                        ? 0
                        : goal.saved.amountMinor / goal.target.amountMinor,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  if (goal != state.goals.take(4).last)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class CurrencyExposureHomeWidget extends StatelessWidget {
  const CurrencyExposureHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final exposure = foreignCurrencyExposure(state);
    return HomeWidgetCard(
      title: 'Currency exposure',
      icon: Icons.currency_exchange_outlined,
      iconColor: Theme.of(context).colorScheme.tertiary,
      actionLabel: 'Rates',
      onAction: () => context.push('/currencies'),
      child: exposure.isEmpty
          ? Text(
              'No non-${state.preferences.baseCurrency} balances yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final money in exposure.take(5)) ...[
                  HomeDetailRow(
                    icon: Icons.currency_pound_rounded,
                    title: money.currency,
                    trailing: _formatDisplayMoney(state, money),
                    iconColor: Theme.of(context).colorScheme.tertiary,
                  ),
                  if (money != exposure.take(5).last)
                    const Divider(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class _CategoryListWidget extends StatelessWidget {
  const _CategoryListWidget({
    required this.state,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.actionLabel,
    required this.onRecords,
    required this.items,
  });

  final LedgerState state;
  final String title;
  final IconData icon;
  final Color iconColor;
  final String actionLabel;
  final VoidCallback onRecords;
  final List<_CategoryTotal> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, item) => sum + item.amountMinor);
    return HomeWidgetCard(
      title: title,
      icon: icon,
      iconColor: iconColor,
      actionLabel: actionLabel,
      onAction: onRecords,
      child: items.isEmpty
          ? Text(
              'No matching records this month.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final item in items) ...[
                  HomeProgressRow(
                    label: item.label,
                    value: formatMoney(
                      _displayBaseMoney(state, item.amountMinor),
                      state.preferences.locale,
                    ),
                    progress: total == 0 ? 0 : item.amountMinor / total,
                    color: item.color ?? iconColor,
                  ),
                  if (item != items.last) const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

Money _displayBaseMoney(LedgerState state, int amountMinor) {
  return convertMoneyForDisplay(
    state,
    Money(amountMinor: amountMinor, currency: state.preferences.baseCurrency),
  );
}

Money _displayMoney(LedgerState state, Money money) {
  return convertMoneyForDisplay(state, money);
}

String _formatDisplayMoney(LedgerState state, Money money) {
  return formatMoney(_displayMoney(state, money), state.preferences.locale);
}

String _formatDisplayBaseMoney(LedgerState state, int amountMinor) {
  return formatMoney(
    _displayBaseMoney(state, amountMinor),
    state.preferences.locale,
  );
}

int _displayBaseMinor(LedgerState state, int amountMinor) {
  return _displayBaseMoney(state, amountMinor).amountMinor;
}

int _displayAccountBalanceMinor(
  LedgerState state,
  Account account, {
  bool absolute = false,
  Map<String, Money>? balances,
}) {
  final balance = _displayMoney(
    state,
    balances == null
        ? accountBalance(state, account)
        : accountBalanceFromMap(balances, account),
  );
  return absolute ? balance.amountMinor.abs() : balance.amountMinor;
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({
    required this.state,
    required this.account,
    required this.balances,
  });

  final LedgerState state;
  final Account account;
  final Map<String, Money> balances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = accountDisplayColor(account);
    final foreground = _legibleForegroundFor(color);
    final nativeBalance = accountBalanceFromMap(balances, account);
    final displayBalance = convertMoneyForDisplay(state, nativeBalance);
    final isForeignCurrency =
        nativeBalance.currency.toUpperCase() !=
        state.preferences.displayCurrency.toUpperCase();
    final isCash = account.type == 'cash';

    String primaryLabel;
    String? secondaryLabel;

    if (isCash) {
      final breakdown = cashCurrencyBalancesForAccount(state, account);
      if (breakdown.isNotEmpty) {
        primaryLabel = formatMoney(displayBalance, state.preferences.locale);
        secondaryLabel = breakdown
            .map((m) => formatMoney(m, state.preferences.locale))
            .join(' | ');
      } else {
        primaryLabel = formatMoney(displayBalance, state.preferences.locale);
      }
    } else {
      if (isForeignCurrency) {
        primaryLabel = formatMoney(nativeBalance, state.preferences.locale);
        secondaryLabel = formatMoney(displayBalance, state.preferences.locale);
      } else {
        primaryLabel = formatMoney(displayBalance, state.preferences.locale);
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: () {
        final current = ref.read(homeSelectedAccountProvider);
        if (current == account.id) {
          ref.read(homeSelectedAccountProvider.notifier).state = null;
        } else {
          ref.read(homeSelectedAccountProvider.notifier).state = account.id;
        }
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  accountIcon(account),
                  color: foreground.withAlpha(200),
                  size: 13,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                // Currency badge for foreign accounts
                if (isForeignCurrency)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: foreground.withAlpha(40),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: foreground.withAlpha(60),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      nativeBalance.currency,
                      style: TextStyle(
                        color: foreground.withAlpha(220),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            // Display in base currency
            Text(
              primaryLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground.withAlpha(240),
                fontSize: 13,
                height: 1.1,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (secondaryLabel != null)
              Text(
                secondaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground.withAlpha(160),
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _legibleForegroundFor(Color background) {
  const light = Colors.white;
  const dark = Colors.black;
  return _contrastRatio(background, light) >= _contrastRatio(background, dark)
      ? light
      : dark;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

List<_AccountGroupSummary> _accountGroupSummaries(LedgerState state) {
  final byType = <String, ({int count, int amountMinor})>{};
  for (final account in state.accounts.where(
    (account) => !account.isArchived,
  )) {
    final balance = _displayAccountBalanceMinor(state, account);
    final current = byType[account.type] ?? (count: 0, amountMinor: 0);
    byType[account.type] = (
      count: current.count + 1,
      amountMinor: current.amountMinor + balance,
    );
  }
  final groups = byType.entries
      .map(
        (entry) => _AccountGroupSummary(
          label: accountTypeLabel(entry.key),
          count: entry.value.count,
          balance: Money(
            amountMinor: entry.value.amountMinor,
            currency: state.preferences.displayCurrency,
          ),
        ),
      )
      .toList();
  groups.sort((left, right) {
    final balanceCompare = right.balance.amountMinor.abs().compareTo(
      left.balance.amountMinor.abs(),
    );
    return balanceCompare == 0
        ? left.label.compareTo(right.label)
        : balanceCompare;
  });
  return groups;
}

List<_CategoryTotal> _categoryTotals(
  LedgerState state, {
  required bool income,
}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  final totals = <String, _CategoryTotal>{};
  for (final transaction in state.transactions) {
    if (transaction.status == 'scheduled' || transaction.status == 'void') {
      continue;
    }
    if (transaction.isExcludedFromReports) continue;
    if (transaction.occurredAt.isBefore(start) ||
        !transaction.occurredAt.isBefore(end)) {
      continue;
    }
    if (income && !incomeTypes.contains(transaction.type)) continue;
    if (!income && !expenseTypes.contains(transaction.type)) continue;

    final category = categoryById(state, transaction.categoryId);
    final key = category?.id ?? '__uncategorized__';
    final existing = totals[key];
    totals[key] = _CategoryTotal(
      label: category?.name ?? 'Uncategorized',
      amountMinor:
          (existing?.amountMinor ?? 0) + transaction.baseAmount.amountMinor,
      color: category?.color ?? existing?.color,
    );
  }
  final items = totals.values.toList();
  items.sort((left, right) => right.amountMinor.compareTo(left.amountMinor));
  return items;
}

String _monthRangeLabel(DateTime value) {
  final start = DateTime(value.year, value.month);
  final end = DateTime(value.year, value.month + 1, 0);
  return '${formatLedgerDate(start, 'en_IN')} to ${formatLedgerDate(end, 'en_IN')}';
}

String _shortDate(DateTime date) => formatLedgerDate(date, 'en_IN');

class _AccountGroupSummary {
  const _AccountGroupSummary({
    required this.label,
    required this.count,
    required this.balance,
  });

  final String label;
  final int count;
  final Money balance;
}

class _CategoryTotal {
  const _CategoryTotal({
    required this.label,
    required this.amountMinor,
    this.color,
  });

  final String label;
  final int amountMinor;
  final Color? color;
}
