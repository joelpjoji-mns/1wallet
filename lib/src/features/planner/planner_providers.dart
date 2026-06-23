import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../ledger/ledger_selectors.dart';

class BudgetHealthData {
  final int totalIncome;
  final int totalNeeds;
  final int totalWants;
  final List<TransactionRecord> needsRecords;
  final List<TransactionRecord> wantsRecords;
  
  const BudgetHealthData({
    required this.totalIncome,
    required this.totalNeeds,
    required this.totalWants,
    required this.needsRecords,
    required this.wantsRecords,
  });
}

final budgetHealthProvider = Provider<BudgetHealthData>((ref) {
  final state = ref.watch(ledgerProvider);
  final now = DateTime.now();
  int totalIncome = 0;
  int totalNeeds = 0;
  int totalWants = 0;
  final needsRecords = <TransactionRecord>[];
  final wantsRecords = <TransactionRecord>[];
  
  for (final tx in state.transactions) {
    if (tx.status == 'void' || tx.status == 'scheduled' || tx.status == 'paused') continue;
    if (tx.occurredAt.year == now.year && tx.occurredAt.month == now.month) {
      if (incomeTypes.contains(tx.type)) {
        totalIncome += convertMoneyForDisplay(state, tx.amount, state.preferences.displayCurrency).amountMinor;
      }
      if (expenseTypes.contains(tx.type)) {
        final catName = tx.categoryId != null ? categoryById(state, tx.categoryId!)?.name.toLowerCase() ?? '' : '';
        final needsKeywords = ['grocer', 'bill', 'rent', 'utilit', 'mortgage', 'insur', 'medic', 'tax', 'debt', 'emi', 'loan', 'educat'];
        final isNeed = needsKeywords.any((k) => catName.contains(k));

        final amt = convertMoneyForDisplay(state, tx.amount, state.preferences.displayCurrency).amountMinor;
        if (isNeed) {
          totalNeeds += amt;
          needsRecords.add(tx);
        } else {
          totalWants += amt;
          wantsRecords.add(tx);
        }
      }
    }
  }
  return BudgetHealthData(
    totalIncome: totalIncome,
    totalNeeds: totalNeeds,
    totalWants: totalWants,
    needsRecords: needsRecords,
    wantsRecords: wantsRecords,
  );
});

class EmergencyFundData {
  final int totalCash;
  final int target;
  
  const EmergencyFundData({
    required this.totalCash,
    required this.target,
  });
}

final emergencyFundProvider = Provider<EmergencyFundData>((ref) {
  final state = ref.watch(ledgerProvider);
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 90));
  int totalExp = 0;
  for (final tx in state.transactions) {
    if (tx.status == 'void' || tx.status == 'scheduled') continue;
    if (expenseTypes.contains(tx.type) && tx.occurredAt.isAfter(start)) {
      totalExp += convertMoneyForDisplay(state, tx.amount, state.preferences.displayCurrency).amountMinor;
    }
  }
  final avgMonthlyExp = totalExp ~/ 3;
  final target = avgMonthlyExp * 3;

  int totalCash = 0;
  final balances = accountBalanceMap(state);
  for (final acc in state.accounts) {
    if (acc.type == 'emergency' || acc.name.toLowerCase().contains('emergency')) {
      totalCash += convertMoneyForDisplay(state, accountBalanceFromMap(balances, acc), state.preferences.displayCurrency).amountMinor;
    }
  }
  return EmergencyFundData(totalCash: totalCash, target: target);
});
