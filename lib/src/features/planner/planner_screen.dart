import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({required this.onMenuPressed, super.key});

  final VoidCallback onMenuPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final flow = flowForCurrentMonth(state);
    final scheduled = scheduledTransactions(state);
    final debtCommitments = scheduled
        .where((tx) => tx.type == 'loan_repayment' || tx.type == 'card_payment')
        .fold<int>(0, (sum, tx) => sum + tx.baseAmount.amountMinor);
    final free =
        flow.income.amountMinor - flow.expense.amountMinor - debtCommitments;

    return AppScreen(
      title: 'Planner',
      onMenuPressed: onMenuPressed,
      actions: [
        HeaderIconButton(
          icon: Icons.event_repeat_outlined,
          onPressed: () => context.push('/recurring'),
        ),
        HeaderIconButton(
          icon: Icons.account_balance_outlined,
          onPressed: () => context.push('/loans'),
        ),
        HeaderIconButton(
          icon: Icons.settings_outlined,
          onPressed: () => context.push('/settings'),
        ),
      ],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Income',
                  value: formatMoney(flow.income, state.preferences.locale),
                  icon: Icons.payments_outlined,
                  tone: MetricTone.positive,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: MetricTile(
                  label: 'EMI load',
                  value: '${_share(debtCommitments, flow.income.amountMinor)}%',
                  icon: Icons.account_balance_outlined,
                  tone: MetricTone.warning,
                ),
              ),
            ],
          ),
          const Gap(AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Can allocate',
                  value: formatMoney(
                    Money(
                      amountMinor: free,
                      currency: state.preferences.baseCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.savings_outlined,
                  tone: free >= 0 ? MetricTone.positive : MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: MetricTile(
                  label: 'Loans',
                  value:
                      '${state.accounts.where((account) => account.type == 'loan').length}',
                  icon: Icons.account_balance_outlined,
                  tone: MetricTone.warning,
                ),
              ),
            ],
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Income plan',
            subtitle: 'Current month allocation',
            child: Column(
              children: [
                InfoRow(
                  label: 'Income available',
                  value: formatMoney(flow.income, state.preferences.locale),
                  icon: Icons.payments_outlined,
                  tone: MetricTone.positive,
                ),
                InfoRow(
                  label: 'Everyday spend',
                  value: formatMoney(flow.expense, state.preferences.locale),
                  icon: Icons.shopping_cart_outlined,
                ),
                InfoRow(
                  label: 'EMIs and cards',
                  value: formatMoney(
                    Money(
                      amountMinor: debtCommitments,
                      currency: state.preferences.baseCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.credit_card_outlined,
                  tone: MetricTone.warning,
                ),
                InfoRow(
                  label: 'Left for saving/prepayment',
                  value: formatMoney(
                    Money(
                      amountMinor: free,
                      currency: state.preferences.baseCurrency,
                    ),
                    state.preferences.locale,
                  ),
                  icon: Icons.savings_outlined,
                  tone: free >= 0 ? MetricTone.positive : MetricTone.danger,
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Budgets',
            actionLabel: 'New',
            onAction: () => context.push('/budgets/new'),
            child: Column(
              children: [
                for (final budget in state.budgets)
                  _ProgressRow(
                    label: budget.name,
                    current: budget.spent,
                    target: budget.amount,
                    locale: state.preferences.locale,
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Goals',
            actionLabel: 'New',
            onAction: () => context.push('/goals/new'),
            child: Column(
              children: [
                for (final goal in state.goals)
                  _ProgressRow(
                    label: goal.name,
                    current: goal.saved,
                    target: goal.target,
                    locale: state.preferences.locale,
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Plan actions',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/loans'),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Loans'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/recurring'),
                  icon: const Icon(Icons.event_repeat_outlined),
                  label: const Text('Recurring'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/goals/new'),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Goal'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _share(int part, int whole) =>
      whole <= 0 ? 0 : ((part / whole) * 100).round();
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.current,
    required this.target,
    required this.locale,
  });

  final String label;
  final Money current;
  final Money target;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final progress = target.amountMinor <= 0
        ? 0.0
        : (current.amountMinor / target.amountMinor).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatMoney(current, locale)} of ${formatMoney(target, locale)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
