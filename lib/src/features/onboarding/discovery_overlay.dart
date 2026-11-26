import 'package:flutter/material.dart';

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
            'Your first account is set up. Want a quick hands-on look around?',
        onClose: onFinish,
        actions: Wrap(
          children: [
            FilledButton(onPressed: onStart, child: const Text('Show me')),
            TextButton(onPressed: onFinish, child: const Text('Not now')),
          ],
        ),
      );
    }
    if (progress.status == DiscoveryStatus.completion) {
      return DiscoveryCoachMark(
        target: dashboardTarget,
        title: 'The essentials, covered',
        message:
            'Next: plans, loans, forecasts and how captured alerts find the right account. Or stop here and explore later in Settings.',
        onClose: onFinish,
        actions: Wrap(
          children: [
            if (onExploreWorkflows != null)
              FilledButton(
                onPressed: onExploreWorkflows,
                child: const Text('Explore workflows'),
              ),
            TextButton(onPressed: onFinish, child: const Text('Done')),
          ],
        ),
      );
    }
    final step = progress.step;
    final (title, message, tab) = switch (step) {
      0 => (
        'Your money, at a glance',
        'Balances and recent activity live here. Tap a card to explore it.',
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
        'Tap a calendar date to open its real day sheet: records, planned activity and end-of-day balance.',
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
      5 when !needsTab => profileTarget,
      _ => navigationTarget,
    };
    final tabName = ['Home', 'History', 'Calendar', 'Accounts'][tab];
    return DiscoveryCoachMark(
      target: target,
      title: title,
      message: message,
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
