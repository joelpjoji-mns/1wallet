import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/privacy_text.dart';
import 'home_widget_card.dart';

/// Net worth = assets minus liabilities, with a proportional split bar.
class NetWorthHomeWidget extends StatelessWidget {
  const NetWorthHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = state.preferences.locale;
    final worth = netWorth(state);
    final assets = worth.assets.amountMinor;
    final liabilities = worth.liabilities.amountMinor.abs();
    final denom = assets + liabilities;
    final assetFlex = denom > 0 ? (assets / denom * 100).round().clamp(0, 100) : 100;
    final liabFlex = 100 - assetFlex;
    final positiveColor = const Color(0xff22c55e);

    return HomeWidgetCard(
      title: 'Net worth',
      subtitle: 'What you own minus what you owe',
      icon: Icons.account_balance_outlined,
      actionLabel: 'Trend',
      onAction: () => context.push('/balance-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrivacyText(
            formatMoney(worth.total, locale),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: worth.total.amountMinor >= 0 ? scheme.primary : scheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (denom > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Row(
                children: [
                  if (assetFlex > 0)
                    Expanded(
                      flex: assetFlex,
                      child: Container(height: 8, color: positiveColor),
                    ),
                  if (liabFlex > 0)
                    Expanded(
                      flex: liabFlex,
                      child: Container(
                        height: 8,
                        color: scheme.error.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _LabeledAmount(
                  label: 'Assets',
                  money: worth.assets,
                  locale: locale,
                  color: positiveColor,
                ),
              ),
              Expanded(
                child: _LabeledAmount(
                  label: 'You owe',
                  money: Money(
                    amountMinor: liabilities,
                    currency: worth.liabilities.currency,
                  ),
                  locale: locale,
                  color: scheme.error,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Income vs expense for the current month, plus net and savings rate.
class CashFlowHomeWidget extends StatelessWidget {
  const CashFlowHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = state.preferences.locale;
    final flow = cashFlowThisMonth(state);
    final positiveColor = const Color(0xff22c55e);
    final maxSide = [
      flow.incomeMinor,
      flow.expenseMinor,
    ].reduce((a, b) => a > b ? a : b);
    final incomeFraction = maxSide > 0 ? flow.incomeMinor / maxSide : 0.0;
    final expenseFraction = maxSide > 0 ? flow.expenseMinor / maxSide : 0.0;
    final savingsPct = (flow.savingsRate * 100).round();

    return HomeWidgetCard(
      title: 'Cash flow',
      subtitle: 'This month',
      icon: Icons.swap_vert_rounded,
      actionLabel: 'Trend',
      onAction: () => context.push('/balance-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FlowBar(
            label: 'Income',
            money: Money(amountMinor: flow.incomeMinor, currency: flow.currency),
            locale: locale,
            fraction: incomeFraction,
            color: positiveColor,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FlowBar(
            label: 'Expense',
            money: Money(amountMinor: flow.expenseMinor, currency: flow.currency),
            locale: locale,
            fraction: expenseFraction,
            color: scheme.error,
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Net',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    PrivacyText(
                      formatMoney(
                        Money(amountMinor: flow.netMinor, currency: flow.currency),
                        locale,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: flow.netMinor >= 0 ? positiveColor : scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Savings rate',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    flow.incomeMinor > 0 ? '$savingsPct%' : '—',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: savingsPct >= 20
                          ? positiveColor
                          : savingsPct >= 0
                          ? scheme.primary
                          : scheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A composite 0–100 financial-health score with a gauge and signal chips.
class FinancialHealthHomeWidget extends StatelessWidget {
  const FinancialHealthHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final health = financialHealthScore(state);
    final color = health.score >= 80
        ? const Color(0xff22c55e)
        : health.score >= 60
        ? scheme.primary
        : health.score >= 40
        ? const Color(0xfff59e0b)
        : scheme.error;

    return HomeWidgetCard(
      title: 'Financial health',
      subtitle: health.grade,
      icon: Icons.favorite_rounded,
      iconColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${health.score}',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: color,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 2),
                child: Text(
                  '/100',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: (health.score / 100).clamp(0.0, 1.0),
              minHeight: 8,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SignalChip(
                label: 'Savings ${(health.savingsRate * 100).round()}%',
                good: health.savingsRate >= 0.2,
              ),
              _SignalChip(
                label: 'Emergency ${health.emergencyMonths.toStringAsFixed(1)}mo',
                good: health.emergencyMonths >= 3,
              ),
              _SignalChip(
                label: 'Debt ${(health.debtRatio * 100).round()}%',
                good: health.debtRatio <= 0.4,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Current-month spending compared to last month, with a delta indicator.
class MonthComparisonHomeWidget extends StatelessWidget {
  const MonthComparisonHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = state.preferences.locale;
    final cmp = monthlySpendingComparison(state);
    final ratio = cmp.changeRatio;
    final up = ratio != null && ratio > 0;
    final deltaColor = ratio == null
        ? scheme.onSurfaceVariant
        : up
        ? scheme.error
        : const Color(0xff22c55e);

    return HomeWidgetCard(
      title: 'Spending vs last month',
      subtitle: 'How this month compares',
      icon: Icons.calendar_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: PrivacyText(
                  formatMoney(
                    Money(
                      amountMinor: cmp.thisMonthMinor,
                      currency: cmp.currency,
                    ),
                    locale,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              if (ratio != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 16,
                        color: deltaColor,
                      ),
                      Text(
                        '${(ratio.abs() * 100).round()}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: deltaColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ratio == null
                ? 'No spending recorded last month yet.'
                : up
                ? 'You are spending more than last month.'
                : 'You are spending less than last month. Nice!',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Last month: ',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              PrivacyText(
                formatMoney(
                  Money(
                    amountMinor: cmp.lastMonthMinor,
                    currency: cmp.currency,
                  ),
                  locale,
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A GitHub-style heatmap of daily spending over the last ~13 weeks.
class SpendingHeatmapHomeWidget extends StatelessWidget {
  const SpendingHeatmapHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final series = dailySpendingSeries(state, days: 91);
    final maxSpend = series.fold<int>(0, (m, e) => e.spentMinor > m ? e.spentMinor : m);
    // Group into weeks (columns) of 7 days (rows), oldest week first.
    final weeks = <List<({DateTime date, int spentMinor})>>[];
    for (var i = 0; i < series.length; i += 7) {
      weeks.add(series.sublist(i, (i + 7).clamp(0, series.length)));
    }

    return HomeWidgetCard(
      title: 'Spending heatmap',
      subtitle: 'Daily spend over the last 13 weeks',
      icon: Icons.grid_view_rounded,
      iconColor: scheme.error,
      child: maxSpend == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No spending in the last 13 weeks.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final week in weeks) ...[
                      Column(
                        children: [
                          for (final day in week)
                            _HeatCell(
                              intensity: maxSpend > 0
                                  ? day.spentMinor / maxSpend
                                  : 0.0,
                              color: scheme.error,
                              surface: scheme.surfaceContainerHighest,
                            ),
                        ],
                      ),
                      const SizedBox(width: 3),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Less',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    for (final level in [0.15, 0.4, 0.7, 1.0])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: _HeatCell(
                          intensity: level,
                          color: scheme.error,
                          surface: scheme.surfaceContainerHighest,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      'More',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _LabeledAmount extends StatelessWidget {
  const _LabeledAmount({
    required this.label,
    required this.money,
    required this.locale,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final Money money;
  final String locale;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        PrivacyText(
          formatMoney(money, locale),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

class _FlowBar extends StatelessWidget {
  const _FlowBar({
    required this.label,
    required this.money,
    required this.locale,
    required this.fraction,
    required this.color,
  });

  final String label;
  final Money money;
  final String locale;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            PrivacyText(
              formatMoney(money, locale),
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label, required this.good});

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = good ? const Color(0xff22c55e) : const Color(0xfff59e0b);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            good ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.intensity,
    required this.color,
    required this.surface,
  });

  final double intensity;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final clamped = intensity.clamp(0.0, 1.0);
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: clamped <= 0
            ? surface
            : Color.lerp(surface, color, 0.2 + clamped * 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
