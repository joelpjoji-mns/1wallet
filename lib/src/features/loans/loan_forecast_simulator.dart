import 'dart:math' as math;

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

class ForecastImpact {
  final int interestSavedMinor;
  final int monthsSaved;

  ForecastImpact({
    required this.interestSavedMinor,
    required this.monthsSaved,
  });
}

class LoanForecastSimulationResult {
  final List<ForecastDataPoint> balanceCurve;
  final List<PayoffEvent> payoffEvents;
  final int initialBalanceMinor;
  final ForecastImpact impact;

  LoanForecastSimulationResult({
    required this.balanceCurve,
    required this.payoffEvents,
    required this.initialBalanceMinor,
    required this.impact,
  });
}

class ActiveLoan {
  final Account account;
  final int principalMinor;
  final int monthlyEmiMinor;
  final double annualRatePercent;

  ActiveLoan({
    required this.account,
    required this.principalMinor,
    required this.monthlyEmiMinor,
    required this.annualRatePercent,
  });
}

class _SimulatedLoan {
  final Account account;
  double balance;
  final double dailyEmi;
  final double dailyRate;
  
  double totalInterestPaid = 0;
  DateTime? payoffDate;

  _SimulatedLoan(ActiveLoan active) 
      : account = active.account,
        balance = active.principalMinor.toDouble(),
        dailyEmi = active.monthlyEmiMinor.toDouble() / 30.0,
        dailyRate = active.annualRatePercent <= 0 ? 0 : (active.annualRatePercent / 100.0 / 365.0);
}

LoanForecastSimulationResult simulateForecastPayoffGraph({
  required LedgerState state,
  required List<ActiveLoan> activeLoans,
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
  
  void addDeltas(TransactionRecord tx) {
    int lDelta = 0;

    final sourceAccount = accountById(state, tx.accountId);
    final isSourceTracked = sourceAccount != null && !sourceAccount.isArchived;
    final isSourceLiquid = isSourceTracked && !isLiabilityAccount(sourceAccount);

    if (isSourceTracked) {
      final sourceMoney = Money(amountMinor: sourceDelta(tx), currency: tx.amount.currency);
      final val = convertMoneyForDisplay(state, sourceMoney, state.preferences.baseCurrency).amountMinor;
      if (isSourceLiquid) lDelta += val;
    }

    if (tx.counterAccountId != null) {
      final counterAccount = accountById(state, tx.counterAccountId);
      final isCounterTracked = counterAccount != null && !counterAccount.isArchived;
      final isCounterLiquid = isCounterTracked && !isLiabilityAccount(counterAccount);

      if (isCounterTracked) {
        final counterMoney = Money(amountMinor: counterDelta(tx), currency: tx.counterAmount?.currency ?? tx.amount.currency);
        final val = convertMoneyForDisplay(state, counterMoney, state.preferences.baseCurrency).amountMinor;
        if (isCounterLiquid) lDelta += val;
      }
    }

    if (lDelta != 0) {
      final daysSinceStart = tx.occurredAt.difference(startDate).inDays;
      liquidDeltas[daysSinceStart] = (liquidDeltas[daysSinceStart] ?? 0) + lDelta;
    }
  }

  // Process Past Transactions
  for (final tx in state.transactions) {
    if (tx.status == 'scheduled' || tx.status == 'void' || tx.status == 'forecast') continue;
    if (tx.occurredAt.isBefore(pastStart) || tx.occurredAt.isAfter(startDate)) continue;
    addDeltas(tx);
  }

  // Process Future Forecasts (Base Income/Expenses)
  final forecasts = forecastRecurringTransactions(state, startDate.add(const Duration(days: 1)), futureEnd);
  for (final tx in forecasts) {
    // Exclude loan EMI forecasts from liquidDeltas because we simulate them manually!
    if (tx.type == 'loan_repayment') continue; 
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

  // Initialize simulation states
  final baseLoans = activeLoans.map((l) => _SimulatedLoan(l)).toList();
  final acceleratedLoans = activeLoans.map((l) => _SimulatedLoan(l)).toList();
  
  // Sort by priority (highest priority first)
  acceleratedLoans.sort((a, b) {
    final aIndex = loanPriorityIds.indexOf(a.account.id);
    final bIndex = loanPriorityIds.indexOf(b.account.id);
    if (aIndex != -1 && bIndex != -1) return aIndex.compareTo(bIndex);
    if (aIndex != -1) return -1;
    if (bIndex != -1) return 1;
    return b.dailyRate.compareTo(a.dailyRate); // Fallback to interest rate
  });
  
  // 3. Simulate forwards for 5 years
  final rawFutureBalances = List<int>.filled(1826, 0);
  int tempBal = initialNetLiquidBalance;
  for (int i = 1; i <= 1825; i++) {
    tempBal += (liquidDeltas[i] ?? 0);
    rawFutureBalances[i] = tempBal;
  }

  final minFutureBalance = List<int>.filled(1826, 0);
  minFutureBalance[1825] = rawFutureBalances[1825];
  for (int i = 1824; i >= 1; i--) {
    minFutureBalance[i] = math.min(rawFutureBalances[i], minFutureBalance[i + 1]);
  }

  int baseTotalInterest = 0;
  int acceleratedTotalInterest = 0;
  int baseMaxMonths = 0;
  int acceleratedMaxMonths = 0;

  double currentFutureLiquid = initialNetLiquidBalance.toDouble();

  for (int i = 1; i <= 1825; i++) {
    final date = startDate.add(Duration(days: i));
    
    currentFutureLiquid += (liquidDeltas[i] ?? 0);

    // --- BASE SCENARIO (No Extra Payments, just standard EMI) ---
    for (final loan in baseLoans) {
      if (loan.balance > 0) {
        final interest = loan.balance * loan.dailyRate;
        loan.balance += interest;
        loan.totalInterestPaid += interest;
        baseTotalInterest += interest.round();
        
        final payment = math.min(loan.balance, loan.dailyEmi);
        loan.balance -= payment;
        if (loan.balance <= 0 && loan.payoffDate == null) {
          loan.payoffDate = date;
          baseMaxMonths = math.max(baseMaxMonths, (i / 30).ceil());
        }
      }
    }

    // --- ACCELERATED SCENARIO (With Extra Payments) ---
    double dailyEmiTotal = 0;
    for (final loan in acceleratedLoans) {
      if (loan.balance > 0) {
        final interest = loan.balance * loan.dailyRate;
        loan.balance += interest;
        loan.totalInterestPaid += interest;
        acceleratedTotalInterest += interest.round();
        
        final payment = math.min(loan.balance, loan.dailyEmi);
        loan.balance -= payment;
        dailyEmiTotal += payment;
      }
    }

    currentFutureLiquid -= dailyEmiTotal;
    
    final rawFutureMin = minFutureBalance[i];
    final dropFromTodayToFutureMin = rawFutureBalances[i] - rawFutureMin; 
    final safeCurrentLiquid = currentFutureLiquid - dropFromTodayToFutureMin;
    final cashAboveEmergency = safeCurrentLiquid - emergencySavingMinor;

    if (cashAboveEmergency > 0 && extraPaymentAllocationPercent > 0) {
      double extraCashAvailable = cashAboveEmergency * extraPaymentAllocationPercent;
      
      for (final loan in acceleratedLoans) {
        if (extraCashAvailable <= 0) break;
        if (loan.balance > 0) {
          final payment = math.min(loan.balance, extraCashAvailable);
          loan.balance -= payment;
          extraCashAvailable -= payment;
          currentFutureLiquid -= payment;
        }
      }
    }
    
    for (final loan in acceleratedLoans) {
      if (loan.balance <= 0 && loan.payoffDate == null) {
        loan.payoffDate = date;
        payoffEvents.add(PayoffEvent(loan.account, date));
        acceleratedMaxMonths = math.max(acceleratedMaxMonths, (i / 30).ceil());
      }
    }

    balanceCurve.add(ForecastDataPoint(date, currentFutureLiquid.round()));
  }

  int interestSaved = baseTotalInterest - acceleratedTotalInterest;
  if (interestSaved < 0) interestSaved = 0;
  
  int monthsSaved = baseMaxMonths - acceleratedMaxMonths;
  if (monthsSaved < 0) monthsSaved = 0;

  return LoanForecastSimulationResult(
    balanceCurve: balanceCurve,
    payoffEvents: payoffEvents,
    initialBalanceMinor: initialNetLiquidBalance,
    impact: ForecastImpact(
      interestSavedMinor: interestSaved,
      monthsSaved: monthsSaved,
    ),
  );
}
