import 'dart:math' as math;

import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';

class AcceleratedLoanProjection {
  final Account loan;
  final int baseEmiMinor;
  final int baseMonthsRemaining;
  final int baseInterestMinor;
  
  final int acceleratedMonthsRemaining;
  final int acceleratedInterestMinor;

  AcceleratedLoanProjection({
    required this.loan,
    required this.baseEmiMinor,
    required this.baseMonthsRemaining,
    required this.baseInterestMinor,
    required this.acceleratedMonthsRemaining,
    required this.acceleratedInterestMinor,
  });

  int get interestSavedMinor => baseInterestMinor - acceleratedInterestMinor;
  int get monthsSaved => baseMonthsRemaining - acceleratedMonthsRemaining;
}

class LoanForecastSimulationResult {
  final List<AcceleratedLoanProjection> projections;
  final int totalBaseInterestMinor;
  final int totalAcceleratedInterestMinor;
  final int totalBaseMonths;
  final int totalAcceleratedMonths;
  final int totalInterestSavedMinor;

  LoanForecastSimulationResult({
    required this.projections,
    required this.totalBaseInterestMinor,
    required this.totalAcceleratedInterestMinor,
    required this.totalBaseMonths,
    required this.totalAcceleratedMonths,
    required this.totalInterestSavedMinor,
  });
}

class _ActiveLoanSim {
  final Account loan;
  int balanceMinor;
  final double monthlyRate;
  final int baseEmiMinor;
  int totalInterestPaidMinor = 0;
  int monthsToPayoff = 0;
  bool isPaidOff = false;

  _ActiveLoanSim({
    required this.loan,
    required this.balanceMinor,
    required this.monthlyRate,
    required this.baseEmiMinor,
  });
}

LoanForecastSimulationResult simulateAcceleratedPayoff({
  required LedgerState state,
  required List<Account> loans,
  required int monthlyIncomeMinor,
  required int monthlyEmergencySavingMinor,
  required double extraPaymentAllocationPercent,
  required String priorityStrategy, // 'avalanche' or 'snowball'
}) {
  final activeSims = <_ActiveLoanSim>[];
  final baseProjections = <String, LoanProjection>{};

  int totalBaseInterestMinor = 0;
  int totalBaseMonths = 0;

  for (final loan in loans) {
    final projection = loanProjection(state, loan);
    baseProjections[loan.id] = projection;
    
    if (projection.monthsRemaining != null) {
      if (projection.monthsRemaining! > totalBaseMonths) {
        totalBaseMonths = projection.monthsRemaining!;
      }
    }
    totalBaseInterestMinor += projection.estimatedInterestMinor;

    final balanceMinor = accountBalance(state, loan).amountMinor.abs();
    final loanDetails = loan.loanDetails;
    final annualRate = loanDetails?.interestRatePercent ?? 0.0;
    
    activeSims.add(
      _ActiveLoanSim(
        loan: loan,
        balanceMinor: balanceMinor,
        monthlyRate: annualRate <= 0 ? 0 : annualRate / 100 / 12,
        baseEmiMinor: projection.monthlyEmi,
      ),
    );
  }

  int simulatedMonths = 0;
  
  while (activeSims.any((sim) => !sim.isPaidOff) && simulatedMonths < 1200) {
    simulatedMonths++;
    
    int totalBaseEmisDueThisMonth = 0;
    for (final sim in activeSims) {
      if (!sim.isPaidOff) {
        totalBaseEmisDueThisMonth += sim.baseEmiMinor;
      }
    }

    // Calculate free cash
    int freeCashMinor = monthlyIncomeMinor - monthlyEmergencySavingMinor - totalBaseEmisDueThisMonth;
    if (freeCashMinor < 0) freeCashMinor = 0;

    int extraPaymentAvailable = (freeCashMinor * extraPaymentAllocationPercent).round();

    // Sort active loans by priority
    final pendingLoans = activeSims.where((sim) => !sim.isPaidOff).toList();
    pendingLoans.sort((a, b) {
      if (priorityStrategy == 'avalanche') {
        // Highest rate first
        final rateDiff = b.monthlyRate.compareTo(a.monthlyRate);
        if (rateDiff != 0) return rateDiff;
        // Tie-breaker: lowest balance
        return a.balanceMinor.compareTo(b.balanceMinor);
      } else {
        // Snowball: lowest balance first
        return a.balanceMinor.compareTo(b.balanceMinor);
      }
    });

    // Step 1: Accrue interest and pay base EMIs
    for (final sim in pendingLoans) {
      final interestThisMonth = (sim.balanceMinor * sim.monthlyRate).round();
      sim.totalInterestPaidMinor += interestThisMonth;
      
      // Pay base EMI
      final principalPortion = sim.baseEmiMinor - interestThisMonth;
      if (principalPortion > 0) {
        sim.balanceMinor -= principalPortion;
      }
    }

    // Step 2: Apply extra payments to the highest priority loan
    for (final sim in pendingLoans) {
      if (extraPaymentAvailable <= 0) break;
      if (sim.balanceMinor <= 0) continue;

      final payment = math.min(extraPaymentAvailable, sim.balanceMinor);
      sim.balanceMinor -= payment;
      extraPaymentAvailable -= payment;
    }

    // Check payoff
    for (final sim in pendingLoans) {
      if (sim.balanceMinor <= 0) {
        sim.isPaidOff = true;
        sim.monthsToPayoff = simulatedMonths;
      }
    }
  }

  // Handle loans that might not be paid off due to max iterations
  for (final sim in activeSims) {
    if (!sim.isPaidOff) sim.monthsToPayoff = simulatedMonths;
  }

  int totalAcceleratedInterestMinor = 0;
  int totalAcceleratedMonths = 0;
  final projections = <AcceleratedLoanProjection>[];

  for (final sim in activeSims) {
    totalAcceleratedInterestMinor += sim.totalInterestPaidMinor;
    if (sim.monthsToPayoff > totalAcceleratedMonths) {
      totalAcceleratedMonths = sim.monthsToPayoff;
    }
    
    final baseProj = baseProjections[sim.loan.id]!;
    
    projections.add(AcceleratedLoanProjection(
      loan: sim.loan,
      baseEmiMinor: sim.baseEmiMinor,
      baseMonthsRemaining: baseProj.monthsRemaining ?? 0,
      baseInterestMinor: baseProj.estimatedInterestMinor,
      acceleratedMonthsRemaining: sim.monthsToPayoff,
      acceleratedInterestMinor: sim.totalInterestPaidMinor,
    ));
  }

  return LoanForecastSimulationResult(
    projections: projections,
    totalBaseInterestMinor: totalBaseInterestMinor,
    totalAcceleratedInterestMinor: totalAcceleratedInterestMinor,
    totalBaseMonths: totalBaseMonths,
    totalAcceleratedMonths: totalAcceleratedMonths,
    totalInterestSavedMinor: totalBaseInterestMinor - totalAcceleratedInterestMinor,
  );
}
