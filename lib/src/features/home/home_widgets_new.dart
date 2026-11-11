import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import 'home_components.dart';
import 'home_widget_card.dart';
import 'home_widget_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Pending Ingestion & SMS/Push Review Widget
// ─────────────────────────────────────────────────────────────────────────────
class PendingReviewHomeWidget extends ConsumerWidget {
  const PendingReviewHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pending = state.captureCandidates
        .where((c) => c.status == 'pending')
        .toList();

    return HomeWidgetCard(
      title: 'Pending review',
      subtitle: pending.isEmpty
          ? 'No incoming alerts to verify'
          : '${pending.length} incoming transaction${pending.length > 1 ? 's' : ''} to confirm',
      icon: Icons.mark_email_unread_outlined,
      iconColor: pending.isEmpty ? scheme.primary : scheme.error,
      actionLabel: pending.isNotEmpty ? 'Review' : null,
      onAction: pending.isNotEmpty
          ? () => context.push('/review')
          : null,
      child: pending.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'All caught up',
              body: 'No pending SMS or notification transactions waiting for review.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final candidate in pending.take(3)) ...[
                  InkWell(
                    onTap: () => context.push('/review'),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: scheme.primary.withAlphaFactor(0.16),
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Icon(
                              candidate.source == 'sms'
                                  ? Icons.sms_outlined
                                  : Icons.notifications_none_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  candidate.merchant ??
                                      (candidate.rawText != null && candidate.rawText!.length > 30
                                          ? '${candidate.rawText!.substring(0, 30)}...'
                                          : candidate.rawText) ??
                                      'Transaction alert',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  candidate.suggestedAccountId != null
                                      ? 'Suggested account'
                                      : 'Source: ${candidate.source.toUpperCase()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          if (candidate.parsedAmount != null)
                            PrivacyText(
                              formatMoney(candidate.parsedAmount!, state.preferences.locale),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: scheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (candidate != pending.take(3).last)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Savings Rate & Flow Ratio Widget
// ─────────────────────────────────────────────────────────────────────────────
class SavingsRateHomeWidget extends ConsumerWidget {
  const SavingsRateHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final period = getHomeWidgetFilterForWidget(
      state.preferences.homeWidgetFilters,
      'savingsRate',
    );
    final range = homeWidgetDateRange(period);
    final displayCurrency = state.preferences.displayCurrency.toUpperCase();

    int totalIncomeMinor = 0;
    int totalExpenseMinor = 0;

    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (t.occurredAt.isBefore(range.start) || !t.occurredAt.isBefore(range.end)) {
        continue;
      }

      final converted = convertMoneyForDisplay(state, t.amount, displayCurrency);
      if (incomeTypes.contains(t.type)) {
        totalIncomeMinor += converted.amountMinor;
      } else if (expenseTypes.contains(t.type)) {
        totalExpenseMinor += converted.amountMinor;
      }
    }

    final netSavedMinor = totalIncomeMinor - totalExpenseMinor;
    final savingsRate = totalIncomeMinor > 0
        ? (netSavedMinor / totalIncomeMinor).clamp(-1.0, 1.0)
        : 0.0;
    final savingsPercentage = (savingsRate * 100).round();

    final Color toneColor;
    if (savingsRate >= 0.20) {
      toneColor = positiveTone(context);
    } else if (savingsRate >= 0.0) {
      toneColor = scheme.warning;
    } else {
      toneColor = scheme.error;
    }

    return HomeWidgetCard(
      title: 'Savings rate',
      subtitle: totalIncomeMinor == 0 && totalExpenseMinor == 0
          ? 'No transaction flow in this period'
          : '$savingsPercentage% of income saved · $period',
      icon: Icons.trending_up_rounded,
      iconColor: toneColor,
      dateFilter: period,
      onDateFilterChanged: (val) {
        final newFilters = Map<String, String>.from(state.preferences.homeWidgetFilters);
        newFilters['savingsRate'] = val;
        ref.read(ledgerProvider.notifier).updatePreferencesWith(
              (p) => p.copyWith(homeWidgetFilters: newFilters),
            );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Net Saved',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    PrivacyText(
                      formatMoney(
                        Money(amountMinor: netSavedMinor, currency: displayCurrency),
                        state.preferences.locale,
                      ),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: toneColor,
                            letterSpacing: -0.5,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: toneColor.withAlphaFactor(0.15),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: toneColor.withAlphaFactor(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      savingsRate >= 0.20
                          ? Icons.emoji_events_outlined
                          : savingsRate >= 0.0
                              ? Icons.savings_outlined
                              : Icons.warning_amber_rounded,
                      size: 16,
                      color: toneColor,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '$savingsPercentage%',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: toneColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          HomeLiveProgressBar(
            progress: savingsRate.clamp(0.0, 1.0),
            color: toneColor,
            height: 10,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Income',
                  value: maskMoneyIfPrivate(
                    state,
                    formatMoney(
                      Money(amountMinor: totalIncomeMinor, currency: displayCurrency),
                      state.preferences.locale,
                    ),
                  ),
                  icon: Icons.arrow_downward_rounded,
                  tone: MetricTone.positive,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Expense',
                  value: maskMoneyIfPrivate(
                    state,
                    formatMoney(
                      Money(amountMinor: totalExpenseMinor, currency: displayCurrency),
                      state.preferences.locale,
                    ),
                  ),
                  icon: Icons.arrow_upward_rounded,
                  tone: MetricTone.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Tag Spending Breakdown Widget
// ─────────────────────────────────────────────────────────────────────────────
class TagCloudHomeWidget extends ConsumerWidget {
  const TagCloudHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final period = getHomeWidgetFilterForWidget(
      state.preferences.homeWidgetFilters,
      'tagCloud',
    );
    final range = homeWidgetDateRange(period);
    final displayCurrency = state.preferences.displayCurrency.toUpperCase();

    final tagTotals = <String, int>{};

    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (!expenseTypes.contains(t.type)) continue;
      if (t.occurredAt.isBefore(range.start) || !t.occurredAt.isBefore(range.end)) {
        continue;
      }

      final tags = t.tags;
      if (tags.isEmpty) continue;

      final converted = convertMoneyForDisplay(state, t.amount, displayCurrency);
      for (final rawTag in tags) {
        final tag = rawTag.trim();
        if (tag.isEmpty) continue;
        tagTotals[tag] = (tagTotals[tag] ?? 0) + converted.amountMinor;
      }
    }

    final sorted = tagTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTags = sorted.take(8).toList();

    return HomeWidgetCard(
      title: 'Tag breakdown',
      subtitle: topTags.isEmpty
          ? 'No tagged records in $period'
          : '${topTags.length} active tags · $period',
      icon: Icons.label_outline_rounded,
      iconColor: scheme.tertiary,
      dateFilter: period,
      onDateFilterChanged: (val) {
        final newFilters = Map<String, String>.from(state.preferences.homeWidgetFilters);
        newFilters['tagCloud'] = val;
        ref.read(ledgerProvider.notifier).updatePreferencesWith(
              (p) => p.copyWith(homeWidgetFilters: newFilters),
            );
      },
      child: topTags.isEmpty
          ? const EmptyState(
              icon: Icons.label_off_outlined,
              title: 'No tagged expenses',
              body: 'Tag your transactions with #dining, #work, etc. to view tag insights here.',
            )
          : Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tagEntry in topTags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tagEntry.key.startsWith('#')
                              ? tagEntry.key
                              : '#${tagEntry.key}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        PrivacyText(
                          formatMoney(
                            Money(
                              amountMinor: tagEntry.value,
                              currency: displayCurrency,
                            ),
                            state.preferences.locale,
                          ),
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Daily Safe-to-Spend Widget
// ─────────────────────────────────────────────────────────────────────────────
class SafeToSpendHomeWidget extends ConsumerWidget {
  const SafeToSpendHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day;
    final remainingDays = math.max(1, daysInMonth - dayOfMonth + 1);

    final displayCurrency = state.preferences.displayCurrency.toUpperCase();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    int monthExpensesMinor = 0;
    int todayExpensesMinor = 0;
    int monthIncomeMinor = 0;

    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (t.occurredAt.isBefore(startOfMonth)) continue;

      final converted = convertMoneyForDisplay(state, t.amount, displayCurrency);
      if (expenseTypes.contains(t.type)) {
        monthExpensesMinor += converted.amountMinor;
        if (!t.occurredAt.isBefore(todayStart) && t.occurredAt.isBefore(tomorrowStart)) {
          todayExpensesMinor += converted.amountMinor;
        }
      } else if (incomeTypes.contains(t.type)) {
        monthIncomeMinor += converted.amountMinor;
      }
    }

    final balanceRemainingMinor = math.max(0, monthIncomeMinor - monthExpensesMinor);
    final safeDailyAllowanceMinor = (balanceRemainingMinor / remainingDays).round();
    final spentRatio = safeDailyAllowanceMinor > 0
        ? (todayExpensesMinor / safeDailyAllowanceMinor).clamp(0.0, 1.0)
        : 1.0;

    return HomeWidgetCard(
      title: 'Daily safe-to-spend',
      subtitle: '$remainingDays days remaining in this month',
      icon: Icons.speed_outlined,
      iconColor: scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Allowance',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    PrivacyText(
                      formatMoney(
                        Money(
                          amountMinor: safeDailyAllowanceMinor,
                          currency: displayCurrency,
                        ),
                        state.preferences.locale,
                      ),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                            letterSpacing: -0.5,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  'Day $dayOfMonth of $daysInMonth',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spent today: ${maskMoneyIfPrivate(state, formatMoney(Money(amountMinor: todayExpensesMinor, currency: displayCurrency), state.preferences.locale))}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                '${(spentRatio * 100).round()}% used',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: spentRatio > 0.9 ? scheme.error : positiveTone(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          HomeLiveProgressBar(
            progress: spentRatio,
            color: spentRatio > 0.9 ? scheme.error : positiveTone(context),
            height: 10,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Cash Runway & Burn Rate Widget
// ─────────────────────────────────────────────────────────────────────────────
class CashBurnRunwayHomeWidget extends ConsumerWidget {
  const CashBurnRunwayHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final displayCurrency = state.preferences.displayCurrency.toUpperCase();
    final balances = accountBalanceMap(state);

    // Sum liquid accounts
    int totalLiquidMinor = 0;
    for (final acc in state.accounts) {
      if (acc.isArchived) continue;
      if (acc.type == 'cash' ||
          acc.type == 'bank' ||
          acc.type == 'checking' ||
          acc.type == 'savings') {
        final bal = accountBalanceFromMap(balances, acc);
        final converted = convertMoneyForDisplay(state, bal, displayCurrency);
        if (converted.amountMinor > 0) {
          totalLiquidMinor += converted.amountMinor;
        }
      }
    }

    // 30-day moving expense burn
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    int past30DaysExpenseMinor = 0;

    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (!expenseTypes.contains(t.type)) continue;
      if (t.occurredAt.isBefore(thirtyDaysAgo) || t.occurredAt.isAfter(now)) {
        continue;
      }
      final converted = convertMoneyForDisplay(state, t.amount, displayCurrency);
      past30DaysExpenseMinor += converted.amountMinor;
    }

    final dailyBurnMinor = (past30DaysExpenseMinor / 30).round();
    final monthlyBurnMinor = (dailyBurnMinor * 30.4).round();
    final runwayDays = dailyBurnMinor > 0
        ? (totalLiquidMinor / dailyBurnMinor).round()
        : (totalLiquidMinor > 0 ? 999 : 0);
    final runwayMonths = dailyBurnMinor > 0
        ? (runwayDays / 30.4).toStringAsFixed(1)
        : (totalLiquidMinor > 0 ? '∞' : '0.0');

    // Visual gauge progress towards a healthy 6-month buffer (180 days)
    final progress = totalLiquidMinor <= 0
        ? 0.0
        : (dailyBurnMinor <= 0 ? 1.0 : (runwayDays / 180.0).clamp(0.0, 1.0));

    final MetricTone runwayTone;
    if (runwayDays >= 180 || (dailyBurnMinor == 0 && totalLiquidMinor > 0)) {
      runwayTone = MetricTone.positive;
    } else if (runwayDays >= 60) {
      runwayTone = MetricTone.positive;
    } else if (runwayDays >= 30) {
      runwayTone = MetricTone.warning;
    } else {
      runwayTone = MetricTone.danger;
    }

    final statusText = runwayDays >= 180 || (dailyBurnMinor == 0 && totalLiquidMinor > 0)
        ? 'Excellent emergency cushion (6+ months)'
        : runwayDays >= 90
            ? 'Healthy cushion (3–6 months)'
            : runwayDays >= 30
                ? 'Moderate buffer (< 3 months)'
                : 'Low cash buffer (< 1 month)';

    return HomeWidgetCard(
      title: 'Cash runway',
      subtitle: 'Emergency liquidity margin',
      icon: Icons.hourglass_bottom_rounded,
      iconColor: scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Survival Runway',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      dailyBurnMinor == 0 && totalLiquidMinor > 0
                          ? 'Indefinite'
                          : '$runwayMonths Months',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: runwayTone.resolve(scheme),
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: runwayTone.resolve(scheme).withAlphaFactor(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: runwayTone.resolve(scheme).withAlphaFactor(0.3),
                  ),
                ),
                child: Text(
                  dailyBurnMinor == 0 && totalLiquidMinor > 0
                      ? 'No burn'
                      : '$runwayDays days',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: runwayTone.resolve(scheme),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Buffer health progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: runwayTone.resolve(scheme),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${(progress * 100).round()}% of 6mo goal',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              HomeLiveProgressBar(
                progress: progress,
                color: runwayTone.resolve(scheme),
                height: 8,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: HomeMetricTile(
                  label: 'Daily burn rate',
                  value: maskMoneyIfPrivate(
                    state,
                    formatMoney(
                      Money(amountMinor: dailyBurnMinor, currency: displayCurrency),
                      state.preferences.locale,
                    ),
                  ),
                  icon: Icons.local_fire_department_outlined,
                  tone: MetricTone.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: HomeMetricTile(
                  label: 'Liquid cash',
                  value: maskMoneyIfPrivate(
                    state,
                    formatMoney(
                      Money(amountMinor: totalLiquidMinor, currency: displayCurrency),
                      state.preferences.locale,
                    ),
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  tone: MetricTone.positive,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Est. monthly burn',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              PrivacyText(
                formatMoney(
                  Money(amountMinor: monthlyBurnMinor, currency: displayCurrency),
                  state.preferences.locale,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. No-Spend Days Streak Widget
// ─────────────────────────────────────────────────────────────────────────────
class NoSpendStreakHomeWidget extends ConsumerWidget {
  const NoSpendStreakHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonthSoFar = now.day;

    // Identify days with expenses this month
    final expenseDays = <int>{};
    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (!expenseTypes.contains(t.type)) continue;
      if (t.occurredAt.year == now.year && t.occurredAt.month == now.month) {
        expenseDays.add(t.occurredAt.day);
      }
    }

    int noSpendDaysCount = 0;
    for (int day = 1; day <= daysInMonthSoFar; day++) {
      if (!expenseDays.contains(day)) {
        noSpendDaysCount++;
      }
    }

    // Current streak (counting backwards from today)
    int streak = 0;
    for (int i = 0; i < 30; i++) {
      final checkDate = today.subtract(Duration(days: i));
      final hasExpense = state.transactions.any(
        (t) =>
            !t.occurredAt.isBefore(checkDate) &&
            t.occurredAt.isBefore(checkDate.add(const Duration(days: 1))) &&
            expenseTypes.contains(t.type) &&
            t.status != 'void' &&
            t.status != 'scheduled' &&
            t.status != 'paused',
      );
      if (!hasExpense) {
        streak++;
      } else {
        break;
      }
    }

    return HomeWidgetCard(
      title: 'No-spend days',
      subtitle: 'Discretionary spending discipline',
      icon: Icons.local_fire_department_outlined,
      iconColor: scheme.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zero-Spend Days',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      '$noSpendDaysCount of $daysInMonthSoFar Days',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withAlphaFactor(0.15),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: scheme.tertiary.withAlphaFactor(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '$streak day streak',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.tertiary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Past 7 days mini indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 6; i >= 0; i--) ...[
                Builder(
                  builder: (context) {
                    final dayDate = today.subtract(Duration(days: i));
                    final isNoSpend = !expenseDays.contains(dayDate.day);
                    final dayLabel = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][dayDate.weekday - 1];
                    return Column(
                      children: [
                        Text(
                          dayLabel,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isNoSpend
                                ? positiveTone(context).withAlphaFactor(0.2)
                                : scheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isNoSpend
                                  ? positiveTone(context)
                                  : scheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              isNoSpend ? Icons.check_rounded : Icons.close_rounded,
                              size: 12,
                              color: isNoSpend
                                  ? positiveTone(context)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. Weekend vs Weekday Spend Ratio Widget
// ─────────────────────────────────────────────────────────────────────────────
class WeekendWeekdayRatioHomeWidget extends ConsumerWidget {
  const WeekendWeekdayRatioHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final period = getHomeWidgetFilterForWidget(
      state.preferences.homeWidgetFilters,
      'weekendWeekdayRatio',
    );
    final range = homeWidgetDateRange(period);
    final displayCurrency = state.preferences.displayCurrency.toUpperCase();

    int weekendTotalMinor = 0;
    int weekdayTotalMinor = 0;

    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (!expenseTypes.contains(t.type)) continue;
      if (t.occurredAt.isBefore(range.start) || !t.occurredAt.isBefore(range.end)) {
        continue;
      }

      final converted = convertMoneyForDisplay(state, t.amount, displayCurrency);
      if (t.occurredAt.weekday == DateTime.saturday ||
          t.occurredAt.weekday == DateTime.sunday) {
        weekendTotalMinor += converted.amountMinor;
      } else {
        weekdayTotalMinor += converted.amountMinor;
      }
    }

    final totalMinor = weekendTotalMinor + weekdayTotalMinor;
    final weekendPct = totalMinor > 0 ? (weekendTotalMinor / totalMinor * 100).round() : 0;
    final weekdayPct = 100 - weekendPct;

    return HomeWidgetCard(
      title: 'Weekend vs weekday',
      subtitle: totalMinor == 0
          ? 'No expenses in $period'
          : '$weekendPct% weekend · $weekdayPct% weekday',
      icon: Icons.weekend_outlined,
      iconColor: scheme.secondary,
      dateFilter: period,
      onDateFilterChanged: (val) {
        final newFilters = Map<String, String>.from(state.preferences.homeWidgetFilters);
        newFilters['weekendWeekdayRatio'] = val;
        ref.read(ledgerProvider.notifier).updatePreferencesWith(
              (p) => p.copyWith(homeWidgetFilters: newFilters),
            );
      },
      child: totalMinor == 0
          ? const EmptyState(
              icon: Icons.weekend_outlined,
              title: 'No expense records',
              body: 'Expenses recorded in this timeframe will show your lifestyle spending split.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: Row(
                    children: [
                      if (weekdayPct > 0)
                        Expanded(
                          flex: weekdayPct,
                          child: Container(
                            height: 8,
                            color: scheme.primary,
                          ),
                        ),
                      if (weekendPct > 0)
                        Expanded(
                          flex: weekendPct,
                          child: Container(
                            height: 8,
                            color: scheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: HomeMetricTile(
                        label: 'Weekdays ($weekdayPct%)',
                        value: maskMoneyIfPrivate(
                          state,
                          formatMoney(
                            Money(
                              amountMinor: weekdayTotalMinor,
                              currency: displayCurrency,
                            ),
                            state.preferences.locale,
                          ),
                        ),
                        icon: Icons.business_center_outlined,
                        tone: MetricTone.standard,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: HomeMetricTile(
                        label: 'Weekends ($weekendPct%)',
                        value: maskMoneyIfPrivate(
                          state,
                          formatMoney(
                            Money(
                              amountMinor: weekendTotalMinor,
                              currency: displayCurrency,
                            ),
                            state.preferences.locale,
                          ),
                        ),
                        icon: Icons.local_activity_outlined,
                        tone: MetricTone.warning,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
