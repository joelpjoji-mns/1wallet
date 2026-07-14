import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_user.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/exchange_rate_service.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/user_identity_widgets.dart';
import '../../widgets/bottom_island_nav.dart';
import 'main_drawer_components.dart';
import '../accounts/accounts_screen.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../notifications/notification_engine.dart';
import '../../services/notification_service.dart';
import '../planner/planner_screen.dart';
import '../transactions/transactions_screen.dart';
import '../updates/app_update_provider.dart';
import '../../widgets/app_kit.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _pageController;
  final ValueNotifier<int> _selectedIndex = ValueNotifier(0);
  double _dragDistance = 0;
  double _dragVertical = 0;

  static const _tabs = [
    IslandTabItem(
      title: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    IslandTabItem(
      title: 'History',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      pageIndex: 1,
    ),
    IslandTabItem(
      title: 'Calendar',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      pageIndex: 2,
    ),
    IslandTabItem(
      title: 'Planner',
      icon: Icons.stacked_line_chart_rounded,
      activeIcon: Icons.stacked_line_chart_rounded,
      pageIndex: 3,
    ),
    IslandTabItem(
      title: 'Accounts',
      icon: Icons.wallet_outlined,
      activeIcon: Icons.wallet_rounded,
      pageIndex: 4,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(exchangeRateServiceProvider).refreshRatesIfStale();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(exchangeRateServiceProvider).refreshRatesIfStale();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _selectTab(int index) {
    if (_selectedIndex.value != index) {
      _selectedIndex.value = index;
    }
    if (!_pageController.hasClients) return;
    final currentPage = _pageController.page?.round();
    if (currentPage == index) return;
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LedgerState>(ledgerProvider, (previous, next) {
      NotificationService.checkAndShowAlerts(next);
      if (!identical(previous?.transactions, next.transactions)) {
        NotificationService.syncScheduledNotifications(next);
      }
    });

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          Navigator.of(context).pop();
          return true;
        }
        if (_selectedIndex.value == 0) return false;
        _selectTab(0);
        return true;
      },
      child: ValueListenableBuilder<int>(
        valueListenable: _selectedIndex,
        builder: (context, selectedIndex, child) {
          Widget mainBody = NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                final page = _pageController.page?.round() ?? 0;
                if (_selectedIndex.value != page) {
                  _selectedIndex.value = page;
                }
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
              dragStartBehavior: DragStartBehavior.down,
              itemCount: _tabs.length,
              onPageChanged: (index) {
                // Index update deferred to ScrollEndNotification to prevent mid-swipe jank.
              },
              itemBuilder: (context, index) {
                return _KeepAliveWrapper(
                  key: PageStorageKey<String>('main-shell-tab-$index'),
                  child: _buildScreen(index),
                );
              },
            ),
          );

          Widget mobileBody = Listener(
            onPointerDown: (_) {
              _dragDistance = 0;
              _dragVertical = 0;
            },
            onPointerMove: (event) {
              if (_selectedIndex.value == 0 && _dragDistance > -1000) {
                _dragDistance += event.delta.dx;
                _dragVertical += event.delta.dy;

                // If the user is scrolling vertically, cancel the horizontal drawer swipe
                if (_dragVertical.abs() > 20 &&
                    _dragVertical.abs() > _dragDistance.abs()) {
                  _dragDistance = -1000;
                  return;
                }

                if (_dragDistance > 60) {
                  if (!(_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
                    _scaffoldKey.currentState?.openDrawer();
                  }
                  _dragDistance = -1000;
                } else if (_dragDistance < -20) {
                  _dragDistance =
                      -1000; // prevent triggering if swiped left first
                }
              }
            },
            child: Stack(
              children: [
                mainBody,
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height:
                          AppSizes.bottomBarClearance +
                          MediaQuery.paddingOf(context).bottom,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).colorScheme.surface.withAlpha(0),
                            Theme.of(
                              context,
                            ).colorScheme.surface.withAlpha(120),
                            Theme.of(
                              context,
                            ).colorScheme.surface.withAlpha(190),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: BottomIslandNavBar(
                    items: _tabs,
                    selectedIndex: selectedIndex,
                    onSelected: _selectTab,
                    pageController: _pageController,
                  ),
                ),
              ],
            ),
          );

          Widget desktopBody = Container(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppMainDrawer(
                  selectedIndex: selectedIndex,
                  isStatic: true,
                  onTabSelected: _selectTab,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                          horizontal: AppSpacing.md,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withAlpha(120),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(15),
                                blurRadius: 40,
                                offset: const Offset(0, 15),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            child: mainBody,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

          return Scaffold(
            key: _scaffoldKey,
            drawerEnableOpenDragGesture: true,
            drawerEdgeDragWidth: 40,
            drawer: AppResponsiveLayout.isDesktop(context)
                ? null
                : AppMainDrawer(
                    selectedIndex: selectedIndex,
                    onTabSelected: (index) {
                      Navigator.of(context).pop();
                      _selectTab(index);
                    },
                  ),
            body: AppResponsiveLayout(mobile: mobileBody, desktop: desktopBody),
          );
        },
      ),
    );
  }

  Widget _buildScreen(int index) {
    return switch (index) {
      0 => HomeScreen(onMenuPressed: _openDrawer, onTabSelected: _selectTab),
      1 => TransactionsScreen(onMenuPressed: _openDrawer),
      2 => CalendarScreen(onMenuPressed: _openDrawer),
      3 => PlannerScreen(onMenuPressed: _openDrawer),
      4 => AccountsScreen(onMenuPressed: _openDrawer),
      _ => const SizedBox.shrink(),
    };
  }
}

class AppMainDrawer extends ConsumerWidget {
  const AppMainDrawer({
    required this.selectedIndex,
    required this.onTabSelected,
    this.isStatic = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool isStatic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authControllerProvider);
    final ledger = ref.watch(ledgerProvider);
    final sync = ref.watch(cloudSyncControllerProvider);
    final updateState = ref.watch(appUpdateProvider);
    final pendingReviewCount = _pendingReviewCount(ledger);
    final notificationCount = buildNotificationInbox(ledger).length;
    final syncBadge = _syncBadge(sync);
    final updatesBadge =
        updateState.latestRelease != null &&
            updateState.status == UpdateStatus.idle
        ? '!'
        : null;
    final profileName = _profileName(auth.user, ledger);
    final profileSubtitle = _profileSubtitle(auth.user, ledger);
    final profileInitials = auth.user?.initials ?? _walletInitials(profileName);

    Widget content = SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              scheme.surfaceContainerLow,
              scheme.surface,
            ],
          ),
          border: Border.all(color: scheme.outlineVariant.withAlpha(180)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primaryContainer.withAlpha(220),
                      scheme.surfaceContainerHigh,
                      scheme.tertiaryContainer.withAlpha(180),
                    ],
                  ),
                  border: Border.all(
                    color: scheme.outlineVariant.withAlpha(180),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AuthUserAvatar(
                          user: auth.user,
                          radius: 26,
                          fallbackLabel: profileInitials,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: scheme.onSurface,
                                      letterSpacing: -0.6,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                profileSubtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Metrics and badges removed as requested
                    const SizedBox(height: AppSpacing.md),
                    const _DrawerPrivacyToggle(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  DrawerSection(
                    title: 'Main',
                    titleColor: scheme.primary,
                    icon: Icons.bolt_rounded,
                    surfaceTint: scheme.primary,
                    rows: [
                      DrawerRowConfig.tab('Home', Icons.dashboard_outlined, 0),
                      DrawerRowConfig.route(
                        'Review',
                        Icons.smart_toy_outlined,
                        '/review',
                        badge: _countBadge(pendingReviewCount),
                      ),
                      DrawerRowConfig.route(
                        'Planned payments',
                        Icons.event_repeat_outlined,
                        '/recurring',
                      ),
                      DrawerRowConfig.route(
                        'Loans',
                        Icons.account_balance_outlined,
                        '/loans',
                      ),
                    ],
                    selectedIndex: selectedIndex,
                    onTabSelected: onTabSelected,
                  ),
                  DrawerSection(
                    title: 'Planning & money',
                    titleColor: scheme.secondary,
                    icon: Icons.timeline_rounded,
                    surfaceTint: scheme.secondary,
                    rows: [
                      DrawerRowConfig.route(
                        'Loan forecast',
                        Icons.show_chart_rounded,
                        '/loans/forecast',
                      ),
                      DrawerRowConfig.route(
                        'Budgets',
                        Icons.donut_large_outlined,
                        '/budgets/new',
                      ),
                      DrawerRowConfig.route(
                        'Goals',
                        Icons.flag_outlined,
                        '/goals/new',
                      ),
                      DrawerRowConfig.route(
                        'Categories',
                        Icons.category_outlined,
                        '/categories',
                      ),
                    ],
                    selectedIndex: selectedIndex,
                    onTabSelected: onTabSelected,
                  ),
                  DrawerSection(
                    title: 'Tools',
                    icon: Icons.build_circle_outlined,
                    surfaceTint: scheme.primary,
                    rows: [
                      DrawerRowConfig.route(
                        'Currencies',
                        Icons.currency_exchange_outlined,
                        '/currencies',
                      ),
                      DrawerRowConfig.route(
                        'Widgets',
                        Icons.dashboard_customize_outlined,
                        '/widgets',
                      ),
                      DrawerRowConfig.route(
                        'Sync',
                        Icons.cloud_done_outlined,
                        '/sync',
                        badge: syncBadge,
                      ),
                      DrawerRowConfig.route(
                        'Auto Capture',
                        Icons.notifications_active_outlined,
                        '/auto-capture',
                      ),
                      DrawerRowConfig.route(
                        'Import & backup',
                        Icons.folder_copy_outlined,
                        '/imports',
                      ),
                      DrawerRowConfig.route(
                        'Notifications',
                        Icons.notifications_none,
                        '/notifications',
                        badge: _countBadge(notificationCount),
                      ),
                    ],
                    selectedIndex: selectedIndex,
                    onTabSelected: onTabSelected,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.md,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          DrawerRouteTile(
                            config: DrawerRowConfig.route(
                              'Updates',
                              Icons.download_for_offline_outlined,
                              '/updates',
                              badge: updatesBadge,
                            ),
                            selectedIndex: selectedIndex,
                            onTabSelected: onTabSelected,
                            accentColor: scheme.primary,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          DrawerRouteTile(
                            config: DrawerRowConfig.route(
                              'Settings',
                              Icons.settings_outlined,
                              '/settings',
                            ),
                            selectedIndex: selectedIndex,
                            onTabSelected: onTabSelected,
                            accentColor: scheme.primary,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          DrawerRouteTile(
                            config: DrawerRowConfig.route(
                              'Sign out',
                              Icons.logout_outlined,
                              '/login',
                            ),
                            selectedIndex: selectedIndex,
                            onTabSelected: onTabSelected,
                            danger: true,
                            accentColor: scheme.error,
                            onTapOverride: () async {
                              Navigator.of(context).pop();
                              await ref
                                  .read(authControllerProvider.notifier)
                                  .signOut();
                              if (context.mounted) context.go('/login');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isStatic) {
      return SizedBox(width: 320, child: content);
    }

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.82,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: content,
    );
  }
}

/// Prominent, always-visible Privacy mode toggle in the drawer header so it is
/// one tap away instead of buried in Settings.
class _DrawerPrivacyToggle extends ConsumerWidget {
  const _DrawerPrivacyToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = ref.watch(
      ledgerProvider.select((s) => s.preferences.privacyModeEnabled),
    );
    void toggle() {
      final notifier = ref.read(ledgerProvider.notifier);
      final prefs = ref.read(ledgerProvider).preferences;
      notifier.updatePreferences(
        prefs.copyWith(privacyModeEnabled: !prefs.privacyModeEnabled),
      );
    }

    return Material(
      color: enabled
          ? scheme.primary.withAlpha(28)
          : scheme.surface.withAlpha(160),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Row(
            children: [
              Icon(
                enabled
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  enabled ? 'Privacy mode · On' : 'Privacy mode · Off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              IgnorePointer(
                child: Switch(
                  value: enabled,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _pendingReviewCount(LedgerState ledger) {
  return ledger.captureCandidates
      .where((candidate) => candidate.status == 'pending')
      .length;
}

String? _countBadge(int count) => count <= 0 ? null : count.toString();

String? _syncBadge(CloudSyncState sync) {
  if (sync.phase == CloudSyncPhase.error) return '!';
  if (sync.pendingUpload || sync.phase == CloudSyncPhase.uploading) {
    return 'sync';
  }
  return null;
}

String _profileName(AuthUser? user, LedgerState ledger) {
  final displayName = user?.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  final email = user?.email.trim();
  if (email != null && email.isNotEmpty) return email;
  return '${ledger.preferences.displayCurrency} wallet';
}

String _profileSubtitle(AuthUser? user, LedgerState ledger) {
  final accountCount = ledger.accounts
      .where((account) => !account.isArchived)
      .length;
  return 'My Wallet · $accountCount account${accountCount == 1 ? '' : 's'}';
}

String _walletInitials(String source) {
  final parts = source
      .split(RegExp(r'\s+|@'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return '1W';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

class _KeepAliveWrapper extends StatefulWidget {
  const _KeepAliveWrapper({required this.child, super.key});
  final Widget child;

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
