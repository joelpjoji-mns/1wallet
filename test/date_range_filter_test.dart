import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/features/transactions/transactions_components.dart';
import 'package:one_wallet_flutter/src/features/transactions/transactions_screen.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  testWidgets('history filters have three equal columns and working actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var previous = 0;
    var next = 0;
    var account = 0;
    var category = 0;
    String? selectedType;
    final semantics = tester.ensureSemantics();
    try {
      for (final (width, scale) in [
        (320.0, 1.0),
        (360.0, 1.0),
        (430.0, 1.0),
        (320.0, 2.0),
      ]) {
        tester.view.physicalSize = Size(width, 780);
        final hasTags = width != 430;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ledgerProvider.overrideWith(
                (ref) => _FakeLedgerNotifier(sampleLedgerState()),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TransactionCommandStrip(
                    query: '',
                    typeLabel: 'All types',
                    typeValue: 'all',
                    dateLabel: 'This month',
                    dateValue: 'this_month',
                    accountLabel: 'All accounts',
                    categoryLabel: 'All categories',
                    statusLabel: 'All statuses',
                    statusValue: 'all',
                    tagOptions: [
                      const GlassDropdownOption('all', 'All tags'),
                      if (hasTags) const GlassDropdownOption('food', 'Food'),
                    ],
                    onTagSelected: (_) {},
                    typeActive: false,
                    dateActive: false,
                    accountActive: false,
                    categoryActive: false,
                    statusActive: false,
                    hasActiveFilters: false,
                    onQueryChanged: (_) {},
                    onClear: () {},
                    onTypeSelected: (value) => selectedType = value,
                    onDateSelected: (_) {},
                    onPreviousDate: () => previous++,
                    onNextDate: () => next++,
                    onAccountTap: () => account++,
                    onCategoryTap: () => category++,
                    onStatusSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pills = find.byType(FilterPill);
        expect(pills, findsNWidgets(6));
        final bounds = List.generate(6, (i) => tester.getRect(pills.at(i)));
        for (var i = 0; i < 6; i++) {
          expect(bounds[i].width, closeTo(bounds[0].width, 0.01));
          expect(bounds[i].height, greaterThanOrEqualTo(48));
          expect(bounds[i].top, closeTo(bounds[i < 3 ? 0 : 3].top, 0.01));
          expect(bounds[i].left, closeTo(bounds[i % 3].left, 0.01));
          expect(bounds[i].right, lessThanOrEqualTo(width - 16));
        }
        expect(bounds[3].top, greaterThan(bounds[0].bottom));
        expect(find.bySemanticsLabel('All types'), findsOneWidget);
        if (!hasTags) {
          expect(
            tester.getSemantics(find.bySemanticsLabel('No tags yet')),
            matchesSemantics(
              label: 'No tags yet',
              isButton: true,
              hasEnabledState: true,
              isEnabled: false,
            ),
          );
        }
        if (scale == 1) {
          for (final label in [
            'Type',
            'Month',
            'Account',
            'Category',
            'Tags',
            'Status',
          ]) {
            expect(
              tester
                  .renderObject<RenderParagraph>(
                    find.descendant(
                      of: find.text(label),
                      matching: find.byType(RichText),
                    ),
                  )
                  .didExceedMaxLines,
              isFalse,
              reason: label,
            );
          }
        }
        // Period stepping lives on the date pill's swipe, not header arrows.
        expect(find.byTooltip('Previous period'), findsNothing);
        expect(find.byTooltip('Next period'), findsNothing);
        await tester.tap(pills.at(2));
        await tester.tap(pills.at(3));
        await tester.tap(pills.at(0));
        await tester.pumpAndSettle();
        expect(find.text('All records'), findsOneWidget);
        expect(find.text('Expense'), findsOneWidget);
        await tester.tap(find.text('Expense'));
        await tester.pumpAndSettle();
        expect(selectedType, 'expense');
        expect(tester.takeException(), isNull);
      }
      expect(previous, 0);
      expect(next, 0);
      expect(account, 4);
      expect(category, 4);
    } finally {
      semantics.dispose();
    }
  });

  group('Date Range Filter & Custom Range', () {
    test('Standard options list matches required specification', () {
      expect(standardHomeDateFilterOptions, [
        'Today',
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

    testWidgets(
      'FilterPill displays standardized options without today or last month',
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
      },
    );

    testWidgets('TransactionsScreen filters correctly with custom date range', (
      tester,
    ) async {
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
            home: Scaffold(body: TransactionsScreen(onMenuPressed: () {})),
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
