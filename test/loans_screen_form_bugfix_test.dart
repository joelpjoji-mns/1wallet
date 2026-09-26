// Regression tests for two loan-form bugs fixed in loans_screen.dart:
//   1. The "Tenure count" field had no validation, so a non-positive value
//      (e.g. 0, or a pasted negative number) was silently saved and produced
//      nonsensical payoff projections. `_saveLoan` now rejects it with a
//      clear inline SnackBar and never calls the notifier.
//   2. The "Create loan" button had no re-entrancy guard, so a fast double
//      tap while the async save was in flight could create two loan
//      accounts. `_saveLoan` now disables the button / ignores re-entrant
//      calls via an `_isSaving` flag.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/loans/loans_screen.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // A router scoped to just the loans feature (rather than the full app
  // router) so this test only compiles/exercises loans_screen.dart and its
  // direct dependencies.
  GoRouter buildLoansOnlyRouter() {
    return GoRouter(
      initialLocation: '/loans',
      routes: [
        GoRoute(
          path: '/loans',
          builder: (context, state) => const LoansScreen(),
        ),
        GoRoute(
          path: '/loans/new',
          builder: (context, state) => const LoansScreen(mode: 'new'),
        ),
      ],
    );
  }

  Future<ProviderContainer> pumpLoanForm(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    final router = buildLoansOnlyRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          // NoSplash avoids the ink_sparkle shader (unavailable in the test
          // environment) so button taps don't trigger flaky asset errors.
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.go('/loans/new');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('rejects a non-positive tenure instead of silently saving it', (
    tester,
  ) async {
    final container = await pumpLoanForm(tester);
    final loansBefore = container.read(ledgerProvider).accounts.length;

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Loan name'),
      'Bike Loan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Original Principal'),
      '50000',
    );
    // 0 is a valid *digit* (so it passes the digits-only input formatter)
    // but is not a valid tenure length.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tenure count'),
      '0',
    );
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Create loan');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Tenure must be a positive number of payments.'),
      findsOneWidget,
    );
    expect(
      container.read(ledgerProvider).accounts.length,
      loansBefore,
      reason: 'An invalid tenure must not reach the ledger notifier.',
    );
  });

  testWidgets('the negative sign cannot even be typed into the tenure field', (
    tester,
  ) async {
    await pumpLoanForm(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tenure count'),
      '-12',
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Tenure count'),
    );
    expect(field.controller?.text, '12');
  });

  testWidgets('double-tapping Create loan only creates a single loan account', (
    tester,
  ) async {
    final container = await pumpLoanForm(tester);
    final loansBefore = container
        .read(ledgerProvider)
        .accounts
        .where((a) => a.type == 'loan')
        .length;

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Loan name'),
      'Double Tap Loan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Original Principal'),
      '75000',
    );
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Create loan');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    // Invoke onPressed twice back-to-back with no await in between, so
    // both calls run before the (fast, in-memory) ledger notifier gets a
    // chance to resolve the first save. This is what a real double-tap
    // race looks like: `_saveLoan` must reject the re-entrant call via
    // its `_isSaving` guard rather than relying on timing. (Two
    // sequential `await tester.tap(...)` calls don't reproduce the race:
    // the mocked ledger resolves fast enough that the first save fully
    // completes before the second tap is even dispatched.)
    final onPressed = tester.widget<FilledButton>(saveButton).onPressed!;
    onPressed();
    onPressed();
    await tester.pumpAndSettle();

    final loansAfter = container
        .read(ledgerProvider)
        .accounts
        .where((a) => a.type == 'loan' && a.name == 'Double Tap Loan')
        .length;
    expect(loansAfter, 1);
    expect(
      container
          .read(ledgerProvider)
          .accounts
          .where((a) => a.type == 'loan')
          .length,
      loansBefore + 1,
    );
  });
}
