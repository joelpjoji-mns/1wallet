import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/main/main_shell.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Smoke coverage for AddRecordScreen's nav chrome migration from a plain
/// Material `AppBar` to the liquid_glass_widgets package's `GlassAppBar`
/// (content cards/controls below the bar are intentionally left untouched).
/// Also guards the screen's custom back semantics — pop when possible,
/// otherwise fall back to home — which must survive the widget swap since
/// `GlassAppBar.leading` still wraps the same callback, just under new bar
/// chrome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          // NoSplash avoids the ink_sparkle shader (unavailable in the test
          // environment), which otherwise intermittently throws on button
          // taps.
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          darkTheme: AppTheme.amoled().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets(
    'AddRecordScreen uses GlassAppBar (not a plain Material AppBar) and '
    'shows the right title',
    (tester) async {
      final container = await pumpApp(tester);
      final router = container.read(appRouterProvider);
      router.go('/add');
      await tester.pumpAndSettle();

      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Add record'), findsOneWidget);

      router.go('/add?transactionId=tx-salary');
      await tester.pumpAndSettle();
      expect(find.text('Edit record'), findsOneWidget);
    },
  );

  testWidgets(
    'back button pops to the previous route when one exists',
    (tester) async {
      final container = await pumpApp(tester);
      final router = container.read(appRouterProvider);
      router.go('/');
      await tester.pumpAndSettle();
      router.push('/add');
      await tester.pumpAndSettle();

      expect(find.byType(AddRecordScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(AddRecordScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
    },
  );

  testWidgets(
    'back button falls back to home when there is nothing to pop',
    (tester) async {
      final container = await pumpApp(tester);
      final router = container.read(appRouterProvider);
      // /add is the only entry on the stack here, so context.canPop() is
      // false and the screen's back handler must fall back to context.go('/').
      router.go('/add');
      await tester.pumpAndSettle();

      expect(find.byType(AddRecordScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(AddRecordScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
    },
  );
}
