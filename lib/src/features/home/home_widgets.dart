import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'home_screen.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../utils/currency_utils.dart';
import '../../widgets/app_kit.dart';
import '../transactions/transaction_row.dart';
import '../transactions/transactions_screen.dart';
import 'home_async_providers.dart';
import 'home_components.dart';
import 'home_dashboard_selectors.dart';
import 'home_widget_card.dart';
import 'home_widget_models.dart';
import 'package:fl_chart/fl_chart.dart';


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
    HomeDashboardWidgetId.balanceHero => BalanceHomeWidget(
      state: state,
      onTabSelected: onTabSelected,
    ),
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
  const BalanceHomeWidget({
    required this.state,
    required this.onTabSelected,
    super.key,
  });

  final LedgerState state;
  final ValueChanged<int> onTabSelected;

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
    ).map((m) => m.amountMinor < 0 ? m.copyWith(amountMinor: 0) : m).toList();

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
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              tween: Tween<double>(
                                begin: money.amountMinor.toDouble(),
                                end: money.amountMinor.toDouble(),
                              ),
                              builder: (context, value, child) {
                                return Text(
                                  '${money.currency} ${formatMoney(money.copyWith(amountMinor: value.round()), widget.state.preferences.locale)}',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              },
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
                child: InkWell(
                  onTap: () {
                    ref.read(transactionsTypeFilterProvider.notifier).state = 'income';
                    ref.read(transactionsDateFilterProvider.notifier).state = _mapPeriodToDateFilter(_period);
                    widget.onTabSelected(1);
                  },
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: HomeFlowPanel(
                    label: 'Income',
                    value: flow.income,
                    locale: widget.state.preferences.locale,
                    tone: MetricTone.positive,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: InkWell(
                  onTap: () {
                    ref.read(transactionsTypeFilterProvider.notifier).state = 'expense';
                    ref.read(transactionsDateFilterProvider.notifier).state = _mapPeriodToDateFilter(_period);
                    widget.onTabSelected(1);
                  },
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: HomeFlowPanel(
                    label: 'Expense',
                    value: flow.expense,
                    locale: widget.state.preferences.locale,
                    tone: MetricTone.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _mapPeriodToDateFilter(String period) {
    return switch (period) {
      'Today' => 'today',
      'This week' => 'this_week',
      'This month' => 'this_month',
      'This year' => 'this_year',
      _ => 'all',
    };
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
          : 'Select an account to filter',
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
              : MediaQuery.sizeOf(context).width - AppSpacing.md * 2;
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
                    const SizedBox(height: AppSpacing.xxs),
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
        : '${_shortDate(trend.first.date, widget.state.preferences.locale)} to ${_shortDate(trend.last.date, widget.state.preferences.locale)}';

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

    final spanChart = maxY - minY;
    double niceInterval = 1.0;
    if (spanChart > 0) {
      final roughStep = spanChart / 4;
      final magnitude = math.pow(10, (math.log(roughStep > 0 ? roughStep : 1) / math.ln10).floor()).toDouble();
      final normalizedStep = roughStep / magnitude;
      
      double niceStep;
      if (normalizedStep < 1.5) {
        niceStep = 1.0;
      } else if (normalizedStep < 3.5) {
        niceStep = 2.0;
      } else if (normalizedStep < 7.5) {
        niceStep = 5.0;
      } else {
        niceStep = 10.0;
      }
      
      niceInterval = niceStep * magnitude;
      if (spanChart >= 100000 && niceInterval < 100000) {
        niceInterval = 100000.0;
      } else if (spanChart >= 1000 && niceInterval < 1000) {
        niceInterval = 1000.0;
      }
    }

    String formatCompact(num amountMinor) {
      if (amountMinor == 0) return '0';
      final absVal = (amountMinor / 100.0).abs();
      final sign = amountMinor < 0 ? '-' : '';
      
      if (niceInterval >= 100000) {
        if (absVal >= 100000) {
          final l = (absVal / 100000).round();
          return '$sign${l}L';
        } else if (absVal >= 1000) {
          final k = (absVal / 1000).round();
          return '$sign${k}K';
        }
      } else if (niceInterval >= 1000) {
        if (absVal >= 1000) {
          final k = (absVal / 1000).round();
          return '$sign${k}K';
        }
      }
      return '$sign${absVal.toInt()}';
    }

    final xLabels = [
      if (start != null) _shortDate(start, widget.state.preferences.locale) else trend.isNotEmpty ? _shortDate(trend.first.date, widget.state.preferences.locale) : '',
      '${trend.length} moves',
      _shortDate(now, widget.state.preferences.locale),
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
            if (values.isEmpty)
              const SizedBox(
                height: 200,
                child: Center(child: Text('No data for this period')),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 16.0, top: 16.0),
                child: SizedBox(
                   height: 200,
                   width: double.infinity,
                   child: LineChart(
                      LineChartData(
                         gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: niceInterval,
                             getDrawingHorizontalLine: (value) => FlLine(
                                color: Theme.of(context).colorScheme.outlineVariant.withAlphaFactor(0.3),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                             ),
                         ),
                         titlesData: FlTitlesData(
                            show: true,
                            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                               sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  interval: niceInterval,
                                  getTitlesWidget: (value, meta) {
                                     return Text(formatCompact(value), style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant));
                                  },
                               ),
                            ),
                            bottomTitles: AxisTitles(
                               sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 22,
                                  getTitlesWidget: (value, meta) {
                                     final intValue = value.toInt();
                                     final lastIndex = values.length - 1;
                                     final middleIndex = lastIndex ~/ 2;
                                     if (intValue == 0) return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(xLabels[0], style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)));
                                     if (intValue == lastIndex && lastIndex > 0) return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(xLabels[2], style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)));
                                     if (intValue == middleIndex && middleIndex > 0 && middleIndex < lastIndex) return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(xLabels[1], style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)));
                                     return const SizedBox.shrink();
                                  },
                               ),
                            ),
                         ),
                         borderData: FlBorderData(show: false),
                         minX: 0,
                         maxX: (values.length - 1).toDouble(),
                         minY: minY,
                         maxY: maxY,
                         lineBarsData: [
                            LineChartBarData(
                               spots: [
                                 for (int i = 0; i < values.length; i++)
                                   FlSpot(i.toDouble(), values[i].toDouble())
                               ],
                               isCurved: true,
                               color: Theme.of(context).colorScheme.primary,
                               barWidth: 4,
                               isStrokeCapRound: true,
                               shadow: Shadow(
                                  color: Theme.of(context).colorScheme.primary.withAlphaFactor(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                               ),
                               dotData: FlDotData(
                                  show: true,
                                  checkToShowDot: (spot, barData) => spot.x == barData.spots.last.x,
                                  getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                     radius: 5,
                                     color: Theme.of(context).colorScheme.primary,
                                     strokeWidth: 2,
                                     strokeColor: Theme.of(context).colorScheme.surface,
                                  ),
                               ),
                               belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                     colors: [
                                        Theme.of(context).colorScheme.primary.withAlphaFactor(0.4),
                                        Theme.of(context).colorScheme.primary.withAlphaFactor(0.0),
                                     ],
                                     begin: Alignment.topCenter,
                                     end: Alignment.bottomCenter,
                                  ),
                               ),
                            ),
                         ],
                         lineTouchData: LineTouchData(
                            enabled: true,
                            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                               return spotIndexes.map((index) {
                                  return TouchedSpotIndicatorData(
                                     FlLine(color: Theme.of(context).colorScheme.primary.withAlphaFactor(0.5), strokeWidth: 2, dashArray: [4, 4]),
                                     FlDotData(
                                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                           radius: 5,
                                           color: Theme.of(context).colorScheme.primary,
                                           strokeWidth: 2,
                                           strokeColor: Theme.of(context).colorScheme.surface,
                                        ),
                                     ),
                                  );
                               }).toList();
                            },
                            touchTooltipData: LineTouchTooltipData(
                               getTooltipColor: (touchedSpot) => Theme.of(context).colorScheme.onSurface,
                               getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) => LineTooltipItem(
                                     formatMoney(
                                        Money(amountMinor: spot.y.toInt(), currency: widget.state.preferences.displayCurrency),
                                        widget.state.preferences.locale,
                                     ),
                                     TextStyle(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold, fontSize: 12),
                                  )).toList();
                               },
                            ),
                         ),
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

class CurrencyValuesHomeWidget extends ConsumerStatefulWidget {
  const CurrencyValuesHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  ConsumerState<CurrencyValuesHomeWidget> createState() =>
      _CurrencyValuesHomeWidgetState();
}

class _CurrencyValuesHomeWidgetState extends ConsumerState<CurrencyValuesHomeWidget> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, double> _ratesToBase = {}; 

  String _baseCurrency = '';
  
  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(CurrencyValuesHomeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.preferences.enabledCurrencies != widget.state.preferences.enabledCurrencies ||
        oldWidget.state.preferences.baseCurrency != widget.state.preferences.baseCurrency ||
        oldWidget.state.exchangeRates != widget.state.exchangeRates) {
      _initData();
    }
  }

  void _initData() {
    _baseCurrency = widget.state.preferences.baseCurrency.toUpperCase();
    final enabled = widget.state.preferences.enabledCurrencies
        .where((c) => c.toUpperCase() != _baseCurrency)
        .toList()..sort();
        
    final allCurrencies = [_baseCurrency, ...enabled];
    
    final defaultCurrency = enabled.isNotEmpty ? enabled.first : _baseCurrency;
    
    final oldKeys = _controllers.keys.toSet();
    for (final c in allCurrencies) {
      if (!_controllers.containsKey(c)) {
         _controllers[c] = TextEditingController(text: c == defaultCurrency ? '1' : '');
      }
    }
    
    for (final c in oldKeys) {
      if (!allCurrencies.contains(c)) {
        _controllers[c]?.dispose();
        _controllers.remove(c);
      }
    }
    
    _ratesToBase.clear();
    _ratesToBase[_baseCurrency] = 1.0;
    for (final c in enabled) {
       final matches = widget.state.exchangeRates
            .where((r) =>
                r.base.toUpperCase() == c &&
                r.quote.toUpperCase() == _baseCurrency &&
                r.rate > 0)
            .toList();
       if (matches.isNotEmpty) {
         matches.sort((a, b) {
            final aDate = a.updatedAt ?? a.asOfDate;
            final bDate = b.updatedAt ?? b.asOfDate;
            return bDate.compareTo(aDate);
         });
         _ratesToBase[c] = matches.first.rate;
       } else {
         _ratesToBase[c] = 0.0;
       }
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onTextChanged(defaultCurrency, _controllers[defaultCurrency]!.text);
    });
  }
  
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
  
  void _onTextChanged(String editedCurrency, String value) {
     final amount = double.tryParse(value) ?? 0.0;
     final editedRate = _ratesToBase[editedCurrency] ?? 0.0;
     if (editedRate <= 0) return;
     
     final amountInBase = amount * editedRate;
     
     for (final entry in _controllers.entries) {
        final c = entry.key;
        if (c == editedCurrency) continue;
        
        final r = _ratesToBase[c] ?? 0.0;
        if (r <= 0) {
           entry.value.text = 'No rate';
        } else {
           final val = amountInBase / r;
           // Format to 1 decimal place to maintain simplicity, then strip trailing zeros
           var formatted = val.toStringAsFixed(1);
           if (formatted.contains('.')) {
              formatted = formatted.replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
           }
           entry.value.text = formatted;
        }
     }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.state.preferences.enabledCurrencies
        .where((c) => c.toUpperCase() != _baseCurrency)
        .toList()..sort();
    final allCurrencies = [_baseCurrency, ...enabled];

    final scheme = Theme.of(context).colorScheme;

    if (enabled.isEmpty) {
      return const HomeWidgetCard(
        title: 'Currency calculator',
        icon: Icons.calculate_outlined,
        child: EmptyState(
          icon: Icons.currency_exchange_outlined,
          title: 'No currencies enabled',
          body: 'Add currencies in the Rates page to calculate them here.',
        ),
      );
    }

    return HomeWidgetCard(
      title: 'Currency calculator',
      subtitle: 'Live conversions',
      icon: Icons.calculate_outlined,
      iconColor: scheme.tertiary,
      actionLabel: 'Rates',
      onAction: () => context.push('/currencies'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in allCurrencies) ...[
             Builder(builder: (context) {
                String? rateSubtitle;
                if (c != _baseCurrency) {
                   final r = _ratesToBase[c] ?? 0.0;
                   if (r > 0) {
                      var formatted = r.toStringAsFixed(1);
                      if (formatted.contains('.')) {
                         formatted = formatted.replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
                      }
                      rateSubtitle = '1 $c = $formatted $_baseCurrency';
                   }
                }
                return _CalculatorRow(
                   currency: c,
                   isBase: c == _baseCurrency,
                   controller: _controllers[c]!,
                   onChanged: (val) => _onTextChanged(c, val),
                   hasRate: (_ratesToBase[c] ?? 0) > 0,
                   rateSubtitle: rateSubtitle,
                );
             }),
             if (c != allCurrencies.last) const SizedBox(height: AppSpacing.sm),
          ]
        ],
      ),
    );
  }
}

class _CalculatorRow extends StatelessWidget {
  const _CalculatorRow({
    required this.currency,
    required this.isBase,
    required this.controller,
    required this.onChanged,
    required this.hasRate,
    this.rateSubtitle,
  });

  final String currency;
  final bool isBase;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool hasRate;
  final String? rateSubtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = getCurrencyInfo(currency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isBase ? scheme.tertiaryContainer.withAlphaFactor(0.3) : scheme.surfaceContainerHighest.withAlphaFactor(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isBase ? scheme.tertiary.withAlphaFactor(0.5) : scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              enabled: hasRate,
              textAlign: TextAlign.left,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hasRate ? '0' : 'No rate',
              ),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: hasRate ? scheme.onSurface : scheme.error,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  info.fullName,
                  style: TextStyle(
                    fontWeight: isBase ? FontWeight.bold : FontWeight.w600, 
                    fontSize: 13,
                    color: isBase ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isBase)
                  Text('Base Currency', style: TextStyle(fontSize: 11, color: scheme.tertiary), textAlign: TextAlign.right)
                else if (rateSubtitle != null && rateSubtitle!.isNotEmpty)
                  Text(rateSubtitle!, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), textAlign: TextAlign.right)
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            isBase ? Icons.account_balance_outlined : Icons.payments_outlined, 
            color: isBase ? scheme.tertiary : scheme.onSurfaceVariant,
            size: 20,
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
                const SizedBox(height: AppSpacing.xxs),
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
              subtitle: _shortDate(next.occurredAt, state.preferences.locale),
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
              subtitle: _shortDate(next.occurredAt, state.preferences.locale),
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
                  '${_shortDate(next.occurredAt, state.preferences.locale)} · ${transactionTypeLabel(next.type)}',
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
    return HomeWidgetCard(
      title: 'Automation & review',
      subtitle: 'Queue, imports, and sources',
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
      subtitle: _monthRangeLabel(DateTime.now(), state.preferences.locale),
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
                    icon: Icons.monetization_on_outlined,
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
        primaryLabel = formatMoney(displayBalance, state.preferences.locale);
        secondaryLabel = formatMoney(nativeBalance, state.preferences.locale);
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
  final balancesMap = accountBalanceMap(state);
  for (final account in state.accounts.where(
    (account) => !account.isArchived,
  )) {
    final balance = _displayAccountBalanceMinor(state, account, balances: balancesMap);
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
    if (transaction.status == 'scheduled' ||
        transaction.status == 'paused' ||
        transaction.status == 'void') {
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

String _monthRangeLabel(DateTime value, String locale) {
  final start = DateTime(value.year, value.month);
  final end = DateTime(value.year, value.month + 1, 0);
  return '${formatLedgerDate(start, locale)} to ${formatLedgerDate(end, locale)}';
}

String _shortDate(DateTime date, String locale) => formatLedgerDate(date, locale);

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
