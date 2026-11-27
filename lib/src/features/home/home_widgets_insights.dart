import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import 'home_components.dart';
import 'home_insight_selectors.dart';
import 'home_widget_card.dart';

String _shortDate(DateTime date, String locale) {
  try {
    return DateFormat('EEE, d MMM', locale.replaceAll('_', '-')).format(date);
  } catch (_) {
    return DateFormat('EEE, d MMM').format(date);
  }
}

String _dayCount(int days) => days == 1 ? '1 day' : '$days days';

String paydayHeadline(PaydayInfo info) {
  if (info.isToday) return 'Today';
  if (info.daysUntil == 1) return 'Tomorrow';
  if (info.isLate) return '${_dayCount(-info.daysUntil)} late';
  return _dayCount(info.daysUntil);
}

String cardDueLabel(CardBillInfo info) {
  final status = info.status;
  if (status.isPaid) return 'Paid';
  if (info.hasNothingDue) return 'Nothing due';
  final days = status.daysUntilDue;
  if (days < 0) return '${_dayCount(-days)} overdue';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in ${_dayCount(days)}';
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, this.color, this.onTap, super.key});

  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = color ?? scheme.primary;
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxxs,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tone,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: pill,
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PrivacyText(
            value,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payday countdown
// ─────────────────────────────────────────────────────────────────────────────
class PaydayCountdownHomeWidget extends ConsumerWidget {
  const PaydayCountdownHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final info = paydayInfo(state);
    if (info == null) {
      return HomeWidgetCard(
        title: 'Payday',
        subtitle: 'Countdown to your next salary',
        icon: Icons.event_available_outlined,
        actionLabel: 'Add plan',
        onAction: () => context.push('/recurring/new'),
        child: const EmptyState(
          icon: Icons.payments_outlined,
          title: 'No salary plan',
          body:
              'Add an active planned income in the Salary category to see a countdown to payday.',
        ),
      );
    }

    final locale = state.preferences.locale;
    final plan = info.plan;
    final headlineColor = info.isLate
        ? scheme.error
        : info.isToday
        ? positiveTone(context)
        : scheme.onSurface;
    final canRecord = info.isToday || info.isLate;
    final left = info.leftAfterBills;
    final progress = info.cycleProgress;
    final cycleLength = info.cycleLength;

    return HomeWidgetCard(
      title: 'Payday',
      subtitle: planDisplayName(state, plan),
      icon: Icons.event_available_outlined,
      iconColor: info.isLate ? scheme.error : positiveTone(context),
      actionLabel: canRecord ? 'Record' : 'View',
      onAction: () => canRecord
          ? context.push('/add?plannedId=${plan.id}')
          : context.push('/recurring/${plan.id}'),
      headerTrailing: info.otherPlanIds.isEmpty
          ? null
          : _InfoPill(
              key: const Key('payday-switch-plan'),
              label: '+${info.otherPlanIds.length} more',
              onTap: () => _pinPlan(ref, info.otherPlanIds.first),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    paydayHeadline(info),
                    key: const Key('payday-headline'),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: headlineColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PrivacyText(
                    '+${formatMoney(plan.amount, locale)}',
                    maxLines: 1,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: positiveTone(context),
                    ),
                  ),
                  Text(
                    info.isLate
                        ? 'Expected ${_shortDate(info.payday, locale)}'
                        : _shortDate(info.payday, locale),
                    maxLines: 1,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (info.account != null)
            Text(
              info.isLate
                  ? 'Not recorded yet · ${info.account!.name}'
                  : 'To ${info.account!.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (info.missedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                '${info.missedCount} earlier salary ${info.missedCount == 1 ? 'date' : 'dates'} not recorded',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (progress != null && cycleLength != null && !info.isLate) ...[
            const SizedBox(height: AppSpacing.sm),
            HomeLiveProgressBar(progress: progress, height: 8),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Day ${(cycleLength - info.daysUntil).clamp(0, cycleLength)} of $cycleLength in this pay cycle',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!info.isToday) ...[
            const SizedBox(height: AppSpacing.xs),
            _ValueRow(
              label: 'Bills before payday (${info.bills.length})',
              value: info.bills.isEmpty
                  ? formatMoney(info.billsTotal, locale)
                  : '−${formatMoney(info.billsTotal, locale)}',
              color: info.bills.isEmpty ? null : scheme.error,
            ),
            if (left != null)
              _ValueRow(
                label: 'Left after bills',
                value: formatMoney(left, locale),
                color: left.amountMinor < 0
                    ? scheme.error
                    : positiveTone(context),
              ),
          ],
        ],
      ),
    );
  }

  void _pinPlan(WidgetRef ref, String planId) {
    ref
        .read(ledgerProvider.notifier)
        .updatePreferencesWith(
          (prefs) => prefs.copyWith(
            homeWidgetFilters: {
              ...prefs.homeWidgetFilters,
              paydayPinnedPlanKey: planId,
            },
          ),
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Next card bill
// ─────────────────────────────────────────────────────────────────────────────
class NextCardBillHomeWidget extends ConsumerWidget {
  const NextCardBillHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bills = cardBills(state);
    if (bills.isEmpty) {
      return HomeWidgetCard(
        title: 'Next card bill',
        subtitle: 'Credit card due dates',
        icon: Icons.credit_card_outlined,
        actionLabel: 'Cards',
        onAction: () => context.push('/cards'),
        child: const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No card due dates',
          body:
              'Set a statement or due day on a credit card to track its bill here.',
        ),
      );
    }

    final locale = state.preferences.locale;
    final next = bills.first;
    final settled = next.status.isPaid || next.hasNothingDue;
    final urgent = !settled && (next.status.isOverdue || next.status.isDueSoon);
    final tone = settled
        ? positiveTone(context)
        : next.status.isOverdue
        ? scheme.error
        : urgent
        ? scheme.tertiary
        : scheme.primary;
    final payday = paydayInfo(state);
    final beforePayday =
        !settled &&
        next.status.daysUntilDue >= 0 &&
        payday != null &&
        payday.daysUntil > 0 &&
        calendarDaysBetween(next.status.dueDate, payday.payday) > 0;

    return HomeWidgetCard(
      title: 'Next card bill',
      subtitle: next.status.account.name,
      icon: Icons.credit_card_outlined,
      iconColor: tone,
      actionLabel: 'Cards',
      onAction: () => context.push('/cards'),
      headerTrailing: _InfoPill(label: cardDueLabel(next), color: tone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrivacyText(
            formatMoney(next.owed, locale),
            key: const Key('card-bill-amount'),
            maxLines: 1,
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: settled ? scheme.onSurface : tone,
            ),
          ),
          Text(
            settled
                ? 'Next due ${_shortDate(next.status.dueDate, locale)}'
                : 'Due ${_shortDate(next.status.dueDate, locale)}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (beforePayday) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              key: const Key('card-bill-before-payday'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: scheme.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      payday.daysUntil == 1
                          ? 'Due before payday tomorrow'
                          : 'Due before payday in ${_dayCount(payday.daysUntil)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          for (final other in bills.skip(1).take(2)) ...[
            const Divider(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        other.status.account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        cardDueLabel(other),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: other.status.isOverdue && !other.hasNothingDue
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                PrivacyText(
                  formatMoney(other.owed, locale),
                  maxLines: 1,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: other.status.isOverdue && !other.hasNothingDue
                        ? scheme.error
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category spikes
// ─────────────────────────────────────────────────────────────────────────────
class CategorySpikesHomeWidget extends ConsumerWidget {
  const CategorySpikesHomeWidget({
    required this.state,
    required this.onRecords,
    super.key,
  });

  final LedgerState state;
  final VoidCallback onRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final result = categorySpikes(state);
    final locale = state.preferences.locale;

    final Widget body;
    if (!result.hasEnoughHistory) {
      body = const EmptyState(
        icon: Icons.hourglass_empty_rounded,
        title: 'Not enough history yet',
        body:
            'Unusual spending appears after two months of categorised expenses.',
      );
    } else if (result.items.isEmpty) {
      body = const EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Spending looks normal',
        body: 'No category is far above or below your recent average.',
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final spike in result.items) ...[
            if (spike != result.items.first)
              const Divider(height: AppSpacing.md),
            _SpikeRow(spike: spike, locale: locale),
          ],
        ],
      );
    }

    return HomeWidgetCard(
      title: 'Unusual spending',
      subtitle: result.hasEnoughHistory
          ? 'Day ${result.dayOfMonth} vs ${result.monthsCompared}-month average'
          : 'This month vs your recent average',
      icon: Icons.insights_outlined,
      iconColor: result.items.any((s) => s.change > 0)
          ? scheme.error
          : scheme.primary,
      actionLabel: result.items.isEmpty ? null : 'Records',
      onAction: result.items.isEmpty ? null : onRecords,
      child: DefaultTextStyle.merge(style: textTheme.bodyMedium, child: body),
    );
  }
}

class _SpikeRow extends StatelessWidget {
  const _SpikeRow({required this.spike, required this.locale});

  final CategorySpike spike;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final up = spike.change > 0;
    final tone = up ? scheme.error : positiveTone(context);
    final changeLabel = spike.isNew
        ? 'New'
        : '${up ? '▲' : '▼'} ${(spike.change.abs() * 100).round()}%';
    return Row(
      children: [
        Icon(categoryIcon(spike.category), size: 20, color: tone),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spike.category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              PrivacyText(
                'Avg ${formatMoney(spike.baseline, locale)}',
                maxLines: 1,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              changeLabel,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
              ),
            ),
            PrivacyText(
              formatMoney(spike.current, locale),
              maxLines: 1,
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
