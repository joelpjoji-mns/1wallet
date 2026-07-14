import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../cloud_sync/cloud_sync_controller.dart';

import '../../auth/auth_controller.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/user_identity_widgets.dart';
import '../notifications/notification_engine.dart';
import 'home_widget_card.dart';
import 'home_widget_models.dart';
import 'home_widgets.dart';

final homeSelectedAccountProvider = StateProvider<String?>((ref) => null);
final _homeWidgetReorderModeProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
);

final _homePendingCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(
    ledgerProvider.select(
      (state) => state.captureCandidates
          .where((candidate) => candidate.status == 'pending')
          .length,
    ),
  );
});

final _homeNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(
    ledgerProvider.select((state) => unreadNotificationCount(state)),
  );
});

final _homeAuthUserProvider = Provider.autoDispose((ref) {
  return ref.watch(authControllerProvider.select((state) => state.user));
});

final _homeWidgetOrderProvider =
    Provider.autoDispose<List<HomeDashboardWidgetId>>((ref) {
      final preferences = ref.watch(
        ledgerProvider.select((state) => state.preferences),
      );
      return resolveHomeWidgetOrder(
        preferences.homeWidgetOrder,
        hidden: preferences.homeWidgetHidden,
      );
    });

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.onMenuPressed,
    required this.onTabSelected,
    super.key,
  });

  final VoidCallback onMenuPressed;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(_homePendingCountProvider);
    final notificationCount = ref.watch(_homeNotificationCountProvider);
    final widgetOrder = ref.watch(_homeWidgetOrderProvider);
    final user = ref.watch(_homeAuthUserProvider);
    final selectedAccountId = ref.watch(homeSelectedAccountProvider);
    final reorderMode = ref.watch(_homeWidgetReorderModeProvider);

    final sync = ref.watch(cloudSyncControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget? syncIndicator;
    if (sync.phase == CloudSyncPhase.checking ||
        sync.phase == CloudSyncPhase.restoring ||
        sync.phase == CloudSyncPhase.uploading) {
      final message = sync.progressMessage ??
          (sync.phase == CloudSyncPhase.checking
              ? 'Checking cloud updates…'
              : (sync.phase == CloudSyncPhase.restoring
                  ? 'Downloading latest database…'
                  : 'Uploading latest changes…'));
      syncIndicator = Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withOpacity(0.35),
          border: Border(
            bottom: BorderSide(
              color: scheme.primary.withOpacity(0.15),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            if (sync.progress != null) ...[
              const SizedBox(width: 8),
              Text(
                '${(sync.progress! * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (sync.phase == CloudSyncPhase.error) {
      syncIndicator = Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          border: Border(
            bottom: BorderSide(color: scheme.error.withOpacity(0.3), width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                sync.error ?? 'Sync failed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref.read(cloudSyncControllerProvider.notifier).fullSync(reason: 'user_retry');
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Retry', style: TextStyle(fontSize: 12, color: scheme.onErrorContainer, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return AppScreen(
      title: '1Wallet',
      onMenuPressed: onMenuPressed,
      floatingActionButton: reorderMode
          ? null
          : IslandFloatingActionButton(
              icon: Icons.add_rounded,
              tooltip: 'Add record',
              onPressed: () {
                if (selectedAccountId == null ||
                    selectedAccountId == 'cash_group') {
                  context.push('/add');
                  return;
                }
                context.push(
                  Uri(
                    path: '/add',
                    queryParameters: {'accountId': selectedAccountId},
                  ).toString(),
                );
              },
            ),
      actions: [
        if (reorderMode)
          IconButton(
            tooltip: 'Reset widget order',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () {
              ref.read(ledgerProvider.notifier).resetHomeWidgetOrder();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Home widgets reset'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
        if (reorderMode)
          IconButton(
            tooltip: 'Done reordering widgets',
            icon: const Icon(Icons.check_rounded),
            onPressed: () =>
                ref.read(_homeWidgetReorderModeProvider.notifier).state = false,
          ),
        HeaderIconButton(
          icon: Icons.search_rounded,
          onPressed: () => onTabSelected(1),
        ),
        HeaderIconButton(
          icon: Icons.fact_check_outlined,
          badge: pendingCount,
          onPressed: () => context.push('/review'),
        ),
        HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          badge: notificationCount,
          onPressed: () => context.push('/notifications'),
        ),
        AuthUserActionButton(
          user: user,
          tooltip: 'Open profile and settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: 1400,
      child: Column(
        children: [
          if (syncIndicator != null) syncIndicator,
          Expanded(
            child: _HomeDashboardList(
              widgetOrder: widgetOrder,
              onTabSelected: onTabSelected,
              reorderMode: reorderMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeDashboardList extends ConsumerWidget {
  const _HomeDashboardList({
    required this.widgetOrder,
    required this.onTabSelected,
    required this.reorderMode,
  });

  final List<HomeDashboardWidgetId> widgetOrder;
  final ValueChanged<int> onTabSelected;
  final bool reorderMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    const padding = EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      AppSizes.bottomBarClearance,
    );

    Widget mobileView;
    if (reorderMode) {
      mobileView = ReorderableListView.builder(
        padding: padding,
        itemCount: widgetOrder.length,
        onReorderItem: (oldIndex, newIndex) {
          _reorderHomeWidgets(ref, oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          return Padding(
            key: ValueKey('home-widget-${widgetOrder[index].storageKey}'),
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _buildScopedHomeWidget(context, ref, state, index),
          );
        },
      );
    } else {
      mobileView = ListView.separated(
        padding: padding,
        itemCount: widgetOrder.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _buildScopedHomeWidget(context, ref, state, index),
      );
    }
    final leftColIds = <HomeDashboardWidgetId>[];
    final midColIds = <HomeDashboardWidgetId>[];
    final rightColIds = <HomeDashboardWidgetId>[];
    for (var i = 0; i < widgetOrder.length; i++) {
      if (i % 3 == 0) {
        leftColIds.add(widgetOrder[i]);
      } else if (i % 3 == 1) {
        midColIds.add(widgetOrder[i]);
      } else {
        rightColIds.add(widgetOrder[i]);
      }
    }

    final desktopView = SingleChildScrollView(
      padding: padding,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: leftColIds.map((id) {
                    final index = widgetOrder.indexOf(id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _buildScopedHomeWidget(context, ref, state, index),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  children: midColIds.map((id) {
                    final index = widgetOrder.indexOf(id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _buildScopedHomeWidget(context, ref, state, index),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  children: rightColIds.map((id) {
                    final index = widgetOrder.indexOf(id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _buildScopedHomeWidget(context, ref, state, index),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return AppResponsiveLayout(mobile: mobileView, desktop: desktopView);
  }

  Widget _buildScopedHomeWidget(
    BuildContext context,
    WidgetRef ref,
    LedgerState state,
    int index,
  ) {
    final id = widgetOrder[index];
    return HomeWidgetCardReorderScope(
      reorderMode: reorderMode,
      index: index,
      label: _homeWidgetLabel(id),
      onEnterReorderMode: () => _enterReorderMode(context, ref),
      canMoveUp: index > 0,
      canMoveDown: index < widgetOrder.length - 1,
      onMoveUp: () => _moveHomeWidget(ref, index, index - 1),
      onMoveDown: () => _moveHomeWidget(ref, index, index + 1),
      child: buildHomeDashboardWidget(
        context: context,
        id: id,
        state: state,
        onTabSelected: onTabSelected,
      ),
    );
  }

  void _enterReorderMode(BuildContext context, WidgetRef ref) {
    ref.read(_homeWidgetReorderModeProvider.notifier).state = true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Drag widget icons to rearrange Home.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _reorderHomeWidgets(WidgetRef ref, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= widgetOrder.length ||
        newIndex < 0 ||
        newIndex >= widgetOrder.length) {
      return;
    }
    final next = widgetOrder.toList();
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    _saveHomeWidgetOrder(ref, next);
  }

  void _moveHomeWidget(WidgetRef ref, int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= widgetOrder.length ||
        newIndex < 0 ||
        newIndex >= widgetOrder.length) {
      return;
    }
    final next = widgetOrder.toList();
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    _saveHomeWidgetOrder(ref, next);
  }

  void _saveHomeWidgetOrder(WidgetRef ref, List<HomeDashboardWidgetId> next) {
    ref
        .read(ledgerProvider.notifier)
        .setHomeWidgetOrder(next.map((item) => item.storageKey).toList());
  }
}

String _homeWidgetLabel(HomeDashboardWidgetId id) {
  return switch (id) {
    HomeDashboardWidgetId.balanceHero => 'Balance Hero',
    HomeDashboardWidgetId.plannedPaymentsTile => 'Planned Payments',
    HomeDashboardWidgetId.loansTile => 'Loans & EMIs',
    HomeDashboardWidgetId.accountGrid => 'All accounts',
    HomeDashboardWidgetId.recentRecords => 'Recent Records',
    HomeDashboardWidgetId.upcomingScheduled => 'Upcoming & due',
    HomeDashboardWidgetId.emiTracker => 'Loans & EMIs',
    HomeDashboardWidgetId.cardDebt => 'Cards',
    HomeDashboardWidgetId.accountGroups => 'Account Groups',
    HomeDashboardWidgetId.cardPaymentPlan => 'Card Payment Plan',
    HomeDashboardWidgetId.loanPayoff => 'Loans & EMIs',
    HomeDashboardWidgetId.balanceTrend => 'Balance Trend',
    HomeDashboardWidgetId.topCategories => 'Top Categories',
    HomeDashboardWidgetId.currencyValues => 'Currency calculator',
    HomeDashboardWidgetId.budgetPressure => 'Budget Pressure',
    HomeDashboardWidgetId.goalProgress => 'Goal Progress',
    HomeDashboardWidgetId.creditUtilization => 'Credit Utilization',
    HomeDashboardWidgetId.netWorth => 'Net Worth',
    HomeDashboardWidgetId.cashFlow => 'Cash Flow',
    HomeDashboardWidgetId.financialHealth => 'Financial Health',
    HomeDashboardWidgetId.monthComparison => 'Spending vs Last Month',
    HomeDashboardWidgetId.spendingHeatmap => 'Spending Heatmap',
  };
}
