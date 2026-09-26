import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/recurring/recurring_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/transaction_row.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

/// Covers the package-fidelity fix: `TransactionRow` and the recurring
/// screen's compact row card are rendered in bulk inside scrolling lists
/// (Transactions, Recurring, Home recent activity), so per the
/// liquid_glass_widgets guidance they must stay lightweight opaque
/// surfaces rather than per-item refractive `GlassCard`s. Glass stays
/// reserved for the surrounding chrome (e.g. the recurring summary header).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'TransactionRow renders an opaque surface with no per-row GlassCard',
    (tester) async {
      var tapped = false;
      final state = emptyLedgerState().copyWith(
        accounts: [
          Account(
            id: 'acc-cash',
            name: 'Cash Wallet',
            type: 'cash',
            currency: 'USD',
            openingBalance: const Money(amountMinor: 0, currency: 'USD'),
          ),
        ],
      );
      final transaction = TransactionRecord(
        id: 'tx-1',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-cash',
        amount: const Money(amountMinor: 1250, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1250, currency: 'USD'),
        occurredAt: DateTime(2026, 1, 5),
        notes: 'Coffee',
      );

      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Scaffold(
              body: TransactionRow(
                state: state,
                transaction: transaction,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(TransactionRow),
          matching: find.byType(GlassCard),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(TransactionRow),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );

      // Still a real, distinctly-colored opaque surface (not an invisible
      // transparent container masquerading as "fixed").
      final rowContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(TransactionRow),
          matching: find.byType(Container).first,
        ),
      );
      final decoration = rowContainer.decoration! as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.color, isNot(Colors.transparent));

      // Content and interactivity are unaffected by the surface change.
      expect(find.text('Coffee'), findsOneWidget);
      await tester.tap(find.byType(TransactionRow));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'Recurring planned-list rows are opaque; only the summary header stays '
    'glass',
    (tester) async {
      final now = DateTime.now();
      final state = emptyLedgerState().copyWith(
        accounts: [
          Account(
            id: 'acc-bank',
            name: 'HDFC Main',
            type: 'bank',
            currency: 'USD',
            openingBalance: const Money(amountMinor: 500000, currency: 'USD'),
          ),
        ],
        transactions: [
          TransactionRecord(
            id: 'plan-rent',
            type: 'expense',
            status: 'scheduled',
            source: 'recurring',
            accountId: 'acc-bank',
            amount: const Money(amountMinor: 32000, currency: 'USD'),
            baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
            occurredAt: now.add(const Duration(days: 4)),
            recurrenceFrequency: 'monthly',
            name: 'Rent',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Scaffold(body: RecurringScreen(mode: 'overview')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only the single "Planned summary" header card uses GlassCard; the
      // scrollable list of plan rows below it must not add one per row.
      expect(find.byType(GlassCard), findsOneWidget);

      final rowFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_RecurringCompactCard',
      );
      expect(rowFinder, findsOneWidget);
      expect(
        find.descendant(of: rowFinder, matching: find.byType(GlassCard)),
        findsNothing,
      );
    },
  );
}
