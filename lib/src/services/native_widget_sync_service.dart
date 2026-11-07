import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/ledger_models.dart';
import '../ledger/ledger_selectors.dart';
import '../utils/currency_utils.dart';

/// Service responsible for updating native Android / iOS home screen widgets.
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

  /// Synchronizes current ledger data into native HomeWidgets shared store.
  static Future<void> syncWidgets(LedgerState state) async {
    // Widgets are currently supported on Android & iOS platforms
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    try {
      final currency = state.preferences.displayCurrency.toUpperCase();
      final locale = state.preferences.locale;

      // 1. Balance & Cash flow
      final totalBal = totalBalance(state);
      final netWorthVal = netWorth(state).total;
      final monthFlow = flowForPeriod(state, 'This month');

      await HomeWidget.saveWidgetData<String>(
        'widget_total_balance',
        formatMoney(totalBal, locale),
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_networth',
        'Net Worth ${formatMoney(netWorthVal, locale)}',
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_income',
        '+${formatMoney(monthFlow.income, locale)}',
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_expense',
        '-${formatMoney(monthFlow.expense, locale)}',
      );

      // 2. Recent Transactions (top 3)
      final recent = sortedTransactions(state, includeScheduled: false)
          .where((t) => t.status != 'void')
          .take(3)
          .toList();

      for (var i = 0; i < 3; i++) {
        final keyNum = i + 1;
        if (i < recent.length) {
          final t = recent[i];
          final name = (t.name?.trim().isNotEmpty ?? false)
              ? t.name!.trim()
              : (t.notes?.trim().isNotEmpty ?? false)
                  ? t.notes!.trim()
                  : 'Record';
          final converted = convertMoneyForDisplay(state, t.amount, currency);
          final prefix = expenseTypes.contains(t.type) ? '-' : (incomeTypes.contains(t.type) ? '+' : '');
          await HomeWidget.saveWidgetData<String>(
            'widget_recent_name_$keyNum',
            name,
          );
          await HomeWidget.saveWidgetData<String>(
            'widget_recent_amount_$keyNum',
            '$prefix${formatMoney(converted, locale)}',
          );
        } else {
          await HomeWidget.saveWidgetData<String>(
            'widget_recent_name_$keyNum',
            i == 0 ? 'No recent transactions' : '',
          );
          await HomeWidget.saveWidgetData<String>(
            'widget_recent_amount_$keyNum',
            '',
          );
        }
      }

      // 3. Safe-to-Spend
      final now = DateTime.now();
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
        if (t.status == 'void' || t.status == 'scheduled' || t.status == 'paused') {
          continue;
        }
        if (t.occurredAt.isBefore(startOfMonth)) continue;

        final converted = convertMoneyForDisplay(state, t.amount, currency);
        if (expenseTypes.contains(t.type)) {
          monthExpensesMinor += converted.amountMinor;
          if (!t.occurredAt.isBefore(todayStart) && t.occurredAt.isBefore(tomorrowStart)) {
            todayExpensesMinor += converted.amountMinor;
          }
        } else if (incomeTypes.contains(t.type)) {
          monthIncomeMinor += converted.amountMinor;
        }
      }

      final balanceRemainingMinor = math.max(0, monthIncomeMinor - monthExpensesMinor);
      final safeDailyAllowanceMinor = (balanceRemainingMinor / remainingDays).round();
      final spentRatio = safeDailyAllowanceMinor > 0
          ? (todayExpensesMinor / safeDailyAllowanceMinor).clamp(0.0, 1.0)
          : 1.0;
      final progressPercent = ((1.0 - spentRatio) * 100).round().clamp(0, 100);

      await HomeWidget.saveWidgetData<String>(
        'widget_safe_amount',
        formatMoney(Money(amountMinor: safeDailyAllowanceMinor, currency: currency), locale),
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_safe_subtitle',
        '$remainingDays days left in month · ${(spentRatio * 100).round()}% used',
      );
      await HomeWidget.saveWidgetData<int>(
        'widget_safe_progress',
        progressPercent,
      );

      // 4. Upcoming & Due
      final scheduled = scheduledTransactions(state).where((t) => t.status != 'void').toList();
      final today = DateTime(now.year, now.month, now.day);
      final overdueCount = scheduled.where((t) {
        final d = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
        return d.isBefore(today);
      }).length;
      final dueBadge = overdueCount > 0
          ? '$overdueCount overdue'
          : '${scheduled.length} scheduled';

      await HomeWidget.saveWidgetData<String>(
        'widget_upcoming_count',
        dueBadge,
      );

      for (var i = 0; i < 3; i++) {
        final keyNum = i + 1;
        if (i < scheduled.length) {
          final t = scheduled[i];
          final name = (t.name?.trim().isNotEmpty ?? false)
              ? t.name!.trim()
              : (t.notes?.trim().isNotEmpty ?? false)
                  ? t.notes!.trim()
                  : 'Scheduled';
          final converted = convertMoneyForDisplay(state, t.amount, currency);
          await HomeWidget.saveWidgetData<String>(
            'widget_upcoming_name_$keyNum',
            name,
          );
          await HomeWidget.saveWidgetData<String>(
            'widget_upcoming_amount_$keyNum',
            formatMoney(converted, locale),
          );
        } else {
          await HomeWidget.saveWidgetData<String>(
            'widget_upcoming_name_$keyNum',
            i == 0 ? 'No upcoming payments' : '',
          );
          await HomeWidget.saveWidgetData<String>(
            'widget_upcoming_amount_$keyNum',
            '',
          );
        }
      }

      // 5. Calendar / Today's Pace
      final todayFlow = flowForPeriod(state, 'Today');
      final monthExpense = monthFlow.expense;
      final monthName = DateFormat('MMMM yyyy', locale).format(now);

      await HomeWidget.saveWidgetData<String>(
        'widget_calendar_month',
        monthName,
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_calendar_spent_today',
        formatMoney(todayFlow.expense, locale),
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_calendar_spent_month',
        formatMoney(monthExpense, locale),
      );

      // 6. Accounts Overview (top 3)
      final accounts = state.accounts.where((a) => !a.isArchived).toList();
      await HomeWidget.saveWidgetData<String>(
        'widget_accounts_count',
        '${accounts.length} account${accounts.length == 1 ? '' : 's'}',
      );

      for (var i = 0; i < 3; i++) {
        final keyNum = i + 1;
        if (i < accounts.length) {
          final acc = accounts[i];
          final bal = accountBalance(state, acc);
          await HomeWidget.saveWidgetData<String>(
            'widget_acc_name_$keyNum',
            acc.name,
          );
          await HomeWidget.saveWidgetData<String>(
            'widget_acc_bal_$keyNum',
            formatMoney(bal, locale),
          );
        } else {
          await HomeWidget.saveWidgetData<String>(
            'widget_acc_name_$keyNum',
            i == 0 ? 'No accounts' : '',
          );
          await HomeWidget.saveWidgetData<String>(
            'widget_acc_bal_$keyNum',
            '',
          );
        }
      }

      // Trigger update on all widget providers
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
}
