import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import '../../design/tokens.dart'; // For AppSpacing
import '../../widgets/privacy_text.dart';
import '../transactions/transaction_row.dart';
import 'planner_widgets.dart'; // for DashboardCard
import 'planner_providers.dart';

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
      if (tx.status == 'void' ||
          tx.status == 'scheduled' ||
          tx.status == 'paused' ||
          tx.isExcludedFromReports)
        continue;
      if (tx.occurredAt.year == now.year && tx.occurredAt.month == now.month) {
        if (incomeTypes.contains(tx.type)) {
          totalIncome += convertMoneyForDisplay(
            state,
            tx.amount,
            state.preferences.displayCurrency,
          ).amountMinor;
        } else if (expenseTypes.contains(tx.type)) {
          totalExpense += convertMoneyForDisplay(
            state,
            tx.amount,
            state.preferences.displayCurrency,
          ).amountMinor;
        }
      }
    }

    final remainingBudget = totalIncome - totalExpense;
    final dailyLimit = remainingBudget > 0
        ? remainingBudget ~/ daysRemaining
        : 0;
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      onTap: () => context.push('/budgets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Daily Spending Limit',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Safe to spend per day for the rest of the month',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          PrivacyText(
            formatMoney(
              Money(
                amountMinor: dailyLimit,
                currency: state.preferences.displayCurrency,
              ),
              state.preferences.locale,
            ),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: dailyLimit > 0 ? scheme.primary : scheme.error,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (remainingBudget > 0 && totalIncome > 0)
                ? (totalExpense / totalIncome).clamp(0.0, 1.0)
                : 1.0,
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

// 3. Upcoming Income
class UpcomingIncomeWidget extends ConsumerWidget {
  const UpcomingIncomeWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final nextMonth = now.add(const Duration(days: 30));

    final upcoming = scheduledTransactions(state).where((tx) {
      return incomeTypes.contains(tx.type) &&
          tx.occurredAt.isAfter(now) &&
          tx.occurredAt.isBefore(nextMonth);
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
              const Text(
                'Upcoming Income',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (upcoming.isEmpty)
            Text(
              'No income scheduled for the next 30 days.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ...upcoming.map(
              (tx) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TransactionRow(
                  state: state,
                  transaction: tx,
                  onTap: () => context.push('/transaction/${tx.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 4. 50/30/20 Budget Health
class BudgetHealth503020Widget extends ConsumerWidget {
  const BudgetHealth503020Widget({required this.state, super.key});
  final LedgerState state;

  void _showRecords(
    BuildContext context,
    String title,
    List<TransactionRecord> records,
  ) {
    if (records.isEmpty) return;
    records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final transaction in records) ...[
                TransactionRow(
                  state: state,
                  transaction: transaction,
                  onTap: () => context.push('/transaction/${transaction.id}'),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(budgetHealthProvider);

    final totalIncome = data.totalIncome;
    final totalNeeds = data.totalNeeds;
    final totalWants = data.totalWants;

    final saved = totalIncome - totalNeeds - totalWants;
    final scheme = Theme.of(context).colorScheme;

    double needsPct = totalIncome > 0 ? totalNeeds / totalIncome : 0;
    double wantsPct = totalIncome > 0 ? totalWants / totalIncome : 0;
    double savedPct = totalIncome > 0 ? saved / totalIncome : 0;

    return DashboardCard(
      onTap: () => context.push('/budgets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: scheme.tertiary),
              const SizedBox(width: 8),
              const Text(
                '50/30/20 Budget Health',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildBudgetBar(
                context,
                'Needs (50%)',
                needsPct,
                0.50,
                scheme.primary,
                data.needsRecords,
              ),
              const SizedBox(width: 8),
              _buildBudgetBar(
                context,
                'Wants (30%)',
                wantsPct,
                0.30,
                scheme.secondary,
                data.wantsRecords,
              ),
              const SizedBox(width: 8),
              _buildBudgetBar(
                context,
                'Savings (20%)',
                savedPct,
                0.20,
                scheme.tertiary,
                [],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetBar(
    BuildContext context,
    String label,
    double actual,
    double target,
    Color color,
    List<TransactionRecord> records,
  ) {
    return Expanded(
      child: InkWell(
        onTap: records.isNotEmpty
            ? () => _showRecords(context, label, records)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: actual.clamp(0.0, 1.0),
                color: actual > target && label != 'Savings (20%)'
                    ? Theme.of(context).colorScheme.error
                    : color,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                minHeight: 12,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 4),
              Text(
                '${(actual * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
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
    final data = ref.watch(emergencyFundProvider);
    final target = data.target;
    final totalCash = data.totalCash;

    final progress = target > 0 ? (totalCash / target) : 0.0;
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      onTap: () => context.push('/accounts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Emergency Fund',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Target: 3 months of expenses',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: PrivacyText(
                  formatMoney(
                    Money(
                      amountMinor: totalCash,
                      currency: state.preferences.displayCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: PrivacyText(
                  '/ ${formatMoney(Money(amountMinor: target, currency: state.preferences.displayCurrency), state.preferences.locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
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
