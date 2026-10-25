import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
final homeWidgetReorderModeProvider = StateProvider.autoDispose<bool>(
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
    final reorderMode = ref.watch(homeWidgetReorderModeProvider);

    return AppScreen(
      title: '1Wallet',
      onMenuPressed: onMenuPressed,
      actions: [
        if (reorderMode)
          IconButton(
            tooltip: 'Reset widget order',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () {
              ref.read(ledgerProvider.notifier).resetHomeWidgetOrder();
            },
          ),
        if (reorderMode)
          HeaderIconButton(
            icon: Icons.check_rounded,
            semanticLabel: 'Done reordering widgets',
            onPressed: () =>
                ref.read(homeWidgetReorderModeProvider.notifier).state = false,
          ),

        HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          badge: pendingCount + notificationCount,
          onPressed: () => context.push('/notifications'),
          semanticLabel: 'Notifications',
        ),
        UnconstrainedBox(
          child: Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: AuthUserActionButton(
              user: user,
              radius: 14,
              tooltip: 'Open profile and settings',
              onPressed: () => context.push('/settings'),
            ),
          ),
        ),
      ],
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: 1400,
      child: Column(
        children: [
          Expanded(
            child: AppTopFadeMask(
              child: _HomeDashboardList(
                widgetOrder: widgetOrder,
                onTabSelected: onTabSelected,
                reorderMode: reorderMode,
              ),
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
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      AppSizes.bottomBarClearance + MediaQuery.paddingOf(context).bottom,
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
    ref.read(homeWidgetReorderModeProvider.notifier).state = true;
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
    HomeDashboardWidgetId.topCategories => 'Categories',
    HomeDashboardWidgetId.currencyValues => 'Currency calculator',
    HomeDashboardWidgetId.creditUtilization => 'Credit Utilization',
    HomeDashboardWidgetId.netWorth => 'Net Worth',
  };
}
