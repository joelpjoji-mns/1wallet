import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/cards/cards_screen.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Regression coverage for the Cards screen's "Add" action: it used to push
/// a generic `/account/new` with no type hint, forcing the user to manually
/// change the type away from the "Bank" default. It should now jump
/// straight into a pre-selected "Credit Card" type.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Cards screen "Add" preselects the Credit Card account type', (
    tester,
  ) async {
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
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
        ),
      ),
    );
    router.go('/cards');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('New account'), findsOneWidget);
    expect(find.text('Credit Card'), findsOneWidget);
  });

  testWidgets(
    'the plain Accounts screen "Add account" still defaults to Bank (no '
    'type hint)',
    (tester) async {
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
            theme: AppTheme.light(),
            darkTheme: AppTheme.amoled(),
          ),
        ),
      );
      router.go('/account/new');
      await tester.pumpAndSettle();

      expect(find.text('New account'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Credit Card'), findsNothing);
    },
  );

  testWidgets('custom card icons remain visible on light and dark surfaces', (
    tester,
  ) async {
    final cases = [
      (AppTheme.amoled(), const Color(0xFF111827), false),
      (AppTheme.light(), const Color(0xFFF8FAFC), false),
      (AppTheme.light(), const Color(0xFF1565C0), true),
    ];
    for (final (theme, color, preservesAccent) in cases) {
      final account = Account(
        id: 'contrast-card',
        name: 'Contrast card',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: const Money(amountMinor: 0, currency: 'USD'),
        color: color,
      );
      final state = sampleLedgerState().copyWith(accounts: [account]);
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state),
      );
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: theme, home: const CardsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final tile = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_CardAccountTile',
      );
      final icon = find.descendant(
        of: tile,
        matching: find.byIcon(accountIcon(account)),
      );
      final iconColor = tester.widget<Icon>(icon).color!;
      final bubble = tester.widget<Container>(
        find.ancestor(of: icon, matching: find.byType(Container)).first,
      );
      final panel = tester.widget<DecoratedBox>(
        find.descendant(of: tile, matching: find.byType(DecoratedBox)).first,
      );
      final background = Color.alphaBlend(
        (bubble.decoration! as BoxDecoration).color!,
        (panel.decoration as BoxDecoration).color!,
      );
      final foreground = Color.alphaBlend(iconColor, background);
      final foregroundLuminance = foreground.computeLuminance();
      final backgroundLuminance = background.computeLuminance();
      final contrast = foregroundLuminance > backgroundLuminance
          ? (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (foregroundLuminance + 0.05);
      expect(contrast, greaterThanOrEqualTo(3));
      if (preservesAccent) expect(iconColor, color);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });
}
