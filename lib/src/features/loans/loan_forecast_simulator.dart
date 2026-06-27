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
  int initialNetLiquidBalance = 0;
  
  for (final account in state.accounts) {
    if (!account.isArchived) {
      final balance = convertMoneyForDisplay(
        state,
        accountBalance(state, account),
        state.preferences.baseCurrency,
      );
      if (!isLiabilityAccount(account)) {
        initialNetLiquidBalance += balance.amountMinor;
      }
    }
  }

  final today = DateTime.now();
  final startDate = DateTime(today.year, today.month, today.day);
  final pastStart = startDate.subtract(const Duration(days: 365));
  final futureEnd = startDate.add(const Duration(days: 1825)); // 5 years

  final liquidDeltas = <int, int>{};
  final nwDeltas = <int, int>{};

  void addDeltas(TransactionRecord tx) {
    int lDelta = 0;
    int nwDelta = 0;

    final sourceAccount = accountById(state, tx.accountId);
    final isSourceTracked = sourceAccount != null && !sourceAccount.isArchived;
    final isSourceLiquid = isSourceTracked && !isLiabilityAccount(sourceAccount);

    if (isSourceTracked) {
      final sourceMoney = Money(amountMinor: sourceDelta(tx), currency: tx.amount.currency);
      final val = convertMoneyForDisplay(state, sourceMoney, state.preferences.baseCurrency).amountMinor;
      nwDelta += val;
      if (isSourceLiquid) lDelta += val;
    }

    if (tx.counterAccountId != null) {
      final counterAccount = accountById(state, tx.counterAccountId);
      final isCounterTracked = counterAccount != null && !counterAccount.isArchived;
      final isCounterLiquid = isCounterTracked && !isLiabilityAccount(counterAccount);

      if (isCounterTracked) {
        final counterMoney = Money(amountMinor: counterDelta(tx), currency: tx.counterAmount?.currency ?? tx.amount.currency);
        final val = convertMoneyForDisplay(state, counterMoney, state.preferences.baseCurrency).amountMinor;
        nwDelta += val;
        if (isCounterLiquid) lDelta += val;
      }
    }

    if (lDelta != 0 || nwDelta != 0) {
      final daysSinceStart = tx.occurredAt.difference(startDate).inDays;
      if (lDelta != 0) liquidDeltas[daysSinceStart] = (liquidDeltas[daysSinceStart] ?? 0) + lDelta;
      if (nwDelta != 0) nwDeltas[daysSinceStart] = (nwDeltas[daysSinceStart] ?? 0) + nwDelta;
    }
  }

  // Process Past Transactions
  for (final tx in state.transactions) {
    if (tx.status == 'scheduled' || tx.status == 'void' || tx.status == 'forecast') continue;
    if (tx.occurredAt.isBefore(pastStart) || tx.occurredAt.isAfter(startDate)) continue;
    addDeltas(tx);
  }

  // Process Future Forecasts
  final forecasts = forecastRecurringTransactions(state, startDate.add(const Duration(days: 1)), futureEnd);
  for (final tx in forecasts) {
    addDeltas(tx);
  }

  final balanceCurve = <ForecastDataPoint>[];
  final payoffEvents = <PayoffEvent>[];

  // 1. Simulate backwards for past 365 days
  int currentPastLiquid = initialNetLiquidBalance;
  final pastCurve = <ForecastDataPoint>[];
  for (int i = 0; i >= -365; i--) {
    final date = startDate.add(Duration(days: i));
    pastCurve.add(ForecastDataPoint(date, currentPastLiquid));
    final delta = liquidDeltas[i] ?? 0;
    currentPastLiquid -= delta;
  }
  balanceCurve.addAll(pastCurve.reversed);

  // 2. Track active loans for the future
  final activeLoans = <String, int>{};
  for (final loan in loans) {
    final bal = accountBalance(state, loan);
    final converted = convertMoneyForDisplay(state, bal, state.preferences.baseCurrency);
    activeLoans[loan.id] = converted.amountMinor.abs();
  }

  // 3. Simulate forwards for 5 years
  int currentFutureLiquid = initialNetLiquidBalance;

  for (int i = 1; i <= 1825; i++) {
    final date = startDate.add(Duration(days: i));
    
    currentFutureLiquid += (liquidDeltas[i] ?? 0);

    bool paidSomething = true;
    while (paidSomething) {
      paidSomething = false;
      for (final loanId in loanPriorityIds) {
        final balance = activeLoans[loanId] ?? 0;
        if (balance <= 0) continue;

        final cashAboveEmergency = currentFutureLiquid - emergencySavingMinor;
        if (cashAboveEmergency > 0) {
          final maxPayment = (cashAboveEmergency * extraPaymentAllocationPercent).floor();
          
          if (maxPayment >= balance) {
            currentFutureLiquid -= balance;
            activeLoans[loanId] = 0;
            final loanObj = loans.firstWhereOrNull((l) => l.id == loanId);
            if (loanObj != null) {
              payoffEvents.add(PayoffEvent(loanObj, date));
            }
            paidSomething = true;
          }
        }
        break; 
      }
    }
    
    balanceCurve.add(ForecastDataPoint(date, currentFutureLiquid));
  }

  return LoanForecastSimulationResult(
    balanceCurve: balanceCurve,
    payoffEvents: payoffEvents,
    initialBalanceMinor: initialNetLiquidBalance,
  );
}
