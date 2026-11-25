import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/services/native_widget_previews.dart';
import 'package:one_wallet_flutter/src/services/native_widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeWidgetSyncService', () {
    test('contains all expected Android AppWidget provider identifiers', () {
      expect(NativeWidgetSyncService.androidWidgetProviders, [
        'WalletBalanceWidgetProvider',
        'QuickActionsWidgetProvider',
        'RecentTransactionsWidgetProvider',
        'SafeSpendWidgetProvider',
        'UpcomingWidgetProvider',
        'CalendarWidgetProvider',
        'AccountsWidgetProvider',
        'BalanceTrendWidgetProvider',
        'TopCategoriesWidgetProvider',
        'CurrencyValuesWidgetProvider',
        'AccountGroupsWidgetProvider',
        'CreditUtilizationWidgetProvider',
        'SavingsRateWidgetProvider',
        'TagCloudWidgetProvider',
        'CashBurnRunwayWidgetProvider',
        'NoSpendStreakWidgetProvider',
        'WeekendWeekdayWidgetProvider',
        'PendingReviewWidgetProvider',
      ]);
    });

    test(
      'syncWidgets executes cleanly without throwing on ledger data',
      () async {
        final sampleState = emptyLedgerState(userId: 'test-user');
        await expectLater(
          NativeWidgetSyncService.syncWidgets(sampleState),
          completes,
        );
      },
    );

    testWidgets('native previews fit the home-widget renderer', (tester) async {
      const previews = [
        (
          Size(400, 220),
          NativeBalanceWidget(
            totalBalance: '\$0.00',
            netWorthLabel: 'Net Worth \$0.00',
            incomeText: '+\$0.00',
            expenseText: '-\$0.00',
            currencyBreakdown: <String>[],
          ),
        ),
        (Size(400, 160), NativeQuickActionsWidget()),
        (
          Size(400, 220),
          NativeAccountsWidget(
            accounts: <NativeAccountEntry>[],
            accountCount: '0',
          ),
        ),
      ];

      for (final (size, preview) in previews) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: size,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NativeWidgetSyncService.sizePreviewForRendering(
                      preview,
                      size,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byWidget(preview)), size);
      }
    });
  });
}
