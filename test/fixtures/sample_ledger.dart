import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';

LedgerState sampleLedgerState() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10, 30);

  Money inr(int minor) => Money(amountMinor: minor, currency: 'INR');

  final accounts = [
    Account(
      id: 'acc-bank',
      name: 'HDFC Main',
      type: 'bank',
      currency: 'INR',
      openingBalance: inr(12456000),
      institution: 'HDFC Bank',
      groupName: 'Banking',
      color: AppColors.primary,
      sortOrder: 1,
    ),
    Account(
      id: 'acc-cash',
      name: 'Cash Wallet',
      type: 'cash',
      currency: 'INR',
      openingBalance: inr(185000),
      groupName: 'Daily',
      color: AppColors.tertiary,
      sortOrder: 2,
    ),
    Account(
      id: 'acc-card',
      name: 'Axis Credit Card',
      type: 'credit_card',
      currency: 'INR',
      openingBalance: inr(-284900),
      institution: 'Axis Bank',
      groupName: 'Cards',
      color: AppColors.warning,
      sortOrder: 3,
    ),
    Account(
      id: 'acc-loan',
      name: 'Home Loan',
      type: 'loan',
      currency: 'INR',
      openingBalance: inr(-245000000),
      institution: 'SBI',
      groupName: 'Debt',
      loanDetails: AccountLoanDetails(
        loanKind: 'loan',
        principal: inr(245000000),
        repaymentAmount: inr(4650000),
        interestRatePercent: 8.4,
        repaymentCount: 72,
        repaymentStartsOn: today.add(const Duration(days: 11)),
        repaymentSourceAccountId: 'acc-bank',
      ),
      color: AppColors.dangerLight,
      showOnHome: false,
      includeInTotals: false,
      sortOrder: 4,
    ),
  ];

  final categories = defaultCategories();

  TransactionRecord tx({
    required String id,
    required String type,
    required String accountId,
    required int amountMinor,
    required int daysAgo,
    String status = 'cleared',
    String source = 'manual',
    String? categoryId,
    String? counterAccountId,
    String? notes,
    String? paymentMethod,
  }) {
    return TransactionRecord(
      id: id,
      type: type,
      status: status,
      source: source,
      accountId: accountId,
      counterAccountId: counterAccountId,
      amount: inr(amountMinor),
      baseAmount: inr(amountMinor),
      categoryId: categoryId,
      occurredAt: today.subtract(Duration(days: daysAgo)),
      notes: notes,
      paymentMethod: paymentMethod,
    );
  }

  final transactions = [
    tx(
      id: 'tx-salary',
      type: 'income',
      accountId: 'acc-bank',
      amountMinor: 18500000,
      daysAgo: 2,
      categoryId: 'cat-salary',
      notes: 'Monthly salary',
      paymentMethod: 'NEFT',
    ),
    tx(
      id: 'tx-grocery',
      type: 'expense',
      accountId: 'acc-card',
      amountMinor: 642500,
      daysAgo: 1,
      categoryId: 'cat-grocery',
      notes: 'Big Basket',
      paymentMethod: 'Credit card',
    ),
    tx(
      id: 'tx-food',
      type: 'expense',
      accountId: 'acc-cash',
      amountMinor: 89000,
      daysAgo: 0,
      categoryId: 'cat-food',
      notes: 'Lunch',
      paymentMethod: 'Cash',
    ),
    tx(
      id: 'tx-ride',
      type: 'expense',
      accountId: 'acc-bank',
      amountMinor: 42000,
      daysAgo: 3,
      categoryId: 'cat-travel',
      notes: 'Metro recharge',
      paymentMethod: 'UPI',
    ),
    tx(
      id: 'tx-power',
      type: 'expense',
      accountId: 'acc-bank',
      amountMinor: 328000,
      daysAgo: 5,
      categoryId: 'cat-bills',
      notes: 'Electricity bill',
      paymentMethod: 'Auto debit',
    ),
    tx(
      id: 'tx-card-payment',
      type: 'card_payment',
      accountId: 'acc-bank',
      counterAccountId: 'acc-card',
      amountMinor: 1200000,
      daysAgo: 7,
      categoryId: 'cat-bills',
      notes: 'Credit card payment',
    ),
    tx(
      id: 'tx-emi',
      type: 'loan_repayment',
      accountId: 'acc-bank',
      counterAccountId: 'acc-loan',
      amountMinor: 4650000,
      daysAgo: 9,
      categoryId: 'cat-emi',
      notes: 'Home loan EMI',
    ),
    tx(
      id: 'tx-rent-planned',
      type: 'expense',
      status: 'scheduled',
      accountId: 'acc-bank',
      amountMinor: 3200000,
      daysAgo: -4,
      categoryId: 'cat-bills',
      notes: 'Rent',
      paymentMethod: 'Standing instruction',
    ),
    tx(
      id: 'tx-emi-planned',
      type: 'loan_repayment',
      status: 'scheduled',
      accountId: 'acc-bank',
      counterAccountId: 'acc-loan',
      amountMinor: 4650000,
      daysAgo: -11,
      categoryId: 'cat-emi',
      notes: 'Upcoming EMI',
    ),
  ];

  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'local-user',
    preferences: const LedgerPreferences(),
    accounts: accounts,
    categories: categories,
    transactions: transactions,
    budgets: [
      Budget(
        id: 'budget-food',
        name: 'Food & groceries',
        amount: inr(1800000),
        spent: inr(731500),
      ),
      Budget(
        id: 'budget-bills',
        name: 'Bills',
        amount: inr(7000000),
        spent: inr(328000),
      ),
    ],
    goals: [
      Goal(
        id: 'goal-emergency',
        name: 'Emergency fund',
        target: inr(30000000),
        saved: inr(8700000),
      ),
      Goal(
        id: 'goal-trip',
        name: 'Japan trip',
        target: inr(18000000),
        saved: inr(4200000),
      ),
    ],
    captureCandidates: [
      CaptureCandidate(
        id: 'cap-1',
        source: 'sms',
        status: 'pending',
        createdAt: today,
      ),
      CaptureCandidate(
        id: 'cap-2',
        source: 'notification',
        status: 'pending',
        createdAt: today.subtract(const Duration(hours: 2)),
      ),
    ],
  );
}
