import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';
import 'package:one_wallet_flutter/src/features/updates/updates_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

class _TrackingUpdateProvider extends AppUpdateProvider {
  bool forceCheckCalled = false;

  @override
  Future<void> checkForUpdates({bool force = false}) async {
    if (force) {
      forceCheckCalled = true;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('All accounts Manage action', () {
    testWidgets('calls onTabSelected(3) when no account is selected', (
      tester,
    ) async {
      int? selectedTab;
      final state = emptyLedgerState().copyWith(
        accounts: const [
          Account(
            id: 'acc-1',
            name: 'Checking',
            type: 'bank',
            currency: 'USD',
            openingBalance: Money(amountMinor: 50000, currency: 'USD'),
            showOnHome: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            home: Scaffold(
              body: AccountGridHomeWidget(
                state: state,
                onTabSelected: (index) => selectedTab = index,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final manageBtn = find.text('Manage');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(selectedTab, equals(3));
    });

    testWidgets('navigates to /account/:id when an account is selected', (
      tester,
    ) async {
      final state = emptyLedgerState().copyWith(
        accounts: const [
          Account(
            id: 'acc-1',
            name: 'Checking',
            type: 'bank',
            currency: 'USD',
            openingBalance: Money(amountMinor: 50000, currency: 'USD'),
            showOnHome: true,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeSelectedAccountProvider.overrideWith((ref) => 'acc-1'),
        ],
      );
      addTearDown(container.dispose);

      String? pushedRoute;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, routerState) => Scaffold(
              body: AccountGridHomeWidget(
                state: state,
                onTabSelected: (_) {},
              ),
            ),
          ),
          GoRoute(
            path: '/account/:id',
            builder: (context, routerState) {
              pushedRoute = '/account/${routerState.pathParameters['id']}';
              return Scaffold(body: Text('Account Detail: $pushedRoute'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final manageBtn = find.text('Manage');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(pushedRoute, equals('/account/acc-1'));
      expect(find.text('Account Detail: /account/acc-1'), findsOneWidget);
    });

    testWidgets('navigates to /loans/:id when a loan account is selected', (
      tester,
    ) async {
      final state = emptyLedgerState().copyWith(
        accounts: const [
          Account(
            id: 'loan-1',
            name: 'Home Loan',
            type: 'loan',
            currency: 'USD',
            openingBalance: Money(amountMinor: 1000000, currency: 'USD'),
            showOnHome: true,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeSelectedAccountProvider.overrideWith((ref) => 'loan-1'),
        ],
      );
      addTearDown(container.dispose);

      String? pushedRoute;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, routerState) => Scaffold(
              body: AccountGridHomeWidget(
                state: state,
                onTabSelected: (_) {},
              ),
            ),
          ),
          GoRoute(
            path: '/loans/:id',
            builder: (context, routerState) {
              pushedRoute = '/loans/${routerState.pathParameters['id']}';
              return Scaffold(body: Text('Loan Detail: $pushedRoute'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final manageBtn = find.text('Manage');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(pushedRoute, equals('/loans/loan-1'));
      expect(find.text('Loan Detail: /loans/loan-1'), findsOneWidget);
    });
  });

  group('UpdatesScreen auto-check on mount', () {
    testWidgets('triggers checkForUpdates(force: true) upon mounting', (
      tester,
    ) async {
      final updateProvider = _TrackingUpdateProvider();
      final container = ProviderContainer(
        overrides: [
          appUpdateProvider.overrideWith((ref) => updateProvider),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const UpdatesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(updateProvider.forceCheckCalled, isTrue);
    });
  });
}
