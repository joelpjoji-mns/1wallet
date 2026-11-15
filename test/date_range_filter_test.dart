import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/features/transactions/transactions_components.dart';
import 'package:one_wallet_flutter/src/features/transactions/transactions_screen.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  group('Date Range Filter & Custom Range', () {
    test('Standard options list matches required specification', () {
      expect(standardHomeDateFilterOptions, [
        'This week',
        'This month',
        '30 days',
        '6 months',
        'This year',
        'All time',
        'Custom range',
      ]);
    });

    test('Custom date range key format and parse', () {
      final range = DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 20),
      );
      final key = formatCustomDateRangeKey(range);
      expect(key, 'custom:2026-06-01..2026-06-20');

      final parsed = parseCustomDateRange(key);
      expect(parsed, isNotNull);
      expect(parsed!.start, DateTime(2026, 6, 1));
      expect(parsed.end, DateTime(2026, 6, 20));

      final label = formatCustomDateRangeLabel(key);
      expect(label, contains('Jun 1'));
      expect(label, contains('Jun 20, 2026'));
    });

    testWidgets('FilterPill displays standardized options without today or last month',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FilterPill(
              icon: Icons.date_range_outlined,
              label: 'All time',
              active: false,
              value: 'all',
              options: [
                GlassDropdownOption('this_week', 'This week'),
                GlassDropdownOption('this_month', 'This month'),
                GlassDropdownOption('30_days', '30 days'),
                GlassDropdownOption('6_months', '6 months'),
                GlassDropdownOption('this_year', 'This year'),
                GlassDropdownOption('all', 'All time'),
                GlassDropdownOption('custom', 'Custom range'),
              ],
            ),
          ),
        ),
      );

      // Verify pill renders
      expect(find.text('All time'), findsOneWidget);
    });

    testWidgets('TransactionsScreen filters correctly with custom date range',
        (tester) async {
      final state = LedgerState(
        version: 1,
        userId: 'user-1',
        preferences: const LedgerPreferences(displayCurrency: 'USD'),
        accounts: const [
          Account(
            id: 'acc1',
            name: 'Cash',
            type: 'cash',
            currency: 'USD',
            openingBalance: Money(amountMinor: 0, currency: 'USD'),
          ),
        ],
        categories: const [],
        transactions: [
          TransactionRecord(
            id: 'tx-may-1',
            accountId: 'acc1',
            type: 'expense',
            status: 'cleared',
            source: 'manual',
            amount: const Money(amountMinor: 1000, currency: 'USD'),
            baseAmount: const Money(amountMinor: 1000, currency: 'USD'),
            occurredAt: DateTime(2026, 5, 5),
          ),
          TransactionRecord(
            id: 'tx-june-1',
            accountId: 'acc1',
            type: 'expense',
            status: 'cleared',
            source: 'manual',
            amount: const Money(amountMinor: 2500, currency: 'USD'),
            baseAmount: const Money(amountMinor: 2500, currency: 'USD'),
            occurredAt: DateTime(2026, 6, 10),
          ),
        ],
        captureCandidates: const [],
        exchangeRates: const [],
      );

      final container = ProviderContainer(
        overrides: [
          ledgerProvider.overrideWith((ref) => _FakeLedgerNotifier(state)),
          transactionsDateFilterProvider.overrideWith(
            (ref) => 'custom:2026-06-01..2026-06-30',
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: TransactionsScreen(
                onMenuPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // June transaction / header should be present
      expect(find.textContaining('Jun'), findsWidgets);
      // May transaction / header should not be present
      expect(find.textContaining('May'), findsNothing);
    });
  });
}

class _FakeLedgerNotifier extends StateNotifier<LedgerState>
    implements LedgerController {
  _FakeLedgerNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
