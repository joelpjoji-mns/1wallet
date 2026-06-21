import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import '../transactions/transaction_row.dart';
import 'planner_widgets.dart'; // for DashboardCard
import 'planner_widgets.dart'; // for DashboardCard

// 1. Daily Spending Limit
class DailySpendingLimitWidget extends ConsumerWidget {
  const DailySpendingLimitWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final daysRemaining = daysInMonth - now.day + 1;

    int totalIncome = 0;
    int totalExpense = 0;

    for (final tx in state.transactions) {
      if (tx.status == 'void' || tx.status == 'scheduled' || tx.status == 'paused') continue;
      if (tx.occurredAt.year == now.year && tx.occurredAt.month == now.month) {
        if (incomeTypes.contains(tx.type)) {
          totalIncome += tx.amount.amountMinor;
        } else if (expenseTypes.contains(tx.type)) {
          totalExpense += tx.amount.amountMinor;
        }
      }
    }

    final remainingBudget = totalIncome - totalExpense;
    final dailyLimit = remainingBudget > 0 ? remainingBudget ~/ daysRemaining : 0;
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Daily Spending Limit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Safe to spend per day for the rest of the month', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text(
            formatMoney(Money(amountMinor: dailyLimit, currency: state.preferences.displayCurrency), state.preferences.locale),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: dailyLimit > 0 ? scheme.primary : scheme.error),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: remainingBudget > 0 ? (totalExpense / totalIncome).clamp(0.0, 1.0) : 1.0,
            color: remainingBudget > 0 ? scheme.primary : scheme.error,
            backgroundColor: scheme.surfaceContainerHighest,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

// 2. Upcoming Planned Bills
class UpcomingPlannedBillsWidget extends ConsumerWidget {
  const UpcomingPlannedBillsWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));
    
    final upcoming = scheduledTransactions(state).where((tx) {
      return expenseTypes.contains(tx.type) && tx.occurredAt.isAfter(now) && tx.occurredAt.isBefore(nextWeek);
    }).toList();
    
    upcoming.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: scheme.error),
              const SizedBox(width: 8),
              const Text('Upcoming Bills (7 Days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (upcoming.isEmpty)
            Text('No bills due in the next 7 days!', style: TextStyle(color: scheme.primary))
          else
            ...upcoming.map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TransactionRow(state: state, transaction: tx, onTap: () => context.push('/transaction/${tx.id}')),
            )),
        ],
      ),
    );
  }
}

// 3. Upcoming Income
class UpcomingIncomeWidget extends ConsumerWidget {
  const UpcomingIncomeWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final nextMonth = now.add(const Duration(days: 30));
    
    final upcoming = scheduledTransactions(state).where((tx) {
      return incomeTypes.contains(tx.type) && tx.occurredAt.isAfter(now) && tx.occurredAt.isBefore(nextMonth);
    }).toList();
    
    upcoming.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Upcoming Income', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (upcoming.isEmpty)
            Text('No income scheduled for the next 30 days.', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            ...upcoming.map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TransactionRow(state: state, transaction: tx, onTap: () => context.push('/transaction/${tx.id}')),
            )),
        ],
      ),
    );
  }
}

// 4. 50/30/20 Budget Health
class BudgetHealth503020Widget extends ConsumerWidget {
  const BudgetHealth503020Widget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    int totalIncome = 0;
    int totalNeeds = 0; // Categories marked as needs (simulation: just take 60% of expenses for now, or specific categories if available)
    int totalWants = 0;
    
    for (final tx in state.transactions) {
      if (tx.status == 'void' || tx.status == 'scheduled' || tx.status == 'paused') continue;
      if (tx.occurredAt.year == now.year && tx.occurredAt.month == now.month) {
        if (incomeTypes.contains(tx.type)) totalIncome += tx.amount.amountMinor;
        if (expenseTypes.contains(tx.type)) {
          // Simplistic logic: assume groceries/bills are needs, dining/entertainment are wants
          final catName = tx.categoryId != null ? categoryById(state, tx.categoryId!)?.name.toLowerCase() ?? '' : '';
          if (catName.contains('grocer') || catName.contains('bill') || catName.contains('rent') || catName.contains('utilit')) {
            totalNeeds += tx.amount.amountMinor;
          } else {
            totalWants += tx.amount.amountMinor;
          }
        }
      }
    }

    final saved = totalIncome - totalNeeds - totalWants;
    final scheme = Theme.of(context).colorScheme;

    double needsPct = totalIncome > 0 ? totalNeeds / totalIncome : 0;
    double wantsPct = totalIncome > 0 ? totalWants / totalIncome : 0;
    double savedPct = totalIncome > 0 ? saved / totalIncome : 0;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: scheme.tertiary),
              const SizedBox(width: 8),
              const Text('50/30/20 Budget Health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildBudgetBar(context, 'Needs (50%)', needsPct, 0.50, scheme.primary),
              const SizedBox(width: 8),
              _buildBudgetBar(context, 'Wants (30%)', wantsPct, 0.30, scheme.secondary),
              const SizedBox(width: 8),
              _buildBudgetBar(context, 'Savings (20%)', savedPct, 0.20, scheme.tertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetBar(BuildContext context, String label, double actual, double target, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: actual.clamp(0.0, 1.0),
            color: actual > target && label != 'Savings (20%)' ? Theme.of(context).colorScheme.error : color,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            minHeight: 12,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text('${(actual * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

// 5. Emergency Fund Health
class EmergencyFundHealthWidget extends ConsumerWidget {
  const EmergencyFundHealthWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Target is 3x monthly average expenses
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 90));
    int totalExp = 0;
    for (final tx in state.transactions) {
      if (tx.status == 'void' || tx.status == 'scheduled') continue;
      if (expenseTypes.contains(tx.type) && tx.occurredAt.isAfter(start)) {
        totalExp += tx.amount.amountMinor;
      }
    }
    final avgMonthlyExp = totalExp ~/ 3;
    final target = avgMonthlyExp * 3;

    int totalCash = 0;
    final balances = accountBalanceMap(state);
    for (final acc in state.accounts) {
      if (acc.type == 'cash' || acc.type == 'bank') {
        totalCash += accountBalanceFromMap(balances, acc).amountMinor;
      }
    }

    final progress = target > 0 ? (totalCash / target) : 0.0;
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Emergency Fund', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Target: 3 months of expenses', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatMoney(Money(amountMinor: totalCash, currency: state.preferences.displayCurrency), state.preferences.locale), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('/ ${formatMoney(Money(amountMinor: target, currency: state.preferences.displayCurrency), state.preferences.locale)}', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: scheme.primary,
            backgroundColor: scheme.surfaceContainerHighest,
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
    );
  }
}
