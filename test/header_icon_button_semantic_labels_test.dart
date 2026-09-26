import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/accounts/accounts_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/transaction_row.dart';
import 'package:one_wallet_flutter/src/features/transactions/transactions_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Covers the HeaderIconButton call sites flagged by the theme audit as
/// missing `semanticLabel` (accounts_screen.dart:61,66 and
/// transactions_screen.dart:218,222,229,233,237 pre-fix line numbers).
/// `HeaderIconButton` renders an icon-only `GlassIconButton`; without a
/// semantic label a screen reader announces it with no description at all.
///
/// Both screens are normally hosted inside `MainShell`'s `Scaffold` (which
/// supplies the `Material` ancestor their `ActionChip`-based filter pills
/// need); a bare `Scaffold` wrapper reproduces that same context here
/// without depending on the custom glass tab bar's internals.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AccountsScreen header actions expose semantic labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    final handle = tester.ensureSemantics();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
          home: const Scaffold(body: AccountsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Cards'), findsOneWidget);
    expect(find.bySemanticsLabel('Loans'), findsOneWidget);

    handle.dispose();
  });

  testWidgets(
    'TransactionsScreen header actions expose semantic labels in default '
    'and selection modes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      final handle = tester.ensureSemantics();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(),
      );
      addTearDown(container.dispose);
      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(sampleLedgerState());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.amoled(),
            home: Scaffold(
              body: TransactionsScreen(onMenuPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default (nothing selected) actions.
      expect(find.bySemanticsLabel('Choose display currency'), findsOneWidget);
      // The FAB also uses the "Add record" label (its own tooltip), so the
      // header action is expected to be one of at least two matches here.
      expect(find.bySemanticsLabel('Add record'), findsWidgets);
      expect(find.bySemanticsLabel('Customize widgets'), findsOneWidget);

      // Long-pressing a row enters multi-select mode, swapping the header
      // actions for delete/clear-selection controls.
      await tester.longPress(find.byType(TransactionRow).first);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Delete selected transactions'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Clear selection'), findsOneWidget);

      handle.dispose();
    },
  );
}
