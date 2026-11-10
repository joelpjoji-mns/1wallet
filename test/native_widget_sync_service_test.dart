import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
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

    test('syncWidgets executes cleanly without throwing on ledger data', () async {
      final sampleState = emptyLedgerState(userId: 'test-user');
      await expectLater(
        NativeWidgetSyncService.syncWidgets(sampleState),
        completes,
      );
    });
  });
}
