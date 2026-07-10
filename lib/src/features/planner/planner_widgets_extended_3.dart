import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart'; // For withAlphaFactor
import '../../ledger/ledger_selectors.dart';
import '../../widgets/privacy_text.dart';
import 'planner_widgets.dart'; // for DashboardCard

// 11. Planned vs Actual

// 12. Tax Buffer Predictor

// 13. Investment Target

// 14. Annual Sinking Funds

// 15. Net Worth Snapshot
class NetWorthSnapshotWidget extends ConsumerWidget {
  const NetWorthSnapshotWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worth = netWorth(state);
    final assets = worth.assets.amountMinor;
    final liabilities = worth.liabilities.amountMinor.abs();
    final total = assets - liabilities;
    final scheme = Theme.of(context).colorScheme;
    final assetsShare = (assets + liabilities) > 0
        ? assets / (assets + liabilities)
        : 1.0;

    return DashboardCard(
      onTap: () => context.push('/accounts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Net Worth',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Assets minus liabilities across all accounts',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          PrivacyText(
            formatMoney(
              Money(amountMinor: total, currency: worth.total.currency),
              state.preferences.locale,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: total >= 0 ? scheme.primary : scheme.error,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: assetsShare.clamp(0.0, 1.0),
              color: scheme.primary,
              backgroundColor: scheme.error.withAlphaFactor(0.4),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: PrivacyText(
                  'Assets ${formatMoney(Money(amountMinor: assets, currency: worth.total.currency), state.preferences.locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: PrivacyText(
                  'Liabilities ${formatMoney(Money(amountMinor: liabilities, currency: worth.total.currency), state.preferences.locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 16. Savings Rate Trend
class SavingsRateTrendWidget extends ConsumerWidget {
  const SavingsRateTrendWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = cashFlowThisMonth(state);
    final scheme = Theme.of(context).colorScheme;
    // 20% savings rate is a commonly recommended target.
    const targetRate = 0.20;
    final ratePct = (flow.savingsRate * 100).clamp(-999.0, 999.0);
    final isHealthy = flow.savingsRate >= targetRate;

    return DashboardCard(
      onTap: () => context.push('/budgets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined, color: scheme.tertiary),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Savings Rate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Share of this month\'s income you kept',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${ratePct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: isHealthy ? scheme.primary : scheme.error,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'target ${(targetRate * 100).round()}%',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: flow.savingsRate.clamp(0.0, 1.0),
            color: isHealthy ? scheme.primary : scheme.error,
            backgroundColor: scheme.surfaceContainerHighest,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: PrivacyText(
                  'Income ${formatMoney(Money(amountMinor: flow.incomeMinor, currency: flow.currency), state.preferences.locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: PrivacyText(
                  'Net ${formatMoney(Money(amountMinor: flow.netMinor, currency: flow.currency), state.preferences.locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 17. Budget Health Overview
class BudgetHealthOverviewWidget extends ConsumerWidget {
  const BudgetHealthOverviewWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final budgets = state.budgets;

    return DashboardCard(
      onTap: () => context.push('/budgets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.donut_large_rounded, color: scheme.secondary),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Budget Health',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (budgets.isEmpty)
            Text(
              'No budgets set up yet.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ...budgets.map((budget) {
              final spent = budgetSpent(state, budget).amountMinor;
              final limit = budget.amount.amountMinor;
              final pct = limit > 0 ? spent / limit : 0.0;
              final overBudget = limit > 0 && spent > limit;
              final barColor = overBudget
                  ? scheme.error
                  : (pct >= 0.8 ? Colors.orange : scheme.secondary);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            budget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: PrivacyText(
                            '${formatMoney(Money(amountMinor: spent, currency: budget.amount.currency), state.preferences.locale)} / ${formatMoney(budget.amount, state.preferences.locale)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: overBudget
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      color: barColor,
                      backgroundColor: scheme.surfaceContainerHighest,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
