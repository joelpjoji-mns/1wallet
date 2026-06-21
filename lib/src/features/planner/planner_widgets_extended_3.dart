import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import 'planner_widgets.dart'; // for DashboardCard

// 11. Planned vs Actual
class PlannedVsActualWidget extends ConsumerWidget {
  const PlannedVsActualWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    int actualExp = 0;
    int plannedExp = 0;

    for (final tx in state.transactions) {
      if (tx.status == 'void' || tx.status == 'scheduled' || tx.status == 'paused') continue;
      if (expenseTypes.contains(tx.type) && tx.occurredAt.year == now.year && tx.occurredAt.month == now.month) {
        actualExp += tx.amount.amountMinor;
      }
    }

    for (final tx in scheduledTransactions(state)) {
      if (expenseTypes.contains(tx.type) && tx.occurredAt.year == now.year && tx.occurredAt.month == now.month) {
        plannedExp += tx.amount.amountMinor;
      }
    }
    plannedExp += actualExp; // total planned for the month includes what was already spent

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Planned vs Actual (This Month)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildBar(context, 'Actual Spending', actualExp, scheme.primary),
          const SizedBox(height: 12),
          _buildBar(context, 'Total Planned', plannedExp, scheme.outline),
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context, String label, int amount, Color color) {
    return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
          Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(formatMoney(Money(amountMinor: amount, currency: state.preferences.displayCurrency), state.preferences.locale)),
             ],
          ),
          const SizedBox(height: 4),
          Container(
             height: 12,
             width: double.infinity,
             decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
             child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                // mock max as 10000 for relative widths if planned is 0
                widthFactor: amount > 0 ? (amount / 1000000).clamp(0.1, 1.0) : 0, 
                child: Container(
                   decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                ),
             ),
          ),
       ],
    );
  }
}

// 12. Tax Buffer Predictor
class TaxBufferPredictorWidget extends ConsumerWidget {
  const TaxBufferPredictorWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    int ytdIncome = 0;
    
    for (final tx in state.transactions) {
      if (tx.status == 'void' || tx.status == 'scheduled') continue;
      if (incomeTypes.contains(tx.type) && tx.occurredAt.year == now.year) {
        ytdIncome += tx.amount.amountMinor;
      }
    }

    // Rough guess: 20% effective tax rate on gross income
    final estimatedTax = (ytdIncome * 0.20).toInt();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_rounded, color: scheme.error),
              const SizedBox(width: 8),
              const Text('Tax Buffer Predictor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Estimated tax liability based on YTD income (assuming ~20% rate):', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            formatMoney(Money(amountMinor: estimatedTax, currency: state.preferences.displayCurrency), state.preferences.locale),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// 13. Investment Target
class InvestmentTargetWidget extends ConsumerWidget {
  const InvestmentTargetWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    int ytdInvested = 0;

    for (final tx in state.transactions) {
      if (tx.status == 'void' || tx.status == 'scheduled') continue;
      if (tx.occurredAt.year == now.year) {
        final cat = tx.categoryId != null ? categoryById(state, tx.categoryId!)?.name.toLowerCase() ?? '' : '';
        if (cat.contains('invest') || cat.contains('stock') || cat.contains('crypto')) {
          ytdInvested += tx.amount.amountMinor;
        }
      }
    }

    final annualTarget = 600000; // Mock target: e.g. $6000 or similar
    final progress = (ytdInvested / annualTarget).clamp(0.0, 1.0);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: scheme.secondary),
              const SizedBox(width: 8),
              const Text('Annual Investment Target', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatMoney(Money(amountMinor: ytdInvested, currency: state.preferences.displayCurrency), state.preferences.locale), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('/ ${formatMoney(Money(amountMinor: annualTarget, currency: state.preferences.displayCurrency), state.preferences.locale)}', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            color: scheme.secondary,
            backgroundColor: scheme.surfaceContainerHighest,
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
    );
  }
}

// 14. Annual Sinking Funds
class AnnualSinkingFundsWidget extends ConsumerWidget {
  const AnnualSinkingFundsWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_rounded, color: scheme.tertiary),
              const SizedBox(width: 8),
              const Text('Sinking Funds (Annual Bills)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildFund(context, 'Car Insurance', 0.5),
          const SizedBox(height: 12),
          _buildFund(context, 'Property Tax', 0.8),
          const SizedBox(height: 12),
          _buildFund(context, 'Holiday Gifts', 0.2),
        ],
      ),
    );
  }
  
  Widget _buildFund(BuildContext context, String name, double progress) {
     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                 Text('${(progress * 100).toInt()}% funded'),
              ],
           ),
           const SizedBox(height: 4),
           LinearProgressIndicator(
              value: progress,
              color: Theme.of(context).colorScheme.tertiary,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
           ),
        ],
     );
  }
}

// 15. Net Worth Predictor
class NetWorthPredictorWidget extends ConsumerWidget {
  const NetWorthPredictorWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    
    int currentNetWorth = 0;
    final balances = accountBalanceMap(state);
    for (final acc in state.accounts) {
       final bal = accountBalanceFromMap(balances, acc).amountMinor;
       if (acc.type == 'loan' || acc.type == 'card') {
          currentNetWorth -= bal.abs();
       } else {
          currentNetWorth += bal;
       }
    }
    
    // Simplistic prediction: net worth grows by 5% over the year
    final projectedNetWorth = (currentNetWorth * 1.05).toInt();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Net Worth Predictor (1 Yr)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text('Current', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                     Text(formatMoney(Money(amountMinor: currentNetWorth, currency: state.preferences.displayCurrency), state.preferences.locale), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
               ),
               const Icon(Icons.arrow_forward_rounded),
               Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                     Text('Projected', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                     Text(formatMoney(Money(amountMinor: projectedNetWorth, currency: state.preferences.displayCurrency), state.preferences.locale), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.primary)),
                  ],
               ),
            ],
          ),
        ],
      ),
    );
  }
}
