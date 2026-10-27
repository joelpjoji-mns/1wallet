import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/launch/launch_screen.dart';
import '../features/login/login_screen.dart';
import '../features/main/main_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/routes/route_screens.dart';
import '../features/sync/sync_screen.dart';
import '../features/capture/capture_settings_screen.dart';
import '../features/capture/notification_capture_screen.dart';
import '../features/capture/notification_apps_screen.dart';
import '../startup/startup_state.dart';
import '../auth/auth_controller.dart';
import '../widgets/app_glass_page.dart';
import '../features/settings/account_deletion_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen<StartupState>(startupStateProvider, (_, _) {
    refreshNotifier.notify();
  });
  final initialStartup = ref.read(startupStateProvider);
  final initialLocation =
      (initialStartup.isPending || initialStartup.isRecoverableError)
      ? '/launch'
      : switch (initialStartup.destination) {
          StartupDestination.login => '/login',
          StartupDestination.permissions => '/permissions-setup',
          StartupDestination.onboarding => '/onboarding',
          StartupDestination.home => '/',
          StartupDestination.launch => '/launch',
          StartupDestination.deletion => '/account-deletion',
        };
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final startup = ref.read(startupStateProvider);
      final location = state.matchedLocation;
      final isLaunch = location == '/launch';
      final isLogin = location == '/login' || location == '/signup';
      final isPermissions = location == '/permissions-setup';
      final isOnboarding = location == '/onboarding';

      if (startup.isPending || startup.isRecoverableError) {
        final auth = ref.read(authControllerProvider);
        if (startup.isRecoverableError &&
            location == '/data-backup' &&
            (auth.isAuthenticated || auth.isLocalOnly)) {
          return null;
        }
        return isLaunch ? null : '/launch';
      }

      return switch (startup.destination) {
        StartupDestination.deletion =>
          location == '/account-deletion' ? null : '/account-deletion',
        StartupDestination.login => isLogin ? null : '/login',
        StartupDestination.permissions =>
          isPermissions ? null : '/permissions-setup',
        StartupDestination.onboarding => isOnboarding ? null : '/onboarding',
        StartupDestination.home =>
          isLogin || isLaunch || isPermissions || isOnboarding ? '/' : null,
        StartupDestination.launch => isLaunch ? null : '/launch',
      };
    },
    routes: [
      GoRoute(
        path: '/account-deletion',
        builder: (context, state) => const AccountDeletionScreen(),
      ),
      GoRoute(
        path: '/launch',
        builder: (context, state) => const AppGlassPage(child: LaunchScreen()),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const AppGlassPage(child: LoginScreen()),
      ),
      GoRoute(path: '/signup', redirect: (context, state) => '/login'),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) =>
            const AppGlassPage(child: OnboardingScreen()),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const AppGlassPage(child: MainShell()),
      ),
      GoRoute(
        path: '/add',
        builder: (context, state) {
          final tabStr = state.uri.queryParameters['tab'];
          final initialTab = int.tryParse(tabStr ?? '0') ?? 0;
          return AppGlassPage(
            child: AddRecordScreen(
              transactionId: state.uri.queryParameters['transactionId'],
              initialAccountId: state.uri.queryParameters['accountId'],
              plannedId: state.uri.queryParameters['plannedId'],
              captureCandidateId:
                  state.uri.queryParameters['captureCandidateId'],
              initialTab: initialTab,
            ),
          );
        },
      ),
      GoRoute(
        path: '/transaction/:id',
        builder: (context, state) => AppGlassPage(
          child: TransactionDetailScreen(
            transactionId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/account/new',
        builder: (context, state) => AppGlassPage(
          child: AccountEditorScreen(
            initialType: state.uri.queryParameters['type'],
          ),
        ),
      ),
      GoRoute(
        path: '/account/:id',
        builder: (context, state) => AppGlassPage(
          child: AccountEditorScreen(accountId: state.pathParameters['id']),
        ),
        routes: [
          GoRoute(
            path: 'secure',
            builder: (context, state) => AppGlassPage(
              child: SecureAccountDetailsScreen(
                accountId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/widgets',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: WidgetsManagerScreen()),
        ),
      ),
      GoRoute(path: '/reports', redirect: (context, state) => '/widgets'),
      GoRoute(
        path: '/review',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: ReviewQueueScreen()),
        ),
      ),
      GoRoute(
        path: '/capture/:id',
        builder: (context, state) => AppGlassPage(
          child: CaptureDetailScreen(
            candidateId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(path: '/notifications', redirect: (context, state) => '/review'),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: SettingsScreen()),
        ),
      ),
      GoRoute(
        path: '/recurring',
        builder: (context, state) =>
            const AppGlassPage(child: RecurringScreen()),
      ),
      GoRoute(
        path: '/recurring/new',
        builder: (context, state) =>
            const AppGlassPage(child: RecurringScreen(mode: 'new')),
      ),
      GoRoute(
        path: '/recurring/past',
        builder: (context, state) =>
            const AppGlassPage(child: RecurringScreen(mode: 'past')),
      ),
      GoRoute(
        path: '/recurring/:id/edit',
        builder: (context, state) => AppGlassPage(
          child: RecurringScreen(
            mode: 'edit',
            recordId: state.pathParameters['id'],
          ),
        ),
      ),
      GoRoute(
        path: '/recurring/:id',
        builder: (context, state) => AppGlassPage(
          child: RecurringScreen(recordId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/cards',
        builder: (context, state) => const AppGlassPage(child: CardsScreen()),
      ),
      GoRoute(
        path: '/loans',
        builder: (context, state) => const AppGlassPage(child: LoansScreen()),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) =>
                const AppGlassPage(child: LoansScreen(mode: 'new')),
          ),
          GoRoute(
            path: 'past',
            builder: (context, state) =>
                const AppGlassPage(child: LoansScreen(mode: 'past')),
          ),
          GoRoute(
            path: 'forecast',
            builder: (context, state) => const AppGlassPage(
              child: DrawerConfig(
                hasDrawer: true,
                child: LoansScreen(mode: 'forecast'),
              ),
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => AppGlassPage(
              child: LoansScreen(
                mode: 'detail',
                accountId: state.pathParameters['id'],
              ),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => AppGlassPage(
                  child: LoansScreen(
                    mode: 'edit',
                    accountId: state.pathParameters['id'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/accounts',
        builder: (context, state) =>
            const AppGlassPage(child: AccountsScreen()),
      ),

      GoRoute(
        path: '/categories',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: CategoriesScreen()),
        ),
      ),
      GoRoute(
        path: '/currencies',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: CurrenciesScreen()),
        ),
      ),
      GoRoute(
        path: '/sync',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: SyncScreen()),
        ),
      ),
      GoRoute(path: '/imports', redirect: (context, state) => '/sync'),
      GoRoute(
        path: '/import-statement',
        builder: (context, state) =>
            const AppGlassPage(child: ImportStatementScreen()),
      ),
      GoRoute(
        path: '/imports/:id',
        builder: (context, state) => AppGlassPage(
          child: ImportBatchDetailScreen(
            batchId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/capture-settings',
        builder: (context, state) =>
            const AppGlassPage(child: CaptureSettingsScreen()),
      ),
      GoRoute(
        path: '/import-sms',
        builder: (context, state) =>
            const AppGlassPage(child: SmsCaptureScreen()),
      ),
      GoRoute(
        path: '/notification-capture',
        builder: (context, state) =>
            const AppGlassPage(child: NotificationCaptureScreen()),
      ),
      GoRoute(
        path: '/notification-capture/apps',
        builder: (context, state) =>
            const AppGlassPage(child: NotificationAppsScreen()),
      ),
      GoRoute(
        path: '/data-backup',
        builder: (context, state) =>
            const AppGlassPage(child: DataBackupScreen()),
      ),
      GoRoute(
        path: '/auto-capture',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(
            hasDrawer: true,
            child: SmsCaptureScreen(title: 'Auto capture'),
          ),
        ),
      ),
      GoRoute(
        path: '/auto-capture/debug',
        builder: (context, state) =>
            const AppGlassPage(child: CaptureDiagnosticsScreen()),
      ),
      GoRoute(
        path: '/updates',
        builder: (context, state) => const AppGlassPage(
          child: DrawerConfig(hasDrawer: true, child: UpdatesScreen()),
        ),
      ),
      GoRoute(
        path: '/device-permissions',
        builder: (context, state) =>
            const AppGlassPage(child: DevicePermissionsScreen()),
      ),
      GoRoute(
        path: '/permissions-setup',
        builder: (context, state) =>
            const AppGlassPage(child: PermissionsSetupScreen()),
      ),
    ],
  );
  ref.onDispose(() {
    refreshNotifier.dispose();
    router.dispose();
  });
  return router;
});
