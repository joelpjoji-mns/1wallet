import 'package:collection/collection.dart';

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import '../calendar/calendar_forecast.dart';

class ForecastDataPoint {
  final DateTime date;
  final int netBalanceMinor;

  ForecastDataPoint(this.date, this.netBalanceMinor);
}

class PayoffEvent {
  final Account loan;
  final DateTime payoffDate;

  PayoffEvent(this.loan, this.payoffDate);
}

class LoanForecastSimulationResult {
  final List<ForecastDataPoint> balanceCurve;
  final List<PayoffEvent> payoffEvents;
  final int initialBalanceMinor;

  LoanForecastSimulationResult({
    required this.balanceCurve,
    required this.payoffEvents,
    required this.initialBalanceMinor,
  });
}

LoanForecastSimulationResult simulateForecastPayoffGraph({
  required LedgerState state,
  required List<Account> loans,
  required int emergencySavingMinor,
  required double extraPaymentAllocationPercent,
  required List<String> loanPriorityIds,
}) {
  // 1. Calculate Initial Net Liquid Balance.
  // We consider all active accounts that are not liabilities (i.e. checking, cash, savings).
  int netLiquidBalance = 0;
  for (final account in state.accounts) {
    if (!account.isArchived && !isLiabilityAccount(account)) {
      final balance = convertMoneyForDisplay(
        state,
        accountBalance(state, account),
        state.preferences.baseCurrency,
      );
      netLiquidBalance += balance.amountMinor;
    }
  }

  final initialBalanceMinor = netLiquidBalance;

  // 2. Fetch all forecasted transactions up to 5 years from now
  final startDate = DateTime.now();
  final endDate = DateTime(startDate.year + 5, startDate.month, startDate.day);
  final forecasts = forecastRecurringTransactions(state, startDate, endDate);

  // Group forecasts by day index (days since start)
  final dailyDeltas = <int, int>{};
  for (final tx in forecasts) {
    int delta = 0;

    final sourceAccount = accountById(state, tx.accountId);
    final isSourceLiquid = sourceAccount != null &&
        !sourceAccount.isArchived &&
        !isLiabilityAccount(sourceAccount);

    if (isSourceLiquid) {
      final sourceMoney = Money(amountMinor: sourceDelta(tx), currency: tx.amount.currency);
      delta += convertMoneyForDisplay(state, sourceMoney, state.preferences.baseCurrency).amountMinor;
    }

    if (tx.counterAccountId != null) {
      final counterAccount = accountById(state, tx.counterAccountId);
      final isCounterLiquid = counterAccount != null &&
          !counterAccount.isArchived &&
          !isLiabilityAccount(counterAccount);
      if (isCounterLiquid) {
        final counterMoney = Money(
          amountMinor: counterDelta(tx),
          currency: tx.counterAmount?.currency ?? tx.amount.currency,
        );
        delta += convertMoneyForDisplay(state, counterMoney, state.preferences.baseCurrency).amountMinor;
      }
    }

    if (delta != 0) {
      final daysSinceStart = tx.occurredAt.difference(startDate).inDays;
      if (daysSinceStart >= 0) {
        dailyDeltas[daysSinceStart] = (dailyDeltas[daysSinceStart] ?? 0) + delta;
      }
    }
  }

  // 3. Track active loans
  final activeLoans = <String, int>{};
  for (final loan in loans) {
    final bal = accountBalance(state, loan);
    final converted = convertMoneyForDisplay(state, bal, state.preferences.baseCurrency);
    activeLoans[loan.id] = converted.amountMinor.abs();
  }

  final balanceCurve = <ForecastDataPoint>[];
  final payoffEvents = <PayoffEvent>[];

  // 4. Simulate day by day
  final totalDays = endDate.difference(startDate).inDays;
  for (int i = 0; i <= totalDays; i++) {
    final currentDate = startDate.add(Duration(days: i));

    // Apply daily delta
    final delta = dailyDeltas[i] ?? 0;
    netLiquidBalance += delta;

    // Check payoffs according to priority
    bool paidSomething = true;
    while (paidSomething) {
      paidSomething = false;
      for (final loanId in loanPriorityIds) {
        final balance = activeLoans[loanId] ?? 0;
        if (balance <= 0) continue;

        final cashAboveEmergency = netLiquidBalance - emergencySavingMinor;
        if (cashAboveEmergency > 0) {
          final maxPayment = (cashAboveEmergency * extraPaymentAllocationPercent).floor();

          if (maxPayment >= balance) {
            // We can pay off this loan!
            netLiquidBalance -= balance;
            activeLoans[loanId] = 0;

            final loanObj = loans.firstWhereOrNull((l) => l.id == loanId);
            if (loanObj != null) {
              payoffEvents.add(PayoffEvent(loanObj, currentDate));
            }

            paidSomething = true;
            break; // Break the inner loop to re-evaluate priorities from top
          }
        }
      }
    }

    balanceCurve.add(ForecastDataPoint(currentDate, netLiquidBalance));
  }

  return LoanForecastSimulationResult(
    balanceCurve: balanceCurve,
    payoffEvents: payoffEvents,
    initialBalanceMinor: initialBalanceMinor,
  );
}
