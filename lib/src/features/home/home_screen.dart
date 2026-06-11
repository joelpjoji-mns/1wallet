import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_controller.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/user_identity_widgets.dart';
import '../notifications/notification_engine.dart';
import 'home_widget_models.dart';
import 'home_widgets.dart';

final homeSelectedAccountProvider = StateProvider<String?>((ref) => null);

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

    return AppScreen(
      title: '1Wallet',
      onMenuPressed: onMenuPressed,
      floatingActionButton: IslandFloatingActionButton(
        icon: Icons.add_rounded,
        tooltip: 'Add record',
        onPressed: () => context.push('/add'),
      ),
      actions: [
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
      ),
    );
  }
}

class _HomeDashboardList extends ConsumerWidget {
  const _HomeDashboardList({
    required this.widgetOrder,
    required this.onTabSelected,
  });

  final List<HomeDashboardWidgetId> widgetOrder;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSizes.bottomBarClearance,
      ),
      itemCount: widgetOrder.length,
      separatorBuilder: (context, index) => const Gap(12),
      itemBuilder: (context, index) => buildHomeDashboardWidget(
        context: context,
        id: widgetOrder[index],
        state: state,
        onTabSelected: onTabSelected,
      ),
    );
  }
}
