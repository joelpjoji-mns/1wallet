// Design-consistency regression test: per the liquid_glass_widgets 1.7.2
// README, Liquid Glass should be reserved for the navigation/control layer
// (app bars, floating actions, icon buttons) - scrolling content and list
// rows should stay opaque. `_LoanCompactCard` (a repeated row in the loans
// overview list) and `LoanDetailView`'s header summary card previously wrapped
// themselves in `GlassCard`, applying a refractive/blurred treatment to
// scrolling content. Both were converted to plain opaque `Container`s using
// themed surface/border colors.
//
// This test only inspects the subtree of those two specific widgets (not the
// whole page): shared components from lib/src/widgets/app_kit.dart
// (`SectionCard`, `MetricTile`) still wrap themselves in `GlassCard`
// unconditionally with no opaque opt-out, unlike `PremiumRow` (which now
// defaults to `glass: false` for exactly this reason). That's a shared-widget
// inconsistency outside this feature's ownership (app_kit.dart may not be
// edited here) and has been reported separately rather than fixed in this
// file.
//
// A loan is created through the real "New loan" form (rather than relying on
// the fixture's pre-seeded loan account) because in this harness the ledger
// provider settles to its own fresh/empty state once auth resolves to
// "unavailable" in a test environment, independent of the seed passed to
// `authenticatedSampleOverrides`; creating the loan via the UI, as
// `loans_screen_form_bugfix_test.dart` already does, sidesteps that and is
// the harness's established working pattern for this screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/loans/loans_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  GoRouter buildLoansOnlyRouter() {
    return GoRouter(
      initialLocation: '/loans/new',
      routes: [
        GoRoute(
          path: '/loans',
          builder: (context, state) => const LoansScreen(),
        ),
        GoRoute(
          path: '/loans/new',
          builder: (context, state) => const LoansScreen(mode: 'new'),
        ),
        GoRoute(
          path: '/loans/detail/:id',
          builder: (context, state) => LoansScreen(
            mode: 'detail',
            accountId: state.pathParameters['id'],
          ),
        ),
      ],
    );
  }

  Future<(ProviderContainer, GoRouter)> createLoanAndReturnOverview(
    WidgetTester tester,
  ) async {
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
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Loan name'),
      'Glass Consistency Loan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Original Principal'),
      '50000',
    );
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Create loan');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // `_saveLoan` navigates back to the overview on success.
    expect(
      container
          .read(ledgerProvider)
          .accounts
          .where((a) => a.name == 'Glass Consistency Loan')
          .length,
      1,
    );

    return (container, router);
  }

  testWidgets(
    'a loans overview list row (_LoanCompactCard) is not wrapped in GlassCard',
    (tester) async {
      await createLoanAndReturnOverview(tester);

      final cardFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_LoanCompactCard',
      );
      expect(cardFinder, findsWidgets);

      final glassInsideCard = find.descendant(
        of: cardFinder.first,
        matching: find.byType(GlassCard),
      );
      expect(glassInsideCard, findsNothing);
    },
  );

  testWidgets('the loan detail header card (LoanDetailView) is not wrapped in '
      'GlassCard', (tester) async {
    final (container, router) = await createLoanAndReturnOverview(tester);
    final loanId = container
        .read(ledgerProvider)
        .accounts
        .firstWhere((a) => a.name == 'Glass Consistency Loan')
        .id;

    router.go('/loans/detail/$loanId');
    await tester.pumpAndSettle();

    final detailFinder = find.byType(LoanDetailView);
    expect(detailFinder, findsOneWidget);

    final headerFinder = find.byKey(const ValueKey('loanDetailHeaderCard'));
    expect(headerFinder, findsOneWidget);

    final glassInsideHeader = find.descendant(
      of: headerFinder,
      matching: find.byType(GlassCard),
    );
    expect(glassInsideHeader, findsNothing);
    // The header container itself must not be a GlassCard either.
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(GlassCard)),
      findsNothing,
    );
  });
}
