import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../common/route_scaffold.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final scheme = Theme.of(context).colorScheme;
    final budgets = state.budgets;

    return RouteScaffold(
      title: 'Budgets',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add budget',
          onPressed: () => context.push('/budgets/new'),
        ),
      ],
      child: budgets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.donut_large_outlined,
                      size: 64,
                      color: scheme.onSurfaceVariant.withAlpha(120),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No budgets set up yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Create budgets to track spending limits per category or overall.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => context.push('/budgets/new'),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create budget'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: budgets.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final budget = budgets[index];
                final spent = budgetSpent(state, budget);
                final spentMinor = spent.amountMinor;
                final limitMinor = budget.amount.amountMinor;
                final pct = limitMinor > 0 ? spentMinor / limitMinor : 0.0;
                final isOver = spentMinor > limitMinor && limitMinor > 0;
                final category = budget.categoryId != null
                    ? categoryById(state, budget.categoryId)
                    : null;

                return SectionCard(
                  title: budget.name,
                  subtitle: category != null
                      ? 'Category: ${category.name} · ${budget.frequency}'
                      : 'All categories · ${budget.frequency}',
                  actionLabel: 'Delete',
                  onAction: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete budget'),
                        content: Text('Are you sure you want to delete "${budget.name}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final remaining = state.budgets.where((b) => b.id != budget.id).toList();
                      await ref.read(ledgerProvider.notifier).restoreLedgerState(
                            state.copyWith(budgets: remaining),
                          );
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: PrivacyText(
                              'Spent: ${formatMoney(spent, state.preferences.locale)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isOver ? scheme.error : scheme.onSurface,
                              ),
                            ),
                          ),
                          Flexible(
                            child: PrivacyText(
                              'Limit: ${formatMoney(budget.amount, state.preferences.locale)}',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: 8,
                          color: isOver ? scheme.error : scheme.primary,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isOver
                            ? 'Over budget by ${(pct * 100 - 100).toStringAsFixed(0)}%'
                            : '${(pct * 100).toStringAsFixed(0)}% used',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isOver ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
