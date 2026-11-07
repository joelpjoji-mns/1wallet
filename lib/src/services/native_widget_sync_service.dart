import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/ledger_models.dart';
import '../design/tokens.dart';
import '../ledger/ledger_selectors.dart';
import 'native_widget_previews.dart';

/// Service responsible for updating native Android / iOS home screen widgets.
///
/// Each widget is now rendered as a **Flutter bitmap** via
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
  ];

  // ── Render sizes (logical pixels) ──────────────────────────────────────────
  // These match the Android widget sizes declared in the xml/widget_*_info.xml
  // files. The home_widget package scales the rendered bitmap to fill the
  // native widget frame.
  static const Size _sizeWide = Size(400, 220); // 4×2 cells
  static const Size _sizeCompact = Size(400, 160); // 4×1 cells
  static const Size _sizeTall = Size(400, 320); // 4×3 cells

  /// Synchronises current ledger data into native HomeWidget bitmaps.
  static Future<void> syncWidgets(
    LedgerState state, {
    ThemeData? theme,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Build the Material theme that wraps every rendered widget.  Falls back
    // to a neutral dark theme when the caller doesn't provide one (e.g. during
    // background updates when no BuildContext is available).
    final renderTheme = theme ?? _defaultDarkTheme();

    try {
      final currency = state.preferences.displayCurrency.toUpperCase();
      final locale = state.preferences.locale;
      final now = DateTime.now();

      // ── 1. Balance Hero ──────────────────────────────────────────────────
      final totalBal = totalBalance(state);
      final netWorthVal = netWorth(state).total;
      final monthFlow = flowForPeriod(state, 'This month');

      // Currency breakdown chips (same logic as BalanceHomeWidget)
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
          color: accountDisplayColor(acc),
          isNegative: display.amountMinor < 0,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeAccountsWidget(
            accounts: accountEntries,
            accountCount:
                '${accounts.length} account${accounts.length == 1 ? '' : 's'}',
          ),
        ),
        logicalSize: _sizeTall,
        key: 'widget_accounts_bitmap',
      );

      // ── 3. Recent Records ────────────────────────────────────────────────
      final recent = sortedTransactions(state, includeScheduled: false)
          .where((t) => t.status != 'void')
          .take(5)
          .toList();

      final txnEntries = <NativeTransactionEntry>[];
      for (final t in recent) {
        final name = (t.name?.trim().isNotEmpty ?? false)
            ? t.name!.trim()
            : (t.notes?.trim().isNotEmpty ?? false)
                ? t.notes!.trim()
                : 'Record';
        final converted = convertMoneyForDisplay(state, t.amount, currency);
        final isExpense = expenseTypes.contains(t.type);
        final isTransfer = t.type == 'transfer';
        final prefix = isExpense ? '-' : (isTransfer ? '' : '+');
        final account = accountById(state, t.accountId);
        final dateLabel = _shortDate(t.occurredAt, locale);

        txnEntries.add(NativeTransactionEntry(
          name: name,
          accountName: account?.name ?? '',
          dateLabel: dateLabel,
          amountText: '$prefix${formatMoney(converted, locale)}',
          isExpense: isExpense,
          isTransfer: isTransfer,
        ));
      }

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeRecentWidget(transactions: txnEntries),
        ),
        logicalSize: _sizeTall,
        key: 'widget_recent_bitmap',
      );

      // ── 4. Safe-to-Spend ─────────────────────────────────────────────────
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final dayOfMonth = now.day;
      final remainingDays = math.max(1, daysInMonth - dayOfMonth + 1);
      final startOfMonth = DateTime(now.year, now.month, 1);
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrowStart = todayStart.add(const Duration(days: 1));

      var monthExpensesMinor = 0;
      var todayExpensesMinor = 0;
      var monthIncomeMinor = 0;

      for (final t in state.transactions) {
        if (t.status == 'void' ||
            t.status == 'scheduled' ||
            t.status == 'paused') {
          continue;
        }
        if (t.occurredAt.isBefore(startOfMonth)) continue;
        final converted = convertMoneyForDisplay(state, t.amount, currency);
        if (expenseTypes.contains(t.type)) {
          monthExpensesMinor += converted.amountMinor;
          if (!t.occurredAt.isBefore(todayStart) &&
              t.occurredAt.isBefore(tomorrowStart)) {
            todayExpensesMinor += converted.amountMinor;
          }
        } else if (incomeTypes.contains(t.type)) {
          monthIncomeMinor += converted.amountMinor;
        }
      }

      final balanceRemainingMinor =
          math.max(0, monthIncomeMinor - monthExpensesMinor);
      final safeDailyAllowanceMinor =
          (balanceRemainingMinor / remainingDays).round();
      final spentRatio = safeDailyAllowanceMinor > 0
          ? (todayExpensesMinor / safeDailyAllowanceMinor).clamp(0.0, 1.0)
          : 1.0;

      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: NativeSafeSpendWidget(
            dailyAllowance: formatMoney(
              Money(amountMinor: safeDailyAllowanceMinor, currency: currency),
              locale,
            ),
            spentToday: formatMoney(
              Money(amountMinor: todayExpensesMinor, currency: currency),
              locale,
            ),
            spentRatio: spentRatio,
            remainingDays: remainingDays,
            dayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,
          ),
        ),
        logicalSize: _sizeWide,
        key: 'widget_safe_bitmap',
      );

      // ── 5. Upcoming & Due ────────────────────────────────────────────────
      final scheduled = scheduledTransactions(state)
          .where((t) => t.status != 'void' && t.status != 'paused')
          .toList();
      final today = DateTime(now.year, now.month, now.day);
      scheduled.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

      final overdueCount = scheduled.where((t) {
        final d = DateTime(
            t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
        return d.isBefore(today);
      }).length;

      final dueExpenseAmountMinor = scheduled
          .where((t) => expenseTypes.contains(t.type))
          .fold<int>(0, (sum, t) => sum + t.baseAmount.amountMinor);

      final upcomingEntries = <NativeUpcomingEntry>[];
      for (final t in scheduled.take(4)) {
        final name = (t.name?.trim().isNotEmpty ?? false)
            ? t.name!.trim()
            : (t.notes?.trim().isNotEmpty ?? false)
                ? t.notes!.trim()
                : 'Scheduled';
        final account = accountById(state, t.accountId);
        final dueDay = DateTime(
            t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
        final daysUntil = dueDay.difference(today).inDays;
        final converted = convertMoneyForDisplay(state, t.amount, currency);

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
      final todayFlow = flowForPeriod(state, 'Today');
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

      // ── 7. Quick Actions (static) ─────────────────────────────────────────
      await HomeWidget.renderFlutterWidget(
        Theme(
          data: renderTheme,
          child: const NativeQuickActionsWidget(),
        ),
        logicalSize: _sizeCompact,
        key: 'widget_quick_actions_bitmap',
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

  /// Minimal dark Material 3 theme used when no live [ThemeData] is provided
  /// (e.g. background refresh). Matches the app's dark-mode colour scheme.
  static ThemeData _defaultDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
    );
  }
}
