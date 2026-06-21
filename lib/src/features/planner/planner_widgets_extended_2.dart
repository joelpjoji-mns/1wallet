import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import 'planner_widgets.dart'; // for DashboardCard

// 6. Debt Free Target
class DebtFreeTargetWidget extends ConsumerWidget {
  const DebtFreeTargetWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLoans = state.accounts.where((a) => !a.isArchived && a.type == 'loan').toList();
    int maxMonths = 0;
    for (final loan in activeLoans) {
      final proj = loanProjection(state, loan);
      if (proj.monthsRemaining != null && proj.monthsRemaining! > maxMonths) {
        maxMonths = proj.monthsRemaining!;
      }
    }
    
    final scheme = Theme.of(context).colorScheme;
    final debtFreeDate = DateTime.now().add(Duration(days: maxMonths * 30));
    final hasDebt = activeLoans.isNotEmpty;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.celebration_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Debt Free Target', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasDebt)
            const Text('You are completely debt free!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
          else ...[
            Text('Expected date based on current EMIs:', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              '${debtFreeDate.month}/${debtFreeDate.year}',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: scheme.primary),
            ),
            const SizedBox(height: 4),
            Text('In about $maxMonths months', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

// 7. Active Savings Goals
class ActiveSavingsGoalsWidget extends ConsumerWidget {
  const ActiveSavingsGoalsWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final goals = state.accounts.where((a) => a.type == 'savings' && a.groupId != null).toList();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: scheme.secondary),
              const SizedBox(width: 8),
              const Text('Active Savings Goals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (goals.isEmpty)
            Text('No active savings goals found.', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            ...goals.map((g) {
               final bal = accountBalance(state, g).amountMinor;
               // Mocking a target of 10x current balance for visual progress
               final target = bal > 0 ? bal * 10 : 10000;
               final progress = target > 0 ? (bal / target).clamp(0.0, 1.0) : 0.0;
               return Padding(
                 padding: const EdgeInsets.only(bottom: 12),
                 child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                             Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                             Text('${(progress * 100).toInt()}%'),
                          ],
                       ),
                       const SizedBox(height: 4),
                       LinearProgressIndicator(
                          value: progress,
                          color: scheme.secondary,
                          backgroundColor: scheme.surfaceContainerHighest,
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

// 8. Subscriptions Watch
class SubscriptionsWatchWidget extends ConsumerWidget {
  const SubscriptionsWatchWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    int totalMonthlySubs = 0;
    final subs = scheduledTransactions(state).where((tx) {
       if (!expenseTypes.contains(tx.type)) return false;
       final cat = tx.categoryId != null ? categoryById(state, tx.categoryId!)?.name.toLowerCase() ?? '' : '';
       return cat.contains('sub') || cat.contains('stream') || tx.notes?.toLowerCase().contains('sub') == true;
    }).toList();

    for (final s in subs) {
       totalMonthlySubs += s.amount.amountMinor;
    }

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew_rounded, color: scheme.tertiary),
              const SizedBox(width: 8),
              const Text('Subscriptions Watch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Monthly burn rate on subscriptions:', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            formatMoney(Money(amountMinor: totalMonthlySubs, currency: state.preferences.displayCurrency), state.preferences.locale),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// 9. Cashflow 30-Day Predictor
class Cashflow30DayPredictorWidget extends ConsumerWidget {
  const Cashflow30DayPredictorWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final end = now.add(const Duration(days: 30));
    int expectedIncome = 0;
    int expectedExpense = 0;

    for (final tx in scheduledTransactions(state)) {
      if (tx.occurredAt.isAfter(now) && tx.occurredAt.isBefore(end)) {
        if (incomeTypes.contains(tx.type)) expectedIncome += tx.amount.amountMinor;
        if (expenseTypes.contains(tx.type)) expectedExpense += tx.amount.amountMinor;
      }
    }

    final net = expectedIncome - expectedExpense;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: net >= 0 ? scheme.primary : scheme.error),
              const SizedBox(width: 8),
              const Text('30-Day Cashflow Predictor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expected In', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text(formatMoney(Money(amountMinor: expectedIncome, currency: state.preferences.displayCurrency), state.preferences.locale), style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Expected Out', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text(formatMoney(Money(amountMinor: expectedExpense, currency: state.preferences.displayCurrency), state.preferences.locale), style: TextStyle(fontWeight: FontWeight.bold, color: scheme.error)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
             padding: const EdgeInsets.all(12),
             decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
             child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text('Net Predicted Cashflow', style: TextStyle(fontWeight: FontWeight.bold)),
                   Text(formatMoney(Money(amountMinor: net, currency: state.preferences.displayCurrency), state.preferences.locale), style: TextStyle(fontWeight: FontWeight.bold, color: net >= 0 ? scheme.primary : scheme.error)),
                ],
             ),
          ),
        ],
      ),
    );
  }
}

// 10. High-Interest Alert
class HighInterestAlertWidget extends ConsumerWidget {
  const HighInterestAlertWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final highInterestLoans = state.accounts.where((a) {
       if (a.isArchived || a.type != 'loan') return false;
       final rate = a.loanDetails?.interestRatePercent ?? 0;
       return rate > 10.0;
    }).toList();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error),
              const SizedBox(width: 8),
              const Text('High-Interest Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (highInterestLoans.isEmpty)
             const Text('Great job! You have no debts with an interest rate above 10%.')
          else
             ...highInterestLoans.map((a) {
                return Container(
                   padding: const EdgeInsets.all(12),
                   margin: const EdgeInsets.only(bottom: 8),
                   decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                   ),
                   child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Text(a.name, style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold)),
                         Text('${a.loanDetails?.interestRatePercent}% APR', style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold)),
                      ],
                   ),
                );
             }),
        ],
      ),
    );
  }
}
