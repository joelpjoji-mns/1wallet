import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/glass_diagnostics.dart' show GlassProxyScope;
import 'package:go_router/go_router.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_session_teardown.dart';
import '../../auth/auth_user.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/exchange_rate_service.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../offline_mode/offline_mode_controller.dart';
import '../../widgets/user_identity_widgets.dart';
import '../../widgets/bottom_island_nav.dart';
import 'main_drawer_components.dart';
import '../accounts/accounts_screen.dart';
import '../calendar/calendar_screen.dart';
import '../settings/offline_mode_section.dart';
import '../home/home_screen.dart'
    show HomeScreen, homeSelectedAccountProvider, homeWidgetReorderModeProvider;
import '../notifications/notification_engine.dart';
import '../onboarding/discovery_controller.dart';
import '../onboarding/discovery_overlay.dart';
import '../../services/notification_service.dart';
import '../../theme/theme_controller.dart';
import '../transactions/transactions_screen.dart';
import '../../widgets/app_kit.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({this.initialTab = 0, this.routeTabParameter, super.key});

  final int initialTab;
  final String? routeTabParameter;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _discoveryDashboardKey = GlobalKey();
  final _discoveryNavigationKey = GlobalKey();
  final _discoveryActionKey = GlobalKey();
  final _discoveryProfileKey = GlobalKey();
  late final PageController _pageController;
  late final ValueNotifier<int> _selectedIndex;
  Timer? _lightBackgroundPeriodicTimer;
  late final List<Widget> _screens;
  late final Widget _mainBody;
  RouteInformationProvider? _routeInformationProvider;
  RouteInformation? _lastRouteInformation;
  ProviderSubscription<DiscoveryProgress>? _discoverySubscription;
  String? _observedDiscoveryOwner;
  String? _routePausedDiscoveryOwner;
  GoRouter? _discoveryRouter;

  void _noteGlassChange() {
    if (mounted) {
      GlassProxyScope.maybeOf(context)?.noteChange();
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialTab);
    _pageController.addListener(_noteGlassChange);
    _selectedIndex = ValueNotifier(widget.initialTab);
    ref.listenManual<AuthState>(authControllerProvider, (_, next) {
      _observeDiscovery(next.ownerId);
    }, fireImmediately: true);
    _screens = [
      _KeepAliveWrapper(
        key: const PageStorageKey<String>('main-shell-tab-0'),
        child: HomeScreen(
          onMenuPressed: _openDrawer,
          onTabSelected: _selectTab,
          discoveryDashboardKey: _discoveryDashboardKey,
          discoveryProfileKey: _discoveryProfileKey,
        ),
      ),
      _KeepAliveWrapper(
        key: const PageStorageKey<String>('main-shell-tab-1'),
        child: TransactionsScreen(onMenuPressed: _openDrawer),
      ),
      _KeepAliveWrapper(
        key: const PageStorageKey<String>('main-shell-tab-2'),
        child: CalendarScreen(onMenuPressed: _openDrawer),
      ),
      _KeepAliveWrapper(
        key: const PageStorageKey<String>('main-shell-tab-3'),
        child: AccountsScreen(onMenuPressed: _openDrawer),
      ),
    ];
    _mainBody = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _noteGlassChange();
        return false;
      },
      child: PageView(
        controller: _pageController,
        physics: const PageScrollPhysics(),
        dragStartBehavior: DragStartBehavior.start,
        onPageChanged: (index) {
          if (_selectedIndex.value != index) {
            _selectedIndex.value = index;
          }
          _noteGlassChange();
        },
        children: _screens,
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(exchangeRateServiceProvider).refreshRatesIfStale();
    });
    // The redirect that follows an offline → Google upgrade replaces the page
    // stack (closing the upgrade sheet), so confirm the result here.
    ref.listenManual<OfflineModeState>(offlineModeControllerProvider, (
      previous,
      next,
    ) {
      if (next.stage != OfflineUpgradeStage.completed ||
          next.completionAnnounced) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(offlineModeControllerProvider.notifier).markAnnounced();
        showAppSnackBar(
          context,
          'Backup & sync is on for '
          '${next.accountEmail ?? 'your Google account'}.',
        );
      });
    }, fireImmediately: true);
    _lightBackgroundPeriodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) {
        ref.read(exchangeRateServiceProvider).refreshRatesIfStale();
        ref.read(ledgerProvider.notifier).processSpooledSms();
        ref.read(ledgerProvider.notifier).processSpooledNotifications();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (!identical(router, _discoveryRouter)) {
      _discoveryRouter?.routerDelegate.removeListener(
        _handleDiscoveryNavigation,
      );
      _discoveryRouter = router;
      router?.routerDelegate.addListener(_handleDiscoveryNavigation);
    }
    final provider = router?.routeInformationProvider;
    if (identical(provider, _routeInformationProvider)) return;
    _routeInformationProvider?.removeListener(_handleRouteInformation);
    _routeInformationProvider = provider;
    _lastRouteInformation = provider?.value;
    provider?.addListener(_handleRouteInformation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(provider, _routeInformationProvider)) {
        _lastRouteInformation = provider?.value;
      }
    });
  }

  void _handleRouteInformation() {
    final information = _routeInformationProvider?.value;
    final previous = _lastRouteInformation;
    _lastRouteInformation = information;
    if (information == null || identical(information.state, previous?.state)) {
      return;
    }
    final repeatedRoot =
        previous != null &&
        information.uri == previous.uri &&
        information.uri.path == '/';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _routeInformationProvider?.value;
      if (current?.uri != information.uri) return;
      _lastRouteInformation = current;
      // go_router can retain the same page when a deep link is reopened.
      if (repeatedRoot) {
        _selectTab(widget.initialTab);
      }
    });
  }

  void _handleDiscoveryNavigation() {
    final routes = _discoveryRouter?.routerDelegate.currentConfiguration;
    if (!mounted || routes == null || routes.isEmpty) return;
    final path = routes.last.matchedLocation;
    if (path != '/') {
      final owner = ref.read(authControllerProvider).ownerId;
      if (owner != null) {
        final progress = ref.read(discoveryControllerProvider(owner));
        if (progress.status == DiscoveryStatus.active) {
          _routePausedDiscoveryOwner = owner;
          _runDiscovery(
            ref.read(discoveryControllerProvider(owner).notifier).pause(),
          );
        }
      }
    }
    if (path == '/' && _routePausedDiscoveryOwner != null) {
      final owner = ref.read(authControllerProvider).ownerId;
      if (owner != null &&
          owner == _routePausedDiscoveryOwner &&
          ref.read(discoveryControllerProvider(owner)).status ==
              DiscoveryStatus.paused &&
          !ref.read(discoveryControllerProvider(owner)).guideActive) {
        _runDiscovery(
          ref.read(discoveryControllerProvider(owner).notifier).start(),
        );
      }
      _routePausedDiscoveryOwner = null;
    }
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab ||
        widget.routeTabParameter != oldWidget.routeTabParameter) {
      _selectTab(widget.initialTab);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(exchangeRateServiceProvider).refreshRatesIfStale();
      ref.read(ledgerProvider.notifier).processSpooledSms();
      ref.read(ledgerProvider.notifier).processSpooledNotifications();
      final owner = ref.read(authControllerProvider).ownerId;
      if (owner != null) {
        unawaited(
          ref
              .read(discoveryControllerProvider(owner).notifier)
              .refreshCloudCompletion(),
        );
      }
    }
  }

  @override
  void dispose() {
    _discoveryRouter?.routerDelegate.removeListener(_handleDiscoveryNavigation);
    _discoverySubscription?.close();
    _routeInformationProvider?.removeListener(_handleRouteInformation);
    WidgetsBinding.instance.removeObserver(this);
    _lightBackgroundPeriodicTimer?.cancel();
    _pageController.removeListener(_noteGlassChange);
    _pageController.dispose();
    _selectedIndex.dispose();
    super.dispose();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _observeDiscovery(String? owner) {
    if (_observedDiscoveryOwner == owner) return;
    _observedDiscoveryOwner = owner;
    _discoverySubscription?.close();
    _discoverySubscription = owner == null
        ? null
        : ref.listenManual(discoveryControllerProvider(owner), (
            previous,
            next,
          ) {
            if (next.syncError != null &&
                next.syncError != previous?.syncError) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted &&
                    ref.read(authControllerProvider).ownerId == owner) {
                  showAppSnackBar(context, next.syncError!);
                }
              });
            }
          });
  }

  void _runDiscovery(Future<void> operation) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        debugPrint('Could not save guide progress: $error');
        debugPrintStack(stackTrace: stack);
        if (mounted) {
          showAppSnackBar(
            context,
            'Could not save tour progress. Please try again.',
          );
        }
      }),
    );
  }

  void _selectTab(int index) {
    _noteGlassChange();
    if (_selectedIndex.value != index) {
      _selectedIndex.value = index;
    }
    if (!_pageController.hasClients) return;
    final currentPage = _pageController.page?.round();
    if (currentPage == index) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
    );
  }

  bool _shouldSyncScheduledNotifications(
    LedgerState? previous,
    LedgerState next,
  ) {
    if (previous == null) return true;
    final prevPrefs = previous.preferences;
    final nextPrefs = next.preferences;
    if (prevPrefs.deviceNotificationsEnabled !=
            nextPrefs.deviceNotificationsEnabled ||
        prevPrefs.channelScheduledEnabled !=
            nextPrefs.channelScheduledEnabled ||
        prevPrefs.privacyModeEnabled != nextPrefs.privacyModeEnabled ||
        prevPrefs.locale != nextPrefs.locale) {
      return true;
    }
    if (identical(previous.transactions, next.transactions)) {
      return false;
    }
    final prevScheduled = scheduledTransactions(previous);
    final nextScheduled = scheduledTransactions(next);
    if (prevScheduled.length != nextScheduled.length) return true;
    for (var i = 0; i < prevScheduled.length; i++) {
      if (!identical(prevScheduled[i], nextScheduled[i])) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeControllerProvider);
    final theme = Theme.of(context);

    ref.listen(themeControllerProvider, (prev, next) {
      if (prev?.preference != next.preference ||
          prev?.customAccentColor != next.customAccentColor ||
          prev?.colorIntensity != next.colorIntensity ||
          prev?.useSystemColor != next.useSystemColor) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _noteGlassChange());
      }
    });

    ref.listen<LedgerState>(ledgerProvider, (previous, next) {
      if (_shouldSyncScheduledNotifications(previous, next)) {
        NotificationService.syncScheduledNotifications(next);
      }
    });

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          Navigator.of(context).pop();
          return true;
        }
        return false;
      },
      child: ValueListenableBuilder<int>(
        valueListenable: _selectedIndex,
        child: _mainBody,
        builder: (context, selectedIndex, cachedMainBody) {
          final dueCardCount = ref.watch(
            ledgerProvider.select((state) => creditCardsDueSoonCount(state)),
          );

          final tabs = [
            const IslandTabItem(
              title: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
            ),
            const IslandTabItem(
              title: 'History',
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              pageIndex: 1,
            ),
            const IslandTabItem(
              title: 'Calendar',
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month_rounded,
              pageIndex: 2,
            ),
            IslandTabItem(
              title: 'Accounts',
              icon: Icons.wallet_outlined,
              activeIcon: Icons.wallet_rounded,
              pageIndex: 3,
              badgeCount: dueCardCount > 0 ? dueCardCount : null,
            ),
          ];

          final homeReordering = ref.watch(homeWidgetReorderModeProvider);
          final islandGlassFinish = ref.watch(islandBarGlassFinishProvider);
          final fabGlassFinish = ref.watch(fabGlassFinishProvider);
          final showAction = selectedIndex != 0 || !homeReordering;
          final actionButton = selectedIndex == 3
              ? IslandFloatingActionButton(
                  key: ValueKey(
                    'add-account-action_${themeState.fabOutlineThickness}_${themeState.fabOutlineOpacity}',
                  ),
                  icon: Icons.add_rounded,
                  tooltip: 'Add account',
                  finish: fabGlassFinish,
                  onPressed: () => context.push('/account/new'),
                )
              : IslandFloatingActionButton(
                  key: ValueKey(
                    'add-record-action_${themeState.fabOutlineThickness}_${themeState.fabOutlineOpacity}',
                  ),
                  icon: Icons.add_rounded,
                  tooltip: 'Add record',
                  finish: fabGlassFinish,
                  onPressed: () {
                    final owner = ref.read(authControllerProvider).ownerId;
                    if (owner != null) {
                      final guide = ref.read(
                        discoveryControllerProvider(owner),
                      );
                      if (guide.status == DiscoveryStatus.active &&
                          guide.step == 1) {
                        _runDiscovery(
                          ref
                              .read(discoveryControllerProvider(owner).notifier)
                              .advance(),
                        );
                      }
                    }
                    if (selectedIndex == 0) {
                      final accountId = ref.read(homeSelectedAccountProvider);
                      if (accountId != null && accountId != 'cash_group') {
                        context.push(
                          Uri(
                            path: '/add',
                            queryParameters: {'accountId': accountId},
                          ).toString(),
                        );
                        return;
                      }
                    }
                    context.push('/add');
                  },
                );
          final action = KeyedSubtree(
            key: _discoveryActionKey,
            child: actionButton,
          );

          Widget mobileBody = Stack(
            children: [
              cachedMainBody!,
              Positioned(
                left: 0,
                right: 0,
                bottom: AppSpacing.xxs,
                child: KeyedSubtree(
                  key: _discoveryNavigationKey,
                  child: BottomIslandNavBar(
                    key: ValueKey(
                      'island_nav_${theme.brightness}_${themeState.preference}_${themeState.islandOutlineThickness}_${themeState.islandOutlineOpacity}_${islandGlassFinish.name}_${islandGlassFinish.blurSigmaLogical}',
                    ),
                    items: tabs,
                    selectedIndex: selectedIndex,
                    onSelected: _selectTab,
                    action: showAction ? action : null,
                    compactAction: selectedIndex == 2,
                    pageController: _pageController,
                    finish: islandGlassFinish,
                  ),
                ),
              ),
            ],
          );

          Widget desktopBody = ColoredBox(
            color: Colors.transparent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: _discoveryNavigationKey,
                  child: AppMainDrawer(
                    selectedIndex: selectedIndex,
                    isStatic: true,
                    onTabSelected: _selectTab,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: cachedMainBody),
                      if (showAction)
                        Positioned(
                          right: AppSpacing.xl,
                          bottom: AppSpacing.xl,
                          child: action,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final isDesktop = AppResponsiveLayout.isDesktop(context);
          final owner = ref.watch(
            authControllerProvider.select((state) => state.ownerId),
          );
          final discovery = owner == null
              ? null
              : ref.watch(discoveryControllerProvider(owner));
          final snackBarBottomInset = isDesktop
              ? AppSpacing.md
              : (AppSizes.bottomBarClearance + 64 + AppSpacing.md).clamp(
                  0.0,
                  MediaQuery.sizeOf(context).height * 0.35,
                );
          return SnackBarTheme(
            data: theme.snackBarTheme.copyWith(
              insetPadding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                snackBarBottomInset,
              ),
            ),
            child: Scaffold(
              key: _scaffoldKey,
              drawerEdgeDragWidth: 40,
              drawer: isDesktop
                  ? null
                  : AppMainDrawer(
                      selectedIndex: selectedIndex,
                      onTabSelected: (index) {
                        Navigator.of(context).pop();
                        _selectTab(index);
                      },
                    ),
              body: Stack(
                children: [
                  AppResponsiveLayout(mobile: mobileBody, desktop: desktopBody),
                  if (owner != null &&
                      discovery != null &&
                      !discovery.guideActive &&
                      (discovery.status != DiscoveryStatus.welcome ||
                          discovery.automaticTourEligible ||
                          discovery.isReplay))
                    Positioned.fill(
                      child: DiscoveryOverlay(
                        progress: discovery,
                        dashboardTarget: _discoveryDashboardKey,
                        navigationTarget: _discoveryNavigationKey,
                        actionTarget: _discoveryActionKey,
                        profileTarget: _discoveryProfileKey,
                        selectedTab: selectedIndex,
                        hasAccounts: ref.watch(
                          ledgerProvider.select(
                            (state) => state.accounts.any(
                              (account) => !account.isDeleted,
                            ),
                          ),
                        ),
                        onSelectTab: _selectTab,
                        onExploreWorkflows: () => _runDiscovery(() async {
                          await ref
                              .read(discoveryControllerProvider(owner).notifier)
                              .startWorkflowTour();
                          if (context.mounted &&
                              ref.read(authControllerProvider).ownerId ==
                                  owner) {
                            unawaited(context.push<void>('/recurring'));
                          }
                        }()),
                        onStart: () => _runDiscovery(
                          ref
                              .read(discoveryControllerProvider(owner).notifier)
                              .start(),
                        ),
                        onPause: () => _runDiscovery(
                          ref
                              .read(discoveryControllerProvider(owner).notifier)
                              .pause(),
                        ),
                        onFinish: () {
                          _runDiscovery(
                            ref
                                .read(
                                  discoveryControllerProvider(owner).notifier,
                                )
                                .finish(),
                          );
                        },
                        onPrevious: () => _runDiscovery(
                          ref
                              .read(discoveryControllerProvider(owner).notifier)
                              .previous(),
                        ),
                        onNext: () {
                          _runDiscovery(
                            ref
                                .read(
                                  discoveryControllerProvider(owner).notifier,
                                )
                                .advance(),
                          );
                          if (discovery.step == discovery.endStep) {
                            _selectTab(0);
                          }
                        },
                        onSkipStep: () {
                          _runDiscovery(
                            ref
                                .read(
                                  discoveryControllerProvider(owner).notifier,
                                )
                                .advance(skipped: true),
                          );
                          if (discovery.step == discovery.endStep) {
                            _selectTab(0);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class AppMainDrawer extends ConsumerWidget {
  const AppMainDrawer({
    required this.selectedIndex,
    required this.onTabSelected,
    this.isStatic = false,
    super.key,
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

    final pendingReviewCount = _pendingReviewCount(ledger);
    final unreadNotificationCount = buildNotificationInbox(
      ledger,
    ).where((n) => !n.read).length;
    final combinedInboxCount = pendingReviewCount + unreadNotificationCount;
    final upcomingPlannedCount = _upcomingPlannedCount(ledger);
    final syncBadge = _syncBadge(sync);
    final profileUser = auth.profileUser;
    final profileName = auth.isLocalOnly && auth.localDisplayName != null
        ? auth.localDisplayName!
        : _profileName(profileUser, ledger);
    final profileSubtitle = _profileSubtitle(
      profileUser,
      ledger,
      offline: auth.isLocalOnly,
    );
    final profileInitials =
        profileUser?.initials ?? _walletInitials(profileName);

    Widget content = SafeArea(
      child: Container(
        margin: isStatic
            ? EdgeInsets.zero
            : const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: isStatic
              ? BorderRadius.zero
              : BorderRadius.circular(AppRadii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              scheme.surfaceContainerLow,
              scheme.surface,
            ],
          ),
          border: isStatic
              ? Border(
                  right: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.71),
                  ),
                )
              : Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.71),
                ),
          boxShadow: isStatic
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.11),
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
                      scheme.primaryContainer.withValues(
                        alpha: isStatic ? 0.59 : 0.86,
                      ),
                      scheme.surfaceContainerHigh,
                      scheme.tertiaryContainer.withValues(
                        alpha: isStatic ? 0.47 : 0.71,
                      ),
                    ],
                  ),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.71),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AuthUserAvatar(
                          user: profileUser,
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
                              const SizedBox(height: AppSpacing.xxxs),
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
                    title: 'Quick Access',
                    titleColor: scheme.primary,
                    icon: Icons.bolt_rounded,
                    surfaceTint: scheme.primary,
                    rows: [
                      DrawerRowConfig.tab('Home', Icons.dashboard_outlined, 0),
                      DrawerRowConfig.route(
                        'Review',
                        Icons.smart_toy_outlined,
                        '/review',
                        badge: _countBadge(combinedInboxCount),
                      ),
                      DrawerRowConfig.route(
                        'Planned payments',
                        Icons.event_repeat_outlined,
                        '/recurring',
                        badge: _countBadge(upcomingPlannedCount),
                      ),
                      DrawerRowConfig.route(
                        'Loans',
                        Icons.account_balance_outlined,
                        '/loans',
                      ),
                      DrawerRowConfig.route(
                        'Loan forecast',
                        Icons.show_chart_rounded,
                        '/loans/forecast',
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
                        'Auto Capture',
                        Icons.notifications_active_outlined,
                        '/auto-capture',
                      ),
                      DrawerRowConfig.route(
                        'Categories',
                        Icons.category_outlined,
                        '/categories',
                      ),
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
                        'Import statements',
                        Icons.receipt_long_outlined,
                        '/import-statement',
                      ),
                      DrawerRowConfig.route(
                        'Data backup',
                        Icons.backup_outlined,
                        '/data-backup',
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
                      decoration: AppSurfaces.panel(
                        context,
                        radius: AppRadii.xl,
                      ),
                      child: Column(
                        children: [
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
                          if (auth.isLocalOnly) ...[
                            // Offline mode leads with the Google upgrade;
                            // signing out erases the device-only wallet.
                            DrawerRouteTile(
                              config: DrawerRowConfig.route(
                                'Back up with Google',
                                Icons.cloud_upload_outlined,
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
                              // The dialog opens over the drawer so its
                              // context stays mounted until confirmation.
                              onTapOverride: () =>
                                  confirmOfflineSignOut(context, ref),
                            ),
                          ] else
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
                                await signOutAppSession(ref);
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
      notifier.updatePreferencesWith(
        (livePreferences) => livePreferences.copyWith(
          privacyModeEnabled: !livePreferences.privacyModeEnabled,
        ),
      );
    }

    // MergeSemantics combines the label text and the switch's toggled state
    // into a single semantics node, mirroring AppSwitchListTile. Without it,
    // screen readers expose an unlabeled tappable region and a disconnected
    // "Privacy mode" text node instead of one coherent on/off control.
    return MergeSemantics(
      child: Material(
        color: enabled
            ? scheme.primary.withValues(alpha: 0.11)
            : scheme.surface.withValues(alpha: 0.63),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: AppSwitchListTile(
          secondary: Icon(
            enabled ? Icons.visibility_off_rounded : Icons.visibility_outlined,
            size: 18,
            color: scheme.primary,
          ),
          title: const Text('Privacy mode'),
          value: enabled,
          onChanged: (_) => toggle(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
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

/// Returns how many scheduled transactions are due within the next 3 calendar
/// days (today inclusive — e.g. today=Fri means Fri/Sat/Sun all count).
int _upcomingPlannedCount(LedgerState ledger) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final cutoff = startOfToday.add(const Duration(days: 3));
  return scheduledTransactions(ledger)
      .where(
        (t) =>
            t.status == 'scheduled' &&
            !t.occurredAt.isBefore(startOfToday) &&
            t.occurredAt.isBefore(cutoff),
      )
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

String _profileSubtitle(
  AuthUser? user,
  LedgerState ledger, {
  bool offline = false,
}) {
  final accountCount = ledger.accounts
      .where((account) => !account.isArchived)
      .length;
  final label = offline ? 'Offline wallet' : 'My Wallet';
  return '$label · $accountCount account${accountCount == 1 ? '' : 's'}';
}

String _walletInitials(String source) {
  final parts = source
      .split(RegExp(r'\s+|@'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return '1W';
  final letterMatch = RegExp(r'[a-zA-Z0-9]').firstMatch(parts.first);
  return (letterMatch?.group(0) ?? parts.first[0]).toUpperCase();
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
    return widget.child;
  }
}
