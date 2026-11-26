import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'discovery_coach_mark.dart';
import 'discovery_controller.dart';

class DiscoveryOverlay extends StatelessWidget {
  const DiscoveryOverlay({
    required this.progress,
    required this.dashboardTarget,
    required this.navigationTarget,
    required this.actionTarget,
    required this.profileTarget,
    required this.selectedTab,
    required this.hasAccounts,
    required this.onSelectTab,
    required this.onStart,
    required this.onPause,
    required this.onFinish,
    required this.onPrevious,
    required this.onNext,
    required this.onSkipStep,
    this.onExploreWorkflows,
    this.customTitle,
    this.customDescription,
    this.onCustomDismiss,
    this.targets,
    this.onSwitchMonth,
    this.onOpenDay,
    super.key,
  });

  final DiscoveryProgress progress;
  final GlobalKey dashboardTarget;
  final GlobalKey navigationTarget;
  final GlobalKey actionTarget;
  final GlobalKey profileTarget;
  final int selectedTab;
  final bool hasAccounts;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onFinish;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSkipStep;
  final VoidCallback? onExploreWorkflows;
  final String? customTitle;
  final String? customDescription;
  final VoidCallback? onCustomDismiss;
  final Map<String, GlobalKey>? targets;
  final VoidCallback? onSwitchMonth;
  final VoidCallback? onOpenDay;

  Widget _buildSampleBadge({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String detail,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: isDark ? 0.6 : 0.8),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (progress.status == DiscoveryStatus.dormant ||
        progress.status == DiscoveryStatus.finished ||
        progress.status == DiscoveryStatus.paused) {
      return const SizedBox.shrink();
    }
    if (customTitle != null) {
      return DiscoveryCoachMark(
        target: dashboardTarget,
        title: customTitle!,
        message: customDescription!,
        onClose: onCustomDismiss!,
        actions: TextButton(
          onPressed: onCustomDismiss,
          child: const Text('Try it yourself'),
        ),
      );
    }
    if (progress.status == DiscoveryStatus.welcome) {
      return DiscoveryCoachMark(
        target: dashboardTarget,
        title: 'Your wallet is ready',
        message:
            'Your first account is set up. Let us take a compact, guided walkthrough of your financial command center — from live balances to automated cash flow forecasts.',
        onClose: onStart,
        sample: _buildSampleBadge(
          context: context,
          icon: Icons.auto_awesome_rounded,
          title: 'Interactive 1Wallet Story',
          detail:
              'A single continuous flow: live ledger, forward forecasts, and secure alerts.',
        ),
        actions: FilledButton(
          onPressed: onStart,
          child: const Text('Show me'),
        ),
      );
    }
    if (progress.status == DiscoveryStatus.completion) {
      return DiscoveryCoachMark(
        target: dashboardTarget,
        title: 'The essentials, covered',
        message:
            'You have experienced the full story of 1Wallet — from live balances and forecasts to secure matching.',
        onClose: onFinish,
        sample: _buildSampleBadge(
          context: context,
          icon: Icons.check_circle_outline_rounded,
          title: 'All Features Unlocked',
          detail:
              'Your wallet operates 100% offline-first. Review inbox, forecasts, and backups are ready.',
        ),
        actions: Wrap(
          children: [
            if (onExploreWorkflows != null)
              FilledButton(
                onPressed: onExploreWorkflows,
                child: const Text('Explore workflows'),
              ),
            FilledButton(onPressed: onFinish, child: const Text('Done')),
          ],
        ),
      );
    }
    final step = progress.step;
    final (title, message, tab) = switch (step) {
      0 => (
        'Your money, at a glance',
        'Balances and recent activity live here. Tap a card to explore your liquid assets, monthly cashflow, and total net worth in real time.',
        0,
      ),
      1 when !hasAccounts => (
        'Start with an account',
        'Add a real cash, bank or card account using the highlighted +.',
        3,
      ),
      1 => (
        'Make your first record',
        'Tap the highlighted +. Choose expense, income or transfer; nothing is saved until you press Save.',
        0,
      ),
      2 => (
        'Find any record',
        'History brings your transactions together. Use search and filters, then tap a record for its details.',
        1,
      ),
      3 => (
        'Pick a day',
        'Month-end net balance and forward cashflow forecast live here. The Net combines actual balances with scheduled payments. Navigating to next month recalculates the net dynamically, and tapping any day opens its daily transactions sheet!',
        2,
      ),
      4 => (
        'Your accounts',
        'Tap an account card to edit its details. Secure Details stores credentials and the suffix used to match captured alerts.',
        3,
      ),
      _ => (
        'Make it yours',
        'Your profile opens Settings: privacy, appearance, backup and all the feature guides.',
        0,
      ),
    };
    final needsTab = selectedTab != tab;
    final target = switch (step) {
      0 => dashboardTarget,
      1 when !needsTab => actionTarget,
      3 when !needsTab =>
        targets?['calendar-net'] ??
            targets?['calendar-month-controls'] ??
            targets?['calendar-day'] ??
            navigationTarget,
      5 when !needsTab => profileTarget,
      _ => navigationTarget,
    };
    final tabName = ['Home', 'History', 'Calendar', 'Accounts'][tab];

    final sample = switch (step) {
      0 => _buildSampleBadge(
        context: context,
        icon: Icons.account_balance_wallet_outlined,
        title: 'Consolidated Wealth',
        detail:
            'Liquid: \$1,250.00 · Monthly Net: +\$420.00 · Consolidated in real time',
      ),
      1 => _buildSampleBadge(
        context: context,
        icon: Icons.flash_on_rounded,
        title: 'Offline-First Logging',
        detail:
            '⚡ Quick Log: Expense \$4.50 (Coffee) · ☕ Food & Dining · Cash account',
      ),
      2 => _buildSampleBadge(
        context: context,
        icon: Icons.search_rounded,
        title: 'Instant Search & Filters',
        detail:
            '🔍 Filter by account, category, or date range across all transactions',
      ),
      3 => _buildSampleBadge(
        context: context,
        icon: Icons.calendar_month_rounded,
        title: 'Projected Net & Forecast',
        detail:
            'Net Balance combines actual + planned payments · Tap Next Month to see forecast change',
        trailing: onSwitchMonth != null
            ? TextButton(
                key: const ValueKey('discovery-tour-next-month'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onSwitchMonth,
                child: const Text('Next Month', style: TextStyle(fontSize: 11)),
              )
            : null,
      ),
      4 => _buildSampleBadge(
        context: context,
        icon: Icons.credit_card_outlined,
        title: 'Suffix Alert Matching',
        detail:
            'Suffix 4242 → Auto-matches "Everyday Bank" for SMS / notifications',
      ),
      _ => _buildSampleBadge(
        context: context,
        icon: Icons.shield_outlined,
        title: 'Vault & Privacy',
        detail:
            '🔐 Biometrics · 🛡️ Local AES-256 Backups · 🌐 100% Offline Ledger',
      ),
    };

    return DiscoveryCoachMark(
      target: target,
      title: title,
      message: message,
      sample: sample,
      counter:
          '${step - progress.startStep + 1} / ${progress.endStep - progress.startStep + 1}',
      onClose: onPause,
      actions: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (step > progress.startStep)
            IconButton(
              tooltip: 'Previous tip',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          FilledButton(
            onPressed: needsTab
                ? () => onSelectTab(tab)
                : step == 1
                ? onSkipStep
                : onNext,
            child: Text(
              needsTab
                  ? 'Show $tabName'
                  : step == 1
                  ? 'Try later'
                  : step == progress.endStep
                  ? 'Finish basics'
                  : 'Continue',
            ),
          ),
          IconButton(
            tooltip: 'Skip this tip',
            onPressed: onSkipStep,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }
}
