import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import 'planner_widgets.dart'; // for DashboardCard

// 6. Debt Free Target
class DebtFreeTargetWidget extends ConsumerStatefulWidget {
  const DebtFreeTargetWidget({required this.state, super.key});
  final LedgerState state;

  @override
  ConsumerState<DebtFreeTargetWidget> createState() =>
      _DebtFreeTargetWidgetState();
}

class _DebtFreeTargetWidgetState extends ConsumerState<DebtFreeTargetWidget> {
  double _extraPayment = 0;

  @override
  Widget build(BuildContext context) {
    final activeLoans = widget.state.accounts
        .where((a) => !a.isArchived && a.type == 'loan')
        .toList();

    double totalPrincipal = 0;
    int maxMonthsStandard = 0;
    for (final loan in activeLoans) {
      final proj = loanProjection(widget.state, loan);
      final bal = convertMoneyForDisplay(
        widget.state,
        accountBalance(widget.state, loan),
        widget.state.preferences.displayCurrency,
      ).amountMinor.abs().toDouble();
      totalPrincipal += bal;
      if (proj.monthsRemaining != null &&
          proj.monthsRemaining! > maxMonthsStandard) {
        maxMonthsStandard = proj.monthsRemaining!;
      }
    }

    // Simplistic calculation: if we add extra payment, how many months does it take?
    // We assume current total monthly EMI is totalPrincipal / maxMonthsStandard (roughly).
    // Let's just calculate total standard monthly payment.
    double totalStandardMonthly = 0;
    for (final loan in activeLoans) {
      final proj = loanProjection(widget.state, loan);
      final bal = convertMoneyForDisplay(
        widget.state,
        accountBalance(widget.state, loan),
        widget.state.preferences.displayCurrency,
      ).amountMinor.abs().toDouble();
      if (proj.monthsRemaining != null && proj.monthsRemaining! > 0) {
        totalStandardMonthly += bal / proj.monthsRemaining!;
      }
    }

    int projectedMonths = maxMonthsStandard;
    if (totalStandardMonthly + _extraPayment > 0 && totalPrincipal > 0) {
      projectedMonths =
          (totalPrincipal / (totalStandardMonthly + _extraPayment)).ceil();
    }

    final scheme = Theme.of(context).colorScheme;
    final debtFreeDate = DateTime.now().add(
      Duration(days: projectedMonths * 30),
    );
    final hasDebt = activeLoans.isNotEmpty;

    return DashboardCard(
      onTap: () => context.push('/loans'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.celebration_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Debt Free Target',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasDebt)
            const Text(
              'You are completely debt free!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            )
          else ...[
            Text(
              'Expected date based on EMIs + Extra Payment:',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '${debtFreeDate.month}/${debtFreeDate.year}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'In about $projectedMonths months',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              'Extra Monthly Payment: ${_extraPayment > 0 ? formatMoney(Money(amountMinor: _extraPayment.toInt(), currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale) : 'None'}',
              style: const TextStyle(fontSize: 14),
            ),
            Slider(
              value: _extraPayment.clamp(
                0.0,
                totalPrincipal > 500000 ? totalPrincipal : 500000.0,
              ),
              max: totalPrincipal > 500000 ? totalPrincipal : 500000.0,
              divisions: 100,
              label: formatMoney(
                Money(
                  amountMinor: _extraPayment.toInt(),
                  currency: widget.state.preferences.displayCurrency,
                ),
                widget.state.preferences.locale,
              ),
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
      onTap: () => context.push('/accounts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: scheme.secondary),
              const SizedBox(width: 8),
              const Text(
                'Active Savings Goals',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (goals.isEmpty)
            Text(
              'No active savings goals found.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ...goals.map((g) {
              final bal = convertMoneyForDisplay(
                state,
                accountBalance(state, g),
                state.preferences.displayCurrency,
              ).amountMinor;
              // Mocking a target of 10x current balance for visual progress
              final target = bal > 0 ? bal * 10 : 10000;
              final progress = target > 0
                  ? (bal / target).clamp(0.0, 1.0)
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          g.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
      final cat = tx.categoryId != null
          ? categoryById(state, tx.categoryId!)?.name.toLowerCase() ?? ''
          : '';
      return cat.contains('sub') ||
          cat.contains('stream') ||
          tx.notes?.toLowerCase().contains('sub') == true;
    }).toList();

    for (final s in subs) {
      totalMonthlySubs += convertMoneyForDisplay(
        state,
        s.amount,
        state.preferences.displayCurrency,
      ).amountMinor;
    }

    return DashboardCard(
      onTap: () => context.push('/recurring'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew_rounded, color: scheme.tertiary),
              const SizedBox(width: 8),
              const Text(
                'Subscriptions Watch',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Monthly burn rate on subscriptions:',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(
              Money(
                amountMinor: totalMonthlySubs,
                currency: state.preferences.displayCurrency,
              ),
              state.preferences.locale,
            ),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// 9. Cashflow 30-Day Predictor
class CashflowPredictorWidget extends ConsumerWidget {
  const CashflowPredictorWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    int pastIncome = 0;
    int pastExpense = 0;

    for (final tx in state.transactions) {
      if (tx.status == 'void' ||
          tx.status == 'scheduled' ||
          tx.status == 'paused')
        continue;
      if (tx.occurredAt.isAfter(thirtyDaysAgo) && tx.occurredAt.isBefore(now)) {
        if (incomeTypes.contains(tx.type)) {
          pastIncome += convertMoneyForDisplay(
            state,
            tx.amount,
            state.preferences.displayCurrency,
          ).amountMinor;
        } else if (expenseTypes.contains(tx.type)) {
          pastExpense += convertMoneyForDisplay(
            state,
            tx.amount,
            state.preferences.displayCurrency,
          ).amountMinor;
        }
      }
    }

    final netCashflow = pastIncome - pastExpense;
    final scheme = Theme.of(context).colorScheme;
    final isPositive = netCashflow >= 0;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                '30-Day Predictor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Based on your last 30 days, your predicted net cashflow for the next month is:',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '${isPositive ? '+' : '-'}${formatMoney(Money(amountMinor: netCashflow.abs(), currency: state.preferences.displayCurrency), state.preferences.locale)}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: isPositive ? scheme.primary : scheme.error,
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
    final activeLoans = state.accounts
        .where((a) => !a.isArchived && a.type == 'loan')
        .toList();
    if (activeLoans.isEmpty) return const SizedBox.shrink();

    Account? highestLoan;
    double maxInterest = 0;

    for (final loan in activeLoans) {
      final bal = convertMoneyForDisplay(
        state,
        accountBalance(state, loan),
        state.preferences.displayCurrency,
      ).amountMinor.abs();
      if (bal > maxInterest) {
        maxInterest = bal.toDouble();
        highestLoan = loan;
      }
    }

    if (highestLoan == null || maxInterest == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      onTap: () => context.push('/loans'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, color: scheme.error),
              const SizedBox(width: 8),
              const Text(
                'Debt Priority Alert',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Consider prioritizing extra payments towards your largest loan:',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            highestLoan.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Current Balance: ${formatMoney(Money(amountMinor: maxInterest.toInt(), currency: state.preferences.displayCurrency), state.preferences.locale)}',
            style: TextStyle(
              fontSize: 14,
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
