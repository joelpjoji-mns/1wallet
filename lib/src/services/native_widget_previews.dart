import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeWidgetPreviews
//
// Standalone Flutter widgets designed for HomeWidget.renderFlutterWidget().
// They receive plain Dart data — no Riverpod providers, no BuildContext
// navigation. Each widget replicates the exact visual code from its
// corresponding in-app home tile (same card decoration, icon pill, typography,
// color tokens, and content layout).
// ─────────────────────────────────────────────────────────────────────────────

// ─── Shared card wrapper ─────────────────────────────────────────────────────

/// Replicates the visual shell of [HomeWidgetCard] without any interactive
/// controls (dropdowns, action buttons) that cannot work in a static render.
class _NativeCard extends StatelessWidget {
  const _NativeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

// ─── Shared flow panel (income / expense box) ─────────────────────────────────

class _FlowPanel extends StatelessWidget {
  const _FlowPanel({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxxs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Balance Hero
// ─────────────────────────────────────────────────────────────────────────────

class NativeBalanceWidget extends StatelessWidget {
  const NativeBalanceWidget({
    required this.totalBalance,
    required this.netWorthLabel,
    required this.incomeText,
    required this.expenseText,
    required this.currencyBreakdown,
    super.key,
  });

  final String totalBalance;
  final String netWorthLabel;
  final String incomeText;
  final String expenseText;
  /// e.g. ['USD 12,480.00', 'INR 10,34,500'] — empty list = hide
  final List<String> currencyBreakdown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positive = _positiveColor(scheme);
    final danger = scheme.error;

    return Container(
      constraints: const BoxConstraints(minHeight: 178),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Balance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              // Static "This month" pill
              const _StaticPill(label: 'This month', icon: Icons.calendar_month_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.xxxs),
          // Big balance number
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              totalBalance,
              maxLines: 1,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
          ),
          // Currency breakdown chips
          if (currencyBreakdown.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: 24,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in currencyBreakdown) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxxs,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          chip,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (chip != currencyBreakdown.last)
                        const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          // Income / Expense panels
          Row(
            children: [
              Expanded(
                child: _FlowPanel(
                  label: 'Income',
                  value: incomeText,
                  color: positive,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _FlowPanel(
                  label: 'Expense',
                  value: expenseText,
                  color: danger,
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
// 2. Accounts Overview (top N accounts)
// ─────────────────────────────────────────────────────────────────────────────

class NativeAccountEntry {
  const NativeAccountEntry({
    required this.name,
    required this.balance,
    required this.type,
    required this.color,
    required this.isNegative,
  });
  final String name;
  final String balance;
  final String type;
  final Color color;
  final bool isNegative;
}

class NativeAccountsWidget extends StatelessWidget {
  const NativeAccountsWidget({
    required this.accounts,
    required this.accountCount,
    super.key,
  });

  final List<NativeAccountEntry> accounts;
  final String accountCount; // e.g. "5 accounts"

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const columns = 3;
    return _NativeCard(
      icon: Icons.grid_view_rounded,
      iconColor: scheme.primary,
      title: 'All accounts',
      subtitle: accountCount,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = AppSpacing.xs;
          final tileWidth =
              ((constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 300.0) -
                  spacing * (columns - 1)) /
              columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final acc in accounts)
                SizedBox(
                  width: tileWidth,
                  child: _AccountTileNative(entry: acc),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountTileNative extends StatelessWidget {
  const _AccountTileNative({required this.entry});
  final NativeAccountEntry entry;

  @override
  Widget build(BuildContext context) {
    final foreground = _legibleForeground(entry.color);
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: entry.color,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                _typeIcon(entry.type),
                color: foreground.withValues(alpha: 0.78),
                size: 13,
              ),
              const SizedBox(width: AppSpacing.xxxs),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxxs),
          Text(
            entry.balance,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground.withValues(alpha: 0.94),
              height: 1.1,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'bank' || 'checking' => Icons.account_balance_outlined,
      'savings' => Icons.savings_outlined,
      'credit' => Icons.credit_card_outlined,
      'cash' => Icons.money_outlined,
      'investment' || 'stock' => Icons.trending_up_rounded,
      'loan' => Icons.receipt_long_outlined,
      _ => Icons.account_balance_wallet_outlined,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Recent Records
// ─────────────────────────────────────────────────────────────────────────────

class NativeTransactionEntry {
  const NativeTransactionEntry({
    required this.name,
    required this.accountName,
    required this.dateLabel,
    required this.amountText,
    required this.isExpense,
    required this.isTransfer,
  });
  final String name;
  final String accountName;
  final String dateLabel;
  final String amountText;
  final bool isExpense;
  final bool isTransfer;
}

class NativeRecentWidget extends StatelessWidget {
  const NativeRecentWidget({required this.transactions, super.key});

  final List<NativeTransactionEntry> transactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positive = _positiveColor(scheme);

    return _NativeCard(
      icon: Icons.format_list_bulleted_rounded,
      iconColor: scheme.error,
      title: 'Recent records',
      child: transactions.isEmpty
          ? const _EmptyMessage(
              icon: Icons.receipt_long_outlined,
              message: 'No recent transactions',
            )
          : Column(
              children: [
                for (int i = 0; i < transactions.length; i++) ...[
                  _NativeTxnRow(
                    entry: transactions[i],
                    positiveColor: positive,
                    errorColor: scheme.error,
                  ),
                  if (i < transactions.length - 1)
                    const SizedBox(height: AppSpacing.xxs),
                ],
              ],
            ),
    );
  }
}

class _NativeTxnRow extends StatelessWidget {
  const _NativeTxnRow({
    required this.entry,
    required this.positiveColor,
    required this.errorColor,
  });
  final NativeTransactionEntry entry;
  final Color positiveColor;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountColor = entry.isTransfer
        ? scheme.onSurfaceVariant
        : (entry.isExpense ? errorColor : positiveColor);
    final iconColor = entry.isTransfer
        ? scheme.secondary
        : (entry.isExpense ? errorColor : positiveColor);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              entry.isTransfer
                  ? Icons.swap_horiz_rounded
                  : (entry.isExpense
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded),
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${entry.accountName} · ${entry.dateLabel}',
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
          Text(
            entry.amountText,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Upcoming & Due
// ─────────────────────────────────────────────────────────────────────────────

class NativeUpcomingEntry {
  const NativeUpcomingEntry({
    required this.name,
    required this.accountName,
    required this.amountText,
    required this.daysUntilDue,
  });
  final String name;
  final String accountName;
  final String amountText;
  final int daysUntilDue; // <0 = overdue, 0 = today, 1 = tomorrow, etc.
}

class NativeUpcomingWidget extends StatelessWidget {
  const NativeUpcomingWidget({
    required this.entries,
    required this.dueSoonCount,
    required this.totalAmountDue,
    required this.overdueCount,
    super.key,
  });

  final List<NativeUpcomingEntry> entries;
  final int dueSoonCount;
  final String totalAmountDue;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = overdueCount > 0
        ? '$overdueCount overdue · Scheduled payments and bills'
        : 'Scheduled payments and bills';

    return _NativeCard(
      icon: Icons.event_available_outlined,
      iconColor: scheme.secondary,
      title: 'Upcoming & due',
      subtitle: subtitle,
      child: Column(
        children: [
          // Metric row (matches UpcomingDueHomeWidget)
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: 'Due soon',
                  value: '$dueSoonCount',
                  color: overdueCount > 0 ? scheme.error : _positiveColor(scheme),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _MetricBox(
                  label: 'Amount',
                  value: totalAmountDue,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < entries.length; i++) ...[
              _UpcomingRowNative(entry: entries[i]),
              if (i < entries.length - 1)
                const SizedBox(height: AppSpacing.xxs),
            ],
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            const _EmptyMessage(
              icon: Icons.event_available_outlined,
              message: 'No scheduled records yet',
            ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingRowNative extends StatelessWidget {
  const _UpcomingRowNative({required this.entry});
  final NativeUpcomingEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOverdue = entry.daysUntilDue < 0;
    final isToday = entry.daysUntilDue == 0;

    final (badgeText, badgeColor, badgeTextColor) = switch (entry.daysUntilDue) {
      < 0 => ('OVERDUE', scheme.errorContainer, scheme.onErrorContainer),
      0 => ('TODAY', scheme.errorContainer, scheme.onErrorContainer),
      1 => ('TOMORROW', scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (
        'IN ${entry.daysUntilDue}D',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isOverdue || isToday
            ? scheme.error.withValues(alpha: 0.06)
            : scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isOverdue || isToday
              ? scheme.error.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isOverdue || isToday ? scheme.error : scheme.primary)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              Icons.event_outlined,
              size: 20,
              color: isOverdue || isToday ? scheme.error : scheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        badgeText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: badgeTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        entry.accountName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            entry.amountText,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: isOverdue || isToday ? scheme.error : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Daily Safe-to-Spend
// ─────────────────────────────────────────────────────────────────────────────

class NativeSafeSpendWidget extends StatelessWidget {
  const NativeSafeSpendWidget({
    required this.dailyAllowance,
    required this.spentToday,
    required this.spentRatio,
    required this.remainingDays,
    required this.dayOfMonth,
    required this.daysInMonth,
    super.key,
  });

  final String dailyAllowance;
  final String spentToday;
  final double spentRatio; // 0.0 – 1.0
  final int remainingDays;
  final int dayOfMonth;
  final int daysInMonth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positive = _positiveColor(scheme);
    final progressColor =
        spentRatio > 0.9 ? scheme.error : positive;
    final pct = (spentRatio * 100).round();

    return _NativeCard(
      icon: Icons.speed_outlined,
      iconColor: scheme.primary,
      title: 'Daily safe-to-spend',
      subtitle: '$remainingDays days remaining in this month',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big daily allowance + day pill
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Allowance",
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dailyAllowance,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                          letterSpacing: -0.5,
                        ),
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
          // Spent today / % used
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spent today: $spentToday',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$pct% used',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: progressColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              height: 6,
              color: scheme.surfaceContainerHighest,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: spentRatio.clamp(0.0, 1.0),
                  child: Container(color: progressColor),
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
// 6. Calendar / Today's Pace
// ─────────────────────────────────────────────────────────────────────────────

class NativeCalendarWidget extends StatelessWidget {
  const NativeCalendarWidget({
    required this.monthLabel,
    required this.spentToday,
    required this.spentThisMonth,
    super.key,
  });

  final String monthLabel;
  final String spentToday;
  final String spentThisMonth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _NativeCard(
      icon: Icons.calendar_month_rounded,
      iconColor: scheme.tertiary,
      title: monthLabel,
      child: Row(
        children: [
          Expanded(
            child: _MetricBox(
              label: 'Spent Today',
              value: spentToday,
              color: scheme.error,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _MetricBox(
              label: 'This Month',
              value: spentThisMonth,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Quick Actions (static — no live data)
// ─────────────────────────────────────────────────────────────────────────────

class NativeQuickActionsWidget extends StatelessWidget {
  const NativeQuickActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _NativeCard(
      icon: Icons.flash_on_rounded,
      iconColor: scheme.primary,
      title: 'Quick actions',
      subtitle: 'Tap to open 1Wallet',
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.arrow_upward_rounded,
            label: 'Expense',
            color: scheme.error,
          ),
          const SizedBox(width: AppSpacing.xs),
          _ActionButton(
            icon: Icons.arrow_downward_rounded,
            label: 'Income',
            color: _positiveColor(scheme),
          ),
          const SizedBox(width: AppSpacing.xs),
          _ActionButton(
            icon: Icons.document_scanner_outlined,
            label: 'Scan',
            color: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxxs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticPill extends StatelessWidget {
  const _StaticPill({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

Color _positiveColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? const Color(0xFF8ED99F)
        : const Color(0xFF137A3A);

Color _legibleForeground(Color background) {
  const light = Colors.white;
  const dark = Colors.black;
  double contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  return contrastRatio(background, light) >= contrastRatio(background, dark)
      ? light
      : dark;
}
