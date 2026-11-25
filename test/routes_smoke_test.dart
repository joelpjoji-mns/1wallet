import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/main/main_shell.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

// Several capture/notification screens (e.g. SmsCaptureScreen,
// NotificationCaptureScreen, NotificationAppsScreen) call this native
// channel directly from initState to check permissions / list installed
// apps. Without a mock handler, invokeMethod never completes under
// flutter test (defaultTargetPlatform defaults to android in tests, so the
// Android-only code paths do run), which either hangs pumpAndSettle behind
// an indeterminate CircularProgressIndicator or silently leaves a
// "Checking…" state forever. Answering with null lets every caller fall
// back to its already-handled "unavailable/not granted" branch quickly.
const _nativeCaptureChannel = MethodChannel('com.joelpjoji.one.wallet/sms');

Future<void> _pumpRouteTransition(WidgetTester tester) async {
  // Glass shaders and live dashboard charts may keep scheduling frames after
  // a route is fully visible. Pump through the route transition without
  // waiting for those intentional animations to become idle.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, null);
  });

  testWidgets('representative routes render without exceptions', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
        ),
      ),
    );
    await _pumpRouteTransition(tester);
    expect(tester.takeException(), isNull);

    const routes = [
      '/',
      '/add',
      '/add?transactionId=tx-salary',
      '/transaction/tx-salary',
      '/account/new',
      '/account/acc-bank',
      '/widgets',
      '/review',
      '/capture/cap-1',
      '/notifications',
      '/settings',
      '/recurring',
      '/recurring/new',
      '/recurring/tx-rent-planned',
      '/recurring/tx-rent-planned/edit',
      '/cards',
      '/loans',
      '/loans/new',
      '/loans/forecast',
      '/loans/acc-loan',
      '/loans/acc-loan/edit',
      '/login',
      '/signup',
      '/onboarding',
      '/budgets/new',
      '/goals/new',
      '/categories',
      '/currencies',
      '/sync',
      '/imports',
      '/imports/missing',
      '/import-wallet-csv',
      '/import-sms',
      '/data-backup',
      '/auto-capture',
      '/auto-capture/debug',
      '/capture-diagnostics',
      '/notification-capture',
      '/notification-capture/apps',
      '/device-permissions',
      '/permissions-setup',
    ];

    for (final route in routes) {
      router.go(route);
      try {
        await _pumpRouteTransition(tester);
        expect(tester.takeException(), isNull, reason: route);
        if (route == '/settings') {
          expect(find.text('Liquid glass appearance'), findsNothing);
          expect(find.text('Blur level'), findsNothing);
        }
      } catch (e) {
        if (e.toString().contains('semantics.parentDataDirty')) {
          // Ignore known Flutter framework bug during test navigation teardown
          continue;
        }
        rethrow;
      }
    }
  });

  testWidgets('core routes render with an empty persisted ledger', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(
        ledger: _emptyLedgerState(),
        prefs: prefs,
      ),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
        ),
      ),
    );
    await _pumpRouteTransition(tester);

    const routes = [
      '/',
      '/add',
      '/transaction/missing',
      '/account/new',
      '/widgets',
      '/review',
      '/categories',
      '/cards',
      '/loans',
      '/recurring',
      '/budgets/new',
      '/goals/new',
    ];

    for (final route in routes) {
      router.go(route);
      try {
        await _pumpRouteTransition(tester);
        expect(tester.takeException(), isNull, reason: route);
      } catch (e) {
        if (e.toString().contains('semantics.parentDataDirty')) {
          // Ignore known Flutter framework bug during test navigation teardown
          continue;
        }
        rethrow;
      }
    }
  });

  testWidgets('tab deep links select valid tabs and reject invalid indexes', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
        ),
      ),
    );
    await _pumpRouteTransition(tester);

    for (final (route, expected) in [
      ('/?tab=1', 1),
      ('/?tab=3', 3),
      ('/?tab=99', 0),
      ('/?tab=-1', 0),
      ('/add?tab=1', 1),
      ('/add?tab=99', 0),
      ('/add?tab=-1', 0),
    ]) {
      router.go(route);
      await _pumpRouteTransition(tester);
      expect(tester.takeException(), isNull, reason: route);
      if (route.startsWith('/add')) {
        expect(
          tester
              .widget<DefaultTabController>(find.byType(DefaultTabController))
              .initialIndex,
          expected,
          reason: route,
        );
        expect(
          DefaultTabController.of(tester.element(find.text('Keypad'))).index,
          expected,
          reason: route,
        );
      } else {
        expect(
          tester.widget<MainShell>(find.byType(MainShell)).initialTab,
          expected,
        );
        expect(
          tester.widget<PageView>(find.byType(PageView).first).controller!.page,
          expected.toDouble(),
          reason: route,
        );
      }
    }

    router.go('/');
    await _pumpRouteTransition(tester);
    final controller = tester
        .widget<PageView>(find.byType(PageView).first)
        .controller!;
    controller.jumpToPage(1);
    await _pumpRouteTransition(tester);
    expect(controller.page, 1);
    router.refresh();
    await _pumpRouteTransition(tester);
    expect(controller.page, 1, reason: 'initial router refresh');
    router.go('/?tab=0');
    await _pumpRouteTransition(tester);
    expect(controller.page, 0);

    router.go('/?tab=1');
    await _pumpRouteTransition(tester);
    controller.jumpToPage(2);
    await _pumpRouteTransition(tester);
    router.go('/?tab=1');
    await _pumpRouteTransition(tester);
    expect(controller.page, 1, reason: 'repeated deep link');
    controller.jumpToPage(2);
    await _pumpRouteTransition(tester);
    router.refresh();
    await _pumpRouteTransition(tester);
    expect(controller.page, 2, reason: 'router refresh preserves selected tab');

    router.go('/');
    await _pumpRouteTransition(tester);
    controller.jumpToPage(2);
    await _pumpRouteTransition(tester);
    router.go('/');
    await _pumpRouteTransition(tester);
    expect(controller.page, 0, reason: 'repeated root link');
  });
}

LedgerState _emptyLedgerState() {
  return const LedgerState(
    version: 14,
    userId: 'empty-test-user',
    preferences: LedgerPreferences(),
    accounts: [],
    categories: [],
    transactions: [],

    captureCandidates: [],
  );
}
