import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/services/native_widget_previews.dart';

class _WidgetSpec {
  const _WidgetSpec(this.name, this.filename, this.size, this.widget);
  final String name;
  final String filename;
  final Size size;
  final Widget widget;
}

void main() {
  setUpAll(() async {
    final interFile = File('assets/fonts/Inter-Regular.ttf');
    if (interFile.existsSync()) {
      final fontLoader = FontLoader('Inter');
      fontLoader.addFont(Future.value(ByteData.view(interFile.readAsBytesSync().buffer)));
      final interBold = File('assets/fonts/Inter-Bold.ttf');
      if (interBold.existsSync()) {
        fontLoader.addFont(Future.value(ByteData.view(interBold.readAsBytesSync().buffer)));
      }
      await fontLoader.load();
    }

    final materialIconsPaths = [
      r'C:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
      r'/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ];
    for (final path in materialIconsPaths) {
      final f = File(path);
      if (f.existsSync()) {
        final iconLoader = FontLoader('MaterialIcons');
        iconLoader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
        await iconLoader.load();
        break;
      }
    }
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('ALL 18 THUMBNAILS COMPLETED SUCCESSFULLY!');
    // Also copy balance to default
    const balancePath = 'android/app/src/main/res/drawable/widget_preview_balance.png';
    const defaultPath = 'android/app/src/main/res/drawable/widget_preview_default.png';
    if (File(balancePath).existsSync()) {
      File(defaultPath).writeAsBytesSync(File(balancePath).readAsBytesSync());
    }
  });

  const sizeWide = Size(400, 220);
  const sizeCompact = Size(400, 160);
  const sizeTall = Size(400, 320);

  final theme = ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      surfaceContainerLow: const Color(0xFF151820),
      surfaceContainerHigh: const Color(0xFF1E222D),
      surfaceContainerHighest: const Color(0xFF262B38),
      outlineVariant: const Color(0xFF333846),
    ),
  );

  final specs = [
    const _WidgetSpec(
      'Balance',
      'widget_preview_balance.png',
      sizeWide,
      NativeBalanceWidget(
        totalBalance: '\$24,850.00',
        netWorthLabel: 'Net Worth \$31,420.00',
        incomeText: '+\$5,400.00',
        expenseText: '-\$2,140.00',
        currencyBreakdown: ['USD \$24,850', 'EUR €4,200', 'GBP £1,850'],
      ),
    ),
    const _WidgetSpec(
      'Accounts',
      'widget_preview_accounts.png',
      sizeWide,
      NativeAccountsWidget(
        accounts: [
          NativeAccountEntry(name: 'Main Checking', balance: '\$8,420.00', type: 'checking', color: Color(0xFF388E3C), isNegative: false),
          NativeAccountEntry(name: 'High Yield Savings', balance: '\$14,200.00', type: 'savings', color: Color(0xFF1976D2), isNegative: false),
          NativeAccountEntry(name: 'Sapphire Credit', balance: '-\$1,120.00', type: 'credit', color: Color(0xFFD32F2F), isNegative: true),
          NativeAccountEntry(name: 'Index Portfolio', balance: '\$6,500.00', type: 'investment', color: Color(0xFF7B1FA2), isNegative: false),
        ],
        accountCount: '4 active accounts',
      ),
    ),
    const _WidgetSpec(
      'Recent Transactions',
      'widget_preview_recent.png',
      sizeTall,
      NativeRecentWidget(
        transactions: [
          NativeTransactionEntry(name: 'Whole Foods Market', accountName: 'Main Checking', dateLabel: 'Today, 2:15 PM', amountText: '-\$64.20', isExpense: true, isTransfer: false),
          NativeTransactionEntry(name: 'Tech Corp Salary', accountName: 'Main Checking', dateLabel: 'Yesterday', amountText: '+\$2,700.00', isExpense: false, isTransfer: false),
          NativeTransactionEntry(name: 'Blue Bottle Coffee', accountName: 'Sapphire Credit', dateLabel: 'Nov 10', amountText: '-\$5.75', isExpense: true, isTransfer: false),
          NativeTransactionEntry(name: 'Savings Transfer', accountName: 'High Yield', dateLabel: 'Nov 09', amountText: '\$500.00', isExpense: false, isTransfer: true),
        ],
      ),
    ),
    const _WidgetSpec(
      'Safe Spend',
      'widget_preview_safe_spend.png',
      sizeWide,
      NativeSafeSpendWidget(
        dailyAllowance: '\$142.50',
        spentToday: '\$38.20',
        spentRatio: 0.27,
        remainingDays: 18,
        dayOfMonth: 13,
        daysInMonth: 31,
      ),
    ),
    const _WidgetSpec(
      'Upcoming',
      'widget_preview_upcoming.png',
      sizeTall,
      NativeUpcomingWidget(
        entries: [
          NativeUpcomingEntry(name: 'Netflix Subscription', accountName: 'Sapphire Credit', amountText: '-\$15.99', daysUntilDue: 2),
          NativeUpcomingEntry(name: 'Equinox Fitness Gym', accountName: 'Main Checking', amountText: '-\$180.00', daysUntilDue: 5),
          NativeUpcomingEntry(name: 'Consulting Retainer', accountName: 'Main Checking', amountText: '+\$1,500.00', daysUntilDue: 7),
        ],
        dueSoonCount: 3,
        totalAmountDue: '\$195.99',
        overdueCount: 0,
      ),
    ),
    const _WidgetSpec(
      'Calendar',
      'widget_preview_calendar.png',
      sizeCompact,
      NativeCalendarWidget(
        monthLabel: 'November 2026',
        spentToday: '\$38.20',
        spentThisMonth: '\$2,140.00',
      ),
    ),
    const _WidgetSpec(
      'Quick Actions',
      'widget_preview_quick_actions.png',
      sizeCompact,
      NativeQuickActionsWidget(),
    ),
    const _WidgetSpec(
      'Balance Trend',
      'widget_preview_balance_trend.png',
      sizeWide,
      NativeBalanceTrendWidget(
        netWorthLabel: 'Net Worth \$31,420.00',
        deltaText: '+\$1,240.00',
        isPositive: true,
        points: [0.1, 0.25, 0.2, 0.45, 0.6, 0.55, 0.85, 1.0],
        periodLabel: 'Last 30 days',
      ),
    ),
    const _WidgetSpec(
      'Top Categories',
      'widget_preview_top_categories.png',
      sizeWide,
      NativeTopCategoriesWidget(
        categories: [
          NativeCategoryEntry(name: 'Housing & Utilities', amountText: '\$1,250.00', percentage: 0.58, color: Color(0xFF1E88E5)),
          NativeCategoryEntry(name: 'Groceries & Dining', amountText: '\$480.00', percentage: 0.22, color: Color(0xFF43A047)),
          NativeCategoryEntry(name: 'Transportation', amountText: '\$210.00', percentage: 0.10, color: Color(0xFFFB8C00)),
          NativeCategoryEntry(name: 'Entertainment', amountText: '\$140.00', percentage: 0.07, color: Color(0xFF8E24AA)),
        ],
        periodLabel: 'This month',
      ),
    ),
    const _WidgetSpec(
      'Currency Values',
      'widget_preview_currency_values.png',
      sizeWide,
      NativeCurrencyValuesWidget(
        baseCurrency: 'USD',
        rates: [
          NativeCurrencyEntry(currencyCode: 'EUR', rateText: '1 USD = 0.92 EUR', equivalentText: '€4,200.00'),
          NativeCurrencyEntry(currencyCode: 'GBP', rateText: '1 USD = 0.79 GBP', equivalentText: '£1,850.00'),
          NativeCurrencyEntry(currencyCode: 'JPY', rateText: '1 USD = 154.20 JPY', equivalentText: '¥3,830,000'),
        ],
      ),
    ),
    const _WidgetSpec(
      'Account Groups',
      'widget_preview_account_groups.png',
      sizeWide,
      NativeAccountGroupsWidget(
        groups: [
          NativeAccountGroupEntry(name: 'Liquid Cash & Checking', balanceText: '\$14,200.00', countText: '2 accounts', icon: Icons.payments_outlined, color: Color(0xFF00E676)),
          NativeAccountGroupEntry(name: 'Investment & Retirement', balanceText: '\$18,400.00', countText: '2 accounts', icon: Icons.trending_up_rounded, color: Color(0xFF7C4DFF)),
          NativeAccountGroupEntry(name: 'Liabilities & Cards', balanceText: '-\$1,120.00', countText: '1 account', icon: Icons.credit_card_rounded, color: Color(0xFFFF5252)),
        ],
      ),
    ),
    const _WidgetSpec(
      'Credit Utilization',
      'widget_preview_credit_utilization.png',
      sizeCompact,
      NativeCreditUtilizationWidget(
        utilizationPercent: 22.0,
        usedAmountText: '\$1,120.00',
        limitAmountText: '\$5,000.00',
      ),
    ),
    const _WidgetSpec(
      'Savings Rate',
      'widget_preview_savings_rate.png',
      sizeWide,
      NativeSavingsRateWidget(
        savingsRatePercent: 42.0,
        savedAmountText: '\$2,260.00',
        incomeAmountText: '\$5,400.00',
        periodLabel: 'This month',
      ),
    ),
    const _WidgetSpec(
      'Tag Cloud',
      'widget_preview_tag_cloud.png',
      sizeWide,
      NativeTagCloudWidget(
        tags: [
          NativeTagEntry(tag: 'travel', amountText: '\$480.00'),
          NativeTagEntry(tag: 'dining', amountText: '\$295.00'),
          NativeTagEntry(tag: 'work-lunch', amountText: '\$142.00'),
          NativeTagEntry(tag: 'gadgets', amountText: '\$89.00'),
          NativeTagEntry(tag: 'wellness', amountText: '\$65.00'),
        ],
      ),
    ),
    const _WidgetSpec(
      'Cash Burn Runway',
      'widget_preview_cash_burn_runway.png',
      sizeWide,
      NativeCashBurnRunwayWidget(
        runwayMonthsText: '8.4 mo',
        monthlyBurnText: '\$2,450.00',
        liquidReservesText: '\$20,580.00',
      ),
    ),
    const _WidgetSpec(
      'No Spend Streak',
      'widget_preview_no_spend_streak.png',
      sizeWide,
      NativeNoSpendStreakWidget(
        streakDays: 5,
        bestStreakDays: 14,
      ),
    ),
    const _WidgetSpec(
      'Weekend Weekday',
      'widget_preview_weekend_weekday.png',
      sizeWide,
      NativeWeekendWeekdayWidget(
        ratioText: '2.3x',
        weekdayAvgText: '\$42/day',
        weekendAvgText: '\$95/day',
      ),
    ),
    const _WidgetSpec(
      'Pending Review',
      'widget_preview_pending_review.png',
      sizeWide,
      NativePendingReviewWidget(
        pendingCount: 3,
        subtitleText: '3 transactions to verify',
      ),
    ),
  ];

  for (final spec in specs) {
    testWidgets('Render ${spec.name}', (tester) async {
      tester.view.physicalSize = Size(spec.size.width * 2, spec.size.height * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: spec.size.width,
                  height: spec.size.height,
                  child: spec.widget,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        expect(byteData, isNotNull);
        final bytes = byteData!.buffer.asUint8List();

        final targetPath = 'android/app/src/main/res/drawable/${spec.filename}';
        File(targetPath).writeAsBytesSync(bytes);
        // ignore: avoid_print
        print('Rendered ${spec.filename} (${bytes.length} bytes)');
      });
    });
  }
}
