import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/launch/launch_screen.dart';
import '../features/login/login_screen.dart';
import '../features/main/main_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reports/balance_trend_screen.dart';
import '../features/routes/route_screens.dart';
import '../features/sync/sync_screen.dart';
import '../startup/startup_state.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final startup = ref.watch(startupStateProvider);
  return GoRouter(
    initialLocation: '/launch',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isLaunch = location == '/launch';
      final isLogin = location == '/login' || location == '/signup';
      final isPermissions = location == '/permissions-setup';
      final isOnboarding = location == '/onboarding';

      if (startup.isPending || startup.isRecoverableError) {
        return isLaunch ? null : '/launch';
      }

      return switch (startup.destination) {
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
        path: '/launch',
        builder: (context, state) => const LaunchScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', redirect: (context, state) => '/login'),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const MainShell()),
      GoRoute(
        path: '/add',
        builder: (context, state) {
          final tabStr = state.uri.queryParameters['tab'];
          final initialTab = int.tryParse(tabStr ?? '0') ?? 0;
          return AddRecordScreen(
            transactionId: state.uri.queryParameters['transactionId'],
            initialAccountId: state.uri.queryParameters['accountId'],
            plannedId: state.uri.queryParameters['plannedId'],
            initialTab: initialTab,
          );
        },
      ),
      GoRoute(
        path: '/transaction/:id',
        builder: (context, state) => TransactionDetailScreen(
          transactionId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/account/new',
        builder: (context, state) => const AccountEditorScreen(),
      ),
      GoRoute(
        path: '/account/:id',
        builder: (context, state) =>
            AccountEditorScreen(accountId: state.pathParameters['id']),
        routes: [
          GoRoute(
            path: 'secure',
            builder: (context, state) =>
                SecureAccountDetailsScreen(accountId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/widgets',
        builder: (context, state) => const WidgetsManagerScreen(),
      ),
      GoRoute(
        path: '/balance-trend',
        builder: (context, state) => const BalanceTrendScreen(),
      ),
      GoRoute(path: '/reports', redirect: (context, state) => '/widgets'),
      GoRoute(
        path: '/review',
        builder: (context, state) => const ReviewQueueScreen(),
      ),
      GoRoute(
        path: '/capture/:id',
        builder: (context, state) =>
            CaptureDetailScreen(candidateId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/recurring',
        builder: (context, state) => const RecurringScreen(),
      ),
      GoRoute(
        path: '/recurring/new',
        builder: (context, state) => const RecurringScreen(mode: 'new'),
      ),
      GoRoute(
        path: '/recurring/past',
        builder: (context, state) => const RecurringScreen(mode: 'past'),
      ),
      GoRoute(
        path: '/recurring/:id/edit',
        builder: (context, state) =>
            RecurringScreen(mode: 'edit', recordId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/recurring/:id',
        builder: (context, state) =>
            RecurringScreen(recordId: state.pathParameters['id']),
      ),
      GoRoute(path: '/cards', builder: (context, state) => const CardsScreen()),
      GoRoute(path: '/loans', builder: (context, state) => const LoansScreen()),
      GoRoute(
        path: '/loans/new',
        builder: (context, state) => const LoansScreen(mode: 'new'),
      ),
      GoRoute(
        path: '/loans/past',
        builder: (context, state) => const LoansScreen(mode: 'past'),
      ),
      GoRoute(
        path: '/loans/forecast',
        builder: (context, state) => const LoansScreen(mode: 'forecast'),
      ),
      GoRoute(
        path: '/loans/:id/edit',
        builder: (context, state) =>
            LoansScreen(mode: 'edit', accountId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/loans/:id',
        builder: (context, state) =>
            LoansScreen(mode: 'detail', accountId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/budgets/new',
        builder: (context, state) =>
            const BudgetGoalEditorScreen(kind: 'budget'),
      ),
      GoRoute(
        path: '/goals/new',
        builder: (context, state) => const BudgetGoalEditorScreen(kind: 'goal'),
      ),
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/currencies',
        builder: (context, state) => const CurrenciesScreen(),
      ),
      GoRoute(path: '/sync', builder: (context, state) => const SyncScreen()),
      GoRoute(
        path: '/imports',
        builder: (context, state) => const ImportsScreen(),
      ),
      GoRoute(
        path: '/imports/:id',
        builder: (context, state) =>
            ImportBatchDetailScreen(batchId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/import-wallet-csv',
        builder: (context, state) => const ImportWalletCsvScreen(),
      ),
      GoRoute(
        path: '/import-sms',
        builder: (context, state) => const ImportSmsScreen(),
      ),
      GoRoute(
        path: '/data-backup',
        builder: (context, state) => const DataBackupScreen(),
      ),
      GoRoute(
        path: '/auto-capture',
        builder: (context, state) =>
            const ImportSmsScreen(title: 'Auto Capture'),
      ),
      GoRoute(
        path: '/updates',
        builder: (context, state) => const UpdatesScreen(),
      ),
      GoRoute(
        path: '/device-permissions',
        builder: (context, state) => const DevicePermissionsScreen(),
      ),
      GoRoute(
        path: '/permissions-setup',
        builder: (context, state) => const PermissionsSetupScreen(),
      ),
    ],
  );
});
