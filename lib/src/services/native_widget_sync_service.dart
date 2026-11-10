import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ledger_models.dart';
import '../ledger/ledger_selectors.dart';
import '../theme/app_theme.dart';
import 'native_widget_previews.dart';

/// Service responsible for updating native Android / iOS home screen widgets.
///
/// Each widget is rendered as a **Flutter bitmap** via
/// [HomeWidget.renderFlutterWidget], giving pixel-perfect fidelity with the
/// in-app home screen tiles — same glass panel, typography, colors, and layout.
class NativeWidgetSyncService {
  NativeWidgetSyncService._();

  static const List<String> androidWidgetProviders = [
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
  ];

  // ── Render sizes (logical pixels) ──────────────────────────────────────────
  static const Size _sizeWide = Size(400, 220); // 4×2 cells
  static const Size _sizeCompact = Size(400, 160); // 4×1 cells
  static const Size _sizeTall = Size(400, 320); // 4×3 cells

  /// Synchronises current ledger data into native HomeWidget bitmaps.
  static Future<void> syncWidgets(
    LedgerState state, {
    ThemeData? theme,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final renderTheme = theme ?? await _resolveTheme();

    try {
      final currency = state.preferences.displayCurrency.toUpperCase();
      final locale = state.preferences.locale;
      final now = DateTime.now();

      // ── 1. Balance Hero ──────────────────────────────────────────────────
      final totalBal = totalBalance(state);
      final netWorthVal = netWorth(state).total;
      final monthFlow = flowForPeriod(state, 'This month');

      final allCurrencies = availableCurrencies(state);
      final currencyBreakdown = <String>[];
      for (final cur in allCurrencies.take(3)) {
        final converted = convertMoneyForDisplay(
          state,
          Money(amountMinor: totalBal.amountMinor, currency: currency),
          cur,
        );
        currencyBreakdown.add('$cur ${formatMoney(converted, locale)}');
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeBalanceWidget(
            totalBalance: formatMoney(totalBal, locale),
            netWorthLabel: 'Net Worth ${formatMoney(netWorthVal, locale)}',
            incomeText: '+${formatMoney(monthFlow.income, locale)}',
            expenseText: '-${formatMoney(monthFlow.expense, locale)}',
            currencyBreakdown: currencyBreakdown,
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_balance_bitmap',
      );

      // ── 2. Accounts Overview ─────────────────────────────────────────────
      final accounts = state.accounts
          .where((a) => !a.isArchived && a.showOnHome)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final balancesMap = accountBalanceMap(state);

      final accountEntries = <NativeAccountEntry>[];
      for (final acc in accounts.take(6)) {
        final bal = accountBalanceFromMap(balancesMap, acc);
        final display = convertMoneyForDisplay(state, bal);
        accountEntries.add(NativeAccountEntry(
          name: acc.name,
          balance: formatMoney(display, locale),
          type: acc.type,
          color: acc.color ?? renderTheme.colorScheme.primary,
          isNegative: bal.amountMinor < 0,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeAccountsWidget(
            accounts: accountEntries,
            accountCount: '${accounts.length} accounts',
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_accounts_bitmap',
      );

      // ── 3. Recent Transactions ───────────────────────────────────────────
      final txList = sortedTransactions(state, includeScheduled: false)
          .where((t) => t.status != 'void')
          .take(4)
          .toList();

      final categoryMap = {for (final c in state.categories) c.id: c};
      final accountMap = {for (final a in state.accounts) a.id: a};

      final recentEntries = <NativeTransactionEntry>[];
      for (final tx in txList) {
        final cat = tx.categoryId != null ? categoryMap[tx.categoryId] : null;
        final acc = accountMap[tx.accountId];
        final converted = convertMoneyForDisplay(state, tx.amount);
        final isIncome = tx.type == 'income';
        final isTransfer = tx.type == 'transfer';
        final isExpense = expenseTypes.contains(tx.type);

        recentEntries.add(NativeTransactionEntry(
          name: tx.name?.isNotEmpty == true
              ? tx.name!
              : (cat?.name ?? 'Transaction'),
          accountName: acc?.name ?? '',
          dateLabel: _shortDate(tx.occurredAt, locale),
          amountText: '${isIncome ? '+' : '-'}${formatMoney(converted, locale)}',
          isExpense: isExpense,
          isTransfer: isTransfer,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeRecentWidget(transactions: recentEntries),
        ),
        logicalSize: _sizeTall,
        key: 'widget_recent_bitmap',
      );

      // ── 4. Safe to Spend ──────────────────────────────────────────────────
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final dayOfMonth = now.day;
      final remainingDays = math.max(1, daysInMonth - dayOfMonth + 1);
      final todayFlow = flowForPeriod(state, 'Today');
      final monthBudget = monthFlow.income.amountMinor > 0
          ? monthFlow.income.amountMinor
          : 200000;
      final safeSpendDaily = ((monthBudget - monthFlow.expense.amountMinor) / remainingDays).round();
      final safeSpendMoney = Money(
        amountMinor: math.max(0, safeSpendDaily),
        currency: currency,
      );
      final spentRatio = monthBudget > 0
          ? (monthFlow.expense.amountMinor / monthBudget).clamp(0.0, 1.0)
          : 0.0;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeSafeSpendWidget(
            dailyAllowance: formatMoney(safeSpendMoney, locale),
            spentToday: formatMoney(todayFlow.expense, locale),
            spentRatio: spentRatio,
            remainingDays: remainingDays,
            dayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_safe_spend_bitmap',
      );

      // ── 5. Upcoming & Due ────────────────────────────────────────────────
      final scheduled = scheduledTransactions(state)
          .where((t) => t.status != 'void' && t.status != 'paused')
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

      final upcomingEntries = <NativeUpcomingEntry>[];
      int overdueCount = 0;
      int dueExpenseAmountMinor = 0;

      for (final tx in scheduled.take(5)) {
        final daysUntil = tx.occurredAt
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        if (daysUntil < 0) overdueCount++;
        final converted = convertMoneyForDisplay(state, tx.amount);
        if (expenseTypes.contains(tx.type)) {
          dueExpenseAmountMinor += converted.amountMinor;
        }

        final cat = tx.categoryId != null ? categoryMap[tx.categoryId] : null;
        final account = accountMap[tx.accountId];
        final name = tx.name?.isNotEmpty == true ? tx.name! : (cat?.name ?? 'Payment');

        upcomingEntries.add(NativeUpcomingEntry(
          name: name,
          accountName: account?.name ?? '',
          amountText: formatMoney(converted, locale),
          daysUntilDue: daysUntil,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeUpcomingWidget(
            entries: upcomingEntries,
            dueSoonCount: scheduled.length,
            totalAmountDue: formatMoney(
              Money(amountMinor: dueExpenseAmountMinor, currency: currency),
              locale,
            ),
            overdueCount: overdueCount,
          ),
        ),
        logicalSize: _sizeTall,
        key: 'widget_upcoming_bitmap',
      );

      // ── 6. Calendar / Today's Pace ───────────────────────────────────────
      final monthExpense = monthFlow.expense;
      final monthName = DateFormat('MMMM yyyy', locale).format(now);

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeCalendarWidget(
            monthLabel: monthName,
            spentToday: formatMoney(todayFlow.expense, locale),
            spentThisMonth: formatMoney(monthExpense, locale),
          ),
        ),
        logicalSize: _sizeCompact,
        key: 'widget_calendar_bitmap',
      );

      // ── 7. Quick Actions ──────────────────────────────────────────────────
      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: const NativeQuickActionsWidget(),
        ),
        logicalSize: _sizeCompact,
        key: 'widget_quick_actions_bitmap',
      );

      // ── 8. Balance & Net Worth Trend ───────────────────────────────────────
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      int runningMinor = totalBal.amountMinor;
      final dailyDelta = <int, int>{};
      for (final t in state.transactions) {
        if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') continue;
        if (t.occurredAt.isAfter(thirtyDaysAgo) && t.occurredAt.isBefore(now)) {
          final dayDiff = now.difference(t.occurredAt).inDays;
          final conv = convertMoneyForDisplay(state, t.amount, currency);
          final sign = expenseTypes.contains(t.type) ? -1 : 1;
          dailyDelta[dayDiff] = (dailyDelta[dayDiff] ?? 0) + (conv.amountMinor * sign);
        }
      }
      var curr = runningMinor;
      final pointVals = <int>[];
      for (var d = 0; d <= 30; d += 2) {
        pointVals.insert(0, curr);
        curr -= (dailyDelta[d] ?? 0);
      }
      final minVal = pointVals.isNotEmpty ? pointVals.reduce(math.min) : 0;
      final maxVal = pointVals.isNotEmpty ? pointVals.reduce(math.max) : 1;
      final range = (maxVal - minVal).abs() > 0 ? (maxVal - minVal) : 1;
      final trendPoints = pointVals
          .map((p) => ((p - minVal) / range).clamp(0.0, 1.0))
          .toList();

      final delta = totalBal.amountMinor - curr;
      final isTrendPos = delta >= 0;
      final deltaMoney = Money(amountMinor: delta.abs(), currency: currency);

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeBalanceTrendWidget(
            netWorthLabel: formatMoney(netWorthVal, locale),
            deltaText: '${isTrendPos ? '+' : '-'}${formatMoney(deltaMoney, locale)}',
            isPositive: isTrendPos,
            points: trendPoints,
            periodLabel: 'Last 30 days',
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_balance_trend_bitmap',
      );

      // ── 9. Top Categories ────────────────────────────────────────────────
      final catTotals = <String, int>{};
      final startOfMonth = DateTime(now.year, now.month, 1);
      int totalCatExpenseMinor = 0;
      for (final t in state.transactions) {
        if (t.status == 'void' || !expenseTypes.contains(t.type)) continue;
        if (t.occurredAt.isBefore(startOfMonth)) continue;
        final cId = t.categoryId ?? 'uncategorized';
        final conv = convertMoneyForDisplay(state, t.amount, currency);
        catTotals[cId] = (catTotals[cId] ?? 0) + conv.amountMinor;
        totalCatExpenseMinor += conv.amountMinor;
      }
      final sortedCats = catTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final catEntries = <NativeCategoryEntry>[];
      for (final entry in sortedCats.take(4)) {
        final cat = categoryMap[entry.key];
        final name = cat?.name ?? 'Uncategorized';
        final pct = totalCatExpenseMinor > 0 ? (entry.value / totalCatExpenseMinor) : 0.0;
        catEntries.add(NativeCategoryEntry(
          name: name,
          amountText: formatMoney(Money(amountMinor: entry.value, currency: currency), locale),
          percentage: pct,
          color: cat?.color ?? renderTheme.colorScheme.primary,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeTopCategoriesWidget(
            categories: catEntries,
            periodLabel: 'This month',
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_top_categories_bitmap',
      );

      // ── 10. Currency Exchange Values ─────────────────────────────────────
      final currencyEntries = <NativeCurrencyEntry>[];
      for (final cur in allCurrencies.where((c) => c != currency).take(4)) {
        final oneUnit = Money(amountMinor: 100, currency: currency);
        final converted = convertMoneyForDisplay(state, oneUnit, cur);
        currencyEntries.add(NativeCurrencyEntry(
          currencyCode: cur,
          rateText: '1 $currency = ${(converted.amountMinor / 100.0).toStringAsFixed(2)} $cur',
          equivalentText: formatMoney(converted, locale),
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeCurrencyValuesWidget(
            baseCurrency: currency,
            rates: currencyEntries,
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_currency_values_bitmap',
      );

      // ── 11. Account Groups ────────────────────────────────────────────────
      final groupTotals = <String, int>{};
      final groupCounts = <String, int>{};
      for (final acc in accounts) {
        final grp = acc.groupName?.isNotEmpty == true ? acc.groupName! : 'Other';
        final bal = accountBalanceFromMap(balancesMap, acc);
        final display = convertMoneyForDisplay(state, bal);
        groupTotals[grp] = (groupTotals[grp] ?? 0) + display.amountMinor;
        groupCounts[grp] = (groupCounts[grp] ?? 0) + 1;
      }

      final groupEntries = <NativeAccountGroupEntry>[];
      for (final entry in groupTotals.entries) {
        final gName = entry.key;
        final total = entry.value;
        final count = groupCounts[gName] ?? 1;
        IconData icon = Icons.account_balance_rounded;
        Color col = renderTheme.colorScheme.primary;

        if (gName.toLowerCase().contains('cash')) {
          icon = Icons.payments_outlined;
          col = const Color(0xFF00E676);
        } else if (gName.toLowerCase().contains('credit')) {
          icon = Icons.credit_card_rounded;
          col = const Color(0xFFFF5252);
        } else if (gName.toLowerCase().contains('invest')) {
          icon = Icons.trending_up_rounded;
          col = const Color(0xFF7C4DFF);
        }

        groupEntries.add(NativeAccountGroupEntry(
          name: gName,
          balanceText: formatMoney(Money(amountMinor: total, currency: currency), locale),
          countText: '$count account${count > 1 ? 's' : ''}',
          icon: icon,
          color: col,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeAccountGroupsWidget(groups: groupEntries),
        ),
        logicalSize: _sizeWide,
        key: 'widget_account_groups_bitmap',
      );

      // ── 12. Credit Utilization ───────────────────────────────────────────
      final creditAccs = state.accounts
          .where((a) => (a.type == 'credit_card' || a.type == 'card') && !a.isArchived)
          .toList();
      int totalCreditLimitMinor = 0;
      int totalCreditUsedMinor = 0;
      for (final cAcc in creditAccs) {
        if (cAcc.creditLimit != null) {
          final lim = convertMoneyForDisplay(state, cAcc.creditLimit!, currency);
          totalCreditLimitMinor += lim.amountMinor;
        }
        final bal = accountBalanceFromMap(balancesMap, cAcc);
        final used = convertMoneyForDisplay(state, bal, currency);
        if (used.amountMinor < 0) {
          totalCreditUsedMinor += used.amountMinor.abs();
        }
      }
      final utilPct = totalCreditLimitMinor > 0
          ? ((totalCreditUsedMinor / totalCreditLimitMinor) * 100).clamp(0.0, 100.0)
          : 0.0;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeCreditUtilizationWidget(
            utilizationPercent: utilPct,
            usedAmountText: formatMoney(Money(amountMinor: totalCreditUsedMinor, currency: currency), locale),
            limitAmountText: formatMoney(Money(amountMinor: totalCreditLimitMinor, currency: currency), locale),
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_credit_utilization_bitmap',
      );

      // ── 13. Savings Rate ─────────────────────────────────────────────────
      final incomeMinor = monthFlow.income.amountMinor;
      final expenseMinor = monthFlow.expense.amountMinor;
      final savedMinor = incomeMinor - expenseMinor;
      final savingsPct = incomeMinor > 0
          ? ((savedMinor / incomeMinor) * 100).clamp(0.0, 100.0)
          : 0.0;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeSavingsRateWidget(
            savingsRatePercent: savingsPct,
            savedAmountText: formatMoney(Money(amountMinor: math.max(0, savedMinor), currency: currency), locale),
            incomeAmountText: formatMoney(monthFlow.income, locale),
            periodLabel: 'This month',
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_savings_rate_bitmap',
      );

      // ── 14. Tag Cloud ────────────────────────────────────────────────────
      final tagCounts = <String, int>{};
      final tagTotals = <String, int>{};
      for (final tx in state.transactions) {
        if (tx.status == 'void') continue;
        for (final tag in tx.tags) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
          tagTotals[tag] = (tagTotals[tag] ?? 0) + tx.amount.amountMinor;
        }
      }
      final sortedTags = tagCounts.keys.toList()
        ..sort((a, b) => (tagCounts[b] ?? 0).compareTo(tagCounts[a] ?? 0));
      final tagEntries = <NativeTagEntry>[];
      for (final tag in sortedTags.take(6)) {
        final tot = tagTotals[tag] ?? 0;
        tagEntries.add(NativeTagEntry(
          tag: tag,
          amountText: formatMoney(Money(amountMinor: tot, currency: currency), locale),
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeTagCloudWidget(tags: tagEntries),
        ),
        logicalSize: _sizeWide,
        key: 'widget_tag_cloud_bitmap',
      );

      // ── 15. Cash Burn Runway ─────────────────────────────────────────────
      int liquidTotalMinor = 0;
      for (final acc in accounts) {
        if (acc.type == 'cash' || acc.type == 'bank' || acc.type == 'checking' || acc.type == 'savings') {
          final bal = accountBalanceFromMap(balancesMap, acc);
          final conv = convertMoneyForDisplay(state, bal, currency);
          if (conv.amountMinor > 0) liquidTotalMinor += conv.amountMinor;
        }
      }
      final monthlyBurnMinor = monthFlow.expense.amountMinor > 0
          ? monthFlow.expense.amountMinor
          : 100000;
      final runwayMonths = monthlyBurnMinor > 0
          ? (liquidTotalMinor / monthlyBurnMinor)
          : 99.0;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeCashBurnRunwayWidget(
            runwayMonthsText: '${runwayMonths.toStringAsFixed(1)} mo',
            monthlyBurnText: formatMoney(Money(amountMinor: monthlyBurnMinor, currency: currency), locale),
            liquidReservesText: formatMoney(Money(amountMinor: liquidTotalMinor, currency: currency), locale),
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_cash_burn_runway_bitmap',
      );

      // ── 16. No-Spend Streak ──────────────────────────────────────────────
      final expenseDays = <int>{};
      for (final t in state.transactions) {
        if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') continue;
        if (!expenseTypes.contains(t.type)) continue;
        if (t.occurredAt.year == now.year && t.occurredAt.month == now.month) {
          expenseDays.add(t.occurredAt.day);
        }
      }
      int streak = 0;
      for (var d = now.day - 1; d >= 1; d--) {
        if (!expenseDays.contains(d)) {
          streak++;
        } else {
          break;
        }
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeNoSpendStreakWidget(
            streakDays: streak,
            bestStreakDays: math.max(streak, 7),
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_no_spend_streak_bitmap',
      );

      // ── 17. Weekend vs Weekday ───────────────────────────────────────────
      int weekendMinor = 0;
      int weekdayMinor = 0;
      int weekendDaysCount = 0;
      int weekdayDaysCount = 0;
      for (final t in state.transactions) {
        if (t.status == 'void' || !expenseTypes.contains(t.type)) continue;
        if (t.occurredAt.isBefore(thirtyDaysAgo)) continue;
        final isWeekend = t.occurredAt.weekday == DateTime.saturday || t.occurredAt.weekday == DateTime.sunday;
        final conv = convertMoneyForDisplay(state, t.amount, currency);
        if (isWeekend) {
          weekendMinor += conv.amountMinor;
        } else {
          weekdayMinor += conv.amountMinor;
        }
      }
      for (var i = 0; i < 30; i++) {
        final d = now.subtract(Duration(days: i));
        if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          weekendDaysCount++;
        } else {
          weekdayDaysCount++;
        }
      }
      final avgWeekday = weekdayDaysCount > 0 ? (weekdayMinor / weekdayDaysCount).round() : 0;
      final avgWeekend = weekendDaysCount > 0 ? (weekendMinor / weekendDaysCount).round() : 0;
      final ratio = avgWeekday > 0 ? (avgWeekend / avgWeekday) : 1.0;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeWeekendWeekdayWidget(
            ratioText: '${ratio.toStringAsFixed(1)}x',
            weekdayAvgText: formatMoney(Money(amountMinor: avgWeekday, currency: currency), locale),
            weekendAvgText: formatMoney(Money(amountMinor: avgWeekend, currency: currency), locale),
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_weekend_weekday_bitmap',
      );

      // ── 18. Pending Review ───────────────────────────────────────────────
      final pendingCount = state.captureCandidates.where((c) => c.status == 'pending').length;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativePendingReviewWidget(
            pendingCount: pendingCount,
            subtitleText: pendingCount > 0
                ? '$pendingCount transaction${pendingCount > 1 ? 's' : ''} to verify'
                : 'All transactions verified',
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_pending_review_bitmap',
      );

      // ── Trigger Android redraw on all providers ──────────────────────────
      for (final provider in androidWidgetProviders) {
        await HomeWidget.updateWidget(
          androidName: provider,
          qualifiedAndroidName: 'com.joelpjoji.one.wallet.$provider',
        );
      }
    } catch (e, stack) {
      debugPrint('NativeWidgetSyncService error: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _shortDate(DateTime date, String locale) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMM d', locale).format(date);
  }

  /// Resolves the theme dynamically based on user preferences.
  static Future<ThemeData> _resolveTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefName = prefs.getString('one_wallet_flutter.theme.preference.v1');
      if (prefName == 'light') {
        return AppTheme.light();
      } else if (prefName == 'amoled') {
        return AppTheme.amoled();
      }
    } catch (_) {}
    return AppTheme.amoled();
  }
}
