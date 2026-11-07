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
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              height: 6,
              color: scheme.surfaceContainerHighest,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: savingsRate.clamp(0.0, 1.0),
                  child: Container(color: toneColor),
                ),
              ),
            ),
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
// 3. Top Payees & Merchants Widget
// ─────────────────────────────────────────────────────────────────────────────
class TopMerchantsHomeWidget extends ConsumerWidget {
  const TopMerchantsHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final period = getHomeWidgetFilterForWidget(
      state.preferences.homeWidgetFilters,
      'topMerchants',
    );
    final range = homeWidgetDateRange(period);
    final displayCurrency = state.preferences.displayCurrency.toUpperCase();

    final merchantTotals = <String, ({int amountMinor, int count})>{};

    for (final t in state.transactions) {
      if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
        continue;
      }
      if (!expenseTypes.contains(t.type)) continue;
      if (t.occurredAt.isBefore(range.start) || !t.occurredAt.isBefore(range.end)) {
        continue;
      }

      final rawName = t.name?.trim();
      final merchant = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : (t.notes != null && t.notes!.trim().isNotEmpty
              ? t.notes!.trim()
              : 'Unknown Payee');

      final converted = convertMoneyForDisplay(state, t.amount, displayCurrency);
      final existing = merchantTotals[merchant] ?? (amountMinor: 0, count: 0);
      merchantTotals[merchant] = (
        amountMinor: existing.amountMinor + converted.amountMinor,
        count: existing.count + 1,
      );
    }

    final sorted = merchantTotals.entries.toList()
      ..sort((a, b) => b.value.amountMinor.compareTo(a.value.amountMinor));
    final topMerchants = sorted.take(4).toList();
    final maxAmount = topMerchants.isNotEmpty
        ? math.max(1, topMerchants.first.value.amountMinor)
        : 1;

    return HomeWidgetCard(
      title: 'Top merchants',
      subtitle: topMerchants.isEmpty
          ? 'No payee records in $period'
          : '${topMerchants.length} top spend vendors · $period',
      icon: Icons.storefront_outlined,
      iconColor: scheme.primary,
      dateFilter: period,
      onDateFilterChanged: (val) {
        final newFilters = Map<String, String>.from(state.preferences.homeWidgetFilters);
        newFilters['topMerchants'] = val;
        ref.read(ledgerProvider.notifier).updatePreferencesWith(
              (p) => p.copyWith(homeWidgetFilters: newFilters),
            );
      },
      child: topMerchants.isEmpty
          ? const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No merchant data',
              body: 'Enter payee or merchant names on records to view vendor insights.',
            )
          : Column(
              children: [
                for (final item in topMerchants) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${item.value.count}x  ·  ',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                            PrivacyText(
                              formatMoney(
                                Money(
                                  amountMinor: item.value.amountMinor,
                                  currency: displayCurrency,
                                ),
                                state.preferences.locale,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          child: Container(
                            height: 5,
                            color: scheme.surfaceContainerHighest,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: (item.value.amountMinor / maxAmount)
                                    .clamp(0.02, 1.0),
                                child: Container(
                                  color: scheme.primary.withAlphaFactor(0.85),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item != topMerchants.last)
                    const Divider(height: AppSpacing.sm),
                ],
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
// 5. Subscription Radar Widget
// ─────────────────────────────────────────────────────────────────────────────
class SubscriptionRadarHomeWidget extends ConsumerWidget {
  const SubscriptionRadarHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final displayCurrency = state.preferences.displayCurrency.toUpperCase();
    final rules = state.preferences.futureGenerationRules ?? const [];

    final recurringExpenses = rules
        .where((r) => r.enabled && expenseTypes.contains(r.type))
        .toList();

    int totalMonthlyMinor = 0;
    for (final rule in recurringExpenses) {
      final converted = convertMoneyForDisplay(
        state,
        Money(amountMinor: rule.amountMinor, currency: rule.currency),
        displayCurrency,
      );
      final monthlyAmount = switch (rule.frequency) {
        'weekly' => (converted.amountMinor * 52 / 12).round(),
        'biweekly' => (converted.amountMinor * 26 / 12).round(),
        'quarterly' => (converted.amountMinor / 3).round(),
        'yearly' => (converted.amountMinor / 12).round(),
        _ => converted.amountMinor, // default monthly
      };
      totalMonthlyMinor += monthlyAmount;
    }

    final totalAnnualMinor = totalMonthlyMinor * 12;

    return HomeWidgetCard(
      title: 'Subscriptions',
      subtitle: recurringExpenses.isEmpty
          ? 'No active recurring commitments'
          : '${recurringExpenses.length} recurring rules active',
      icon: Icons.autorenew_rounded,
      iconColor: scheme.primary,
      actionLabel: 'Planner',
      onAction: () => context.push('/planner'),
      child: recurringExpenses.isEmpty
          ? const EmptyState(
              icon: Icons.autorenew_rounded,
              title: 'No recurring subscriptions',
              body: 'Add your recurring bills and subscriptions in Planner to track annual burn.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: HomeMetricTile(
                        label: 'Monthly burn',
                        value: maskMoneyIfPrivate(
                          state,
                          formatMoney(
                            Money(
                              amountMinor: totalMonthlyMinor,
                              currency: displayCurrency,
                            ),
                            state.preferences.locale,
                          ),
                        ),
                        icon: Icons.calendar_month_outlined,
                        tone: MetricTone.danger,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: HomeMetricTile(
                        label: 'Projected annual',
                        value: maskMoneyIfPrivate(
                          state,
                          formatMoney(
                            Money(
                              amountMinor: totalAnnualMinor,
                              currency: displayCurrency,
                            ),
                            state.preferences.locale,
                          ),
                        ),
                        icon: Icons.schedule_rounded,
                        tone: MetricTone.standard,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final item in recurringExpenses.take(3)) ...[
                  HomeDetailRow(
                    icon: Icons.repeat_rounded,
                    title: item.name,
                    subtitle: 'Frequency: ${item.frequency}',
                    trailing: maskMoneyIfPrivate(
                      state,
                      formatMoney(
                        Money(amountMinor: item.amountMinor, currency: item.currency),
                        state.preferences.locale,
                      ),
                    ),
                    tone: MetricTone.danger,
                  ),
                  if (item != recurringExpenses.take(3).last)
                    const Divider(height: AppSpacing.sm),
                ],
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
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              height: 6,
              color: scheme.surfaceContainerHighest,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: spentRatio,
                  child: Container(
                    color: spentRatio > 0.9 ? scheme.error : positiveTone(context),
                  ),
                ),
              ),
            ),
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
    final runwayDays = dailyBurnMinor > 0
        ? (totalLiquidMinor / dailyBurnMinor).round()
        : 999;
    final runwayMonths = (runwayDays / 30.4).toStringAsFixed(1);

    final MetricTone runwayTone;
    if (runwayDays >= 90) {
      runwayTone = MetricTone.positive;
    } else if (runwayDays >= 30) {
      runwayTone = MetricTone.warning;
    } else {
      runwayTone = MetricTone.danger;
    }

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
                      '$runwayMonths Months',
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
                  '$runwayDays days',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: runwayTone.resolve(scheme),
                  ),
                ),
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
