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
    ledgerProvider.select((state) => buildNotificationInbox(state).length),
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
            onPressed: () => ref
                .read(_homeWidgetReorderModeProvider.notifier)
                .state = false,
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
      child: _HomeDashboardList(
        widgetOrder: widgetOrder,
        onTabSelected: onTabSelected,
        reorderMode: reorderMode,
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
    if (reorderMode) {
      return ReorderableListView.builder(
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
    }

    return ListView.separated(
      padding: padding,
      itemCount: widgetOrder.length,
      separatorBuilder: (context, index) => const Gap(12),
      itemBuilder: (context, index) => _buildScopedHomeWidget(
        context,
        ref,
        state,
        index,
      ),
    );
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

  void _saveHomeWidgetOrder(
    WidgetRef ref,
    List<HomeDashboardWidgetId> next,
  ) {
    ref
        .read(ledgerProvider.notifier)
        .setHomeWidgetOrder(next.map((item) => item.storageKey).toList());
  }
}

String _homeWidgetLabel(HomeDashboardWidgetId id) {
  return switch (id) {
    HomeDashboardWidgetId.balanceHero => 'Balance Hero',
    HomeDashboardWidgetId.plannedPaymentsTile => 'Planned Payments',
    HomeDashboardWidgetId.loansTile => 'Loans',
    HomeDashboardWidgetId.accountGrid => 'Accounts',
    HomeDashboardWidgetId.summaryTiles => 'Finance Summary',
    HomeDashboardWidgetId.recentRecords => 'Recent Records',
    HomeDashboardWidgetId.upcomingScheduled => 'Upcoming Scheduled',
    HomeDashboardWidgetId.dueNow => 'Due Now',
    HomeDashboardWidgetId.emiTracker => 'EMI Tracker',
    HomeDashboardWidgetId.cardDebt => 'Cards',
    HomeDashboardWidgetId.accountGroups => 'Account Groups',
    HomeDashboardWidgetId.reviewQueue => 'Review Queue',
    HomeDashboardWidgetId.automationHealth => 'Automation Health',
    HomeDashboardWidgetId.cashflowForecast => 'Cashflow Forecast',
    HomeDashboardWidgetId.billWatch => 'Bill Watch',
    HomeDashboardWidgetId.cardPaymentPlan => 'Card Payment Plan',
    HomeDashboardWidgetId.loanPayoff => 'Loan Payoff',
    HomeDashboardWidgetId.savingsRunway => 'Savings Runway',
    HomeDashboardWidgetId.cashflowBook => 'Cashflow Book',
    HomeDashboardWidgetId.balanceTrend => 'Balance Trend',
    HomeDashboardWidgetId.topCategories => 'Top Categories',
    HomeDashboardWidgetId.incomeMix => 'Income Mix',
    HomeDashboardWidgetId.currencyValues => 'Currency Values',
    HomeDashboardWidgetId.budgetPressure => 'Budget Pressure',
    HomeDashboardWidgetId.goalProgress => 'Goal Progress',
    HomeDashboardWidgetId.currencyExposure => 'Currency Exposure',
  };
}
