import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import 'planner_widgets.dart'; // for DashboardCard

// 6. Debt Free Target
class DebtFreeTargetWidget extends ConsumerStatefulWidget {
  const DebtFreeTargetWidget({required this.state, super.key});
  final LedgerState state;

  @override
  ConsumerState<DebtFreeTargetWidget> createState() => _DebtFreeTargetWidgetState();
}

class _DebtFreeTargetWidgetState extends ConsumerState<DebtFreeTargetWidget> {
  double _extraPayment = 0;

  @override
  Widget build(BuildContext context) {
    final activeLoans = widget.state.accounts.where((a) => !a.isArchived && a.type == 'loan').toList();
    
    double totalPrincipal = 0;
    int maxMonthsStandard = 0;
    for (final loan in activeLoans) {
      final proj = loanProjection(widget.state, loan);
      totalPrincipal += proj.principalRemaining ?? 0;
      if (proj.monthsRemaining != null && proj.monthsRemaining! > maxMonthsStandard) {
        maxMonthsStandard = proj.monthsRemaining!;
      }
    }
    
    // Simplistic calculation: if we add extra payment, how many months does it take?
    // We assume current total monthly EMI is totalPrincipal / maxMonthsStandard (roughly).
    // Let's just calculate total standard monthly payment.
    double totalStandardMonthly = 0;
    for (final loan in activeLoans) {
      final proj = loanProjection(widget.state, loan);
      if (proj.monthsRemaining != null && proj.monthsRemaining! > 0) {
        totalStandardMonthly += (proj.principalRemaining ?? 0) / proj.monthsRemaining!;
      }
    }
    
    int projectedMonths = maxMonthsStandard;
    if (totalStandardMonthly + _extraPayment > 0 && totalPrincipal > 0) {
       projectedMonths = (totalPrincipal / (totalStandardMonthly + _extraPayment)).ceil();
    }

    final scheme = Theme.of(context).colorScheme;
    final debtFreeDate = DateTime.now().add(Duration(days: projectedMonths * 30));
    final hasDebt = activeLoans.isNotEmpty;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.celebration_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Flexible(child: Text('Debt Free Target', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasDebt)
            const Text('You are completely debt free!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
          else ...[
            Text('Expected date based on EMIs + Extra Payment:', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              '${debtFreeDate.month}/${debtFreeDate.year}',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: scheme.primary),
            ),
            const SizedBox(height: 4),
            Text('In about $projectedMonths months', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('Extra Monthly Payment: ${_extraPayment > 0 ? formatMoney(Money(amountMinor: _extraPayment.toInt(), currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale) : 'None'}', style: const TextStyle(fontSize: 14)),
            Slider(
              value: _extraPayment,
              max: 500000, // 5000.00 assuming minor units
              divisions: 100,
              label: formatMoney(Money(amountMinor: _extraPayment.toInt(), currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale),
              onChanged: (val) {
                setState(() {
                  _extraPayment = val;
                });
              },
            ),
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
    final goals = state.accounts.where((a) => a.type == 'savings').toList();

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


// 10. High-Interest Alert

