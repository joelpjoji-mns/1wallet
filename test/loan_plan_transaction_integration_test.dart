import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/loans/loans_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_widgets.dart';
import 'package:one_wallet_flutter/src/features/transactions/transaction_row.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseDate = DateTime(2026, 6, 1);

  Account makeBank({int balance = 500000}) {
    return Account(
      id: 'acc-bank',
      name: 'Checking Bank',
      type: 'bank',
      currency: 'USD',
      openingBalance: Money(amountMinor: balance, currency: 'USD'),
    );
  }

  Account makeLoan({
    int principal = 100000,
    int balance = -100000,
    int emi = 50000,
    int tenure = 2,
  }) {
    return Account(
      id: 'acc-loan',
      name: 'Auto Loan',
      type: 'loan',
      currency: 'USD',
      openingBalance: Money(amountMinor: balance, currency: 'USD'),
      loanDetails: AccountLoanDetails(
        loanKind: 'loan',
        principal: Money(amountMinor: principal, currency: 'USD'),
        repaymentAmount: Money(amountMinor: emi, currency: 'USD'),
        repaymentCount: tenure,
        recurrenceLimit: tenure,
        repaymentStartsOn: baseDate,
        repaymentSourceAccountId: 'acc-bank',
        recurrenceFrequency: 'monthly',
        recurrenceInterval: 1,
      ),
    );
  }

  TransactionRecord makeEmiPlan({
    int emi = 50000,
    int tenure = 2,
    DateTime? date,
  }) {
    final amt = Money(amountMinor: emi, currency: 'USD');
    return TransactionRecord(
      id: 'plan-loan-emi',
      type: 'loan_repayment',
      accountId: 'acc-bank',
      counterAccountId: 'acc-loan',
      amount: amt,
      baseAmount: amt,
      status: 'scheduled',
      source: 'recurring',
      categoryId: 'cat-emi',
      recurrenceFrequency: 'monthly',
      recurrenceInterval: 1,
      recurrenceLimit: tenure,
      occurredAt: date ?? baseDate,
      notes: 'Scheduled EMI for Auto Loan',
    );
  }

  Category makeCategory() {
    return const Category(
      id: 'cat-emi',
      name: 'EMI & Loans',
      kind: 'expense',
      color: Color(0xFF2196F3),
    );
  }

  group('Loan, Plan & Transaction Integration', () {
    test('Loan EMI plan reduces loan liability and advances or finishes plan', () async {
      final bank = makeBank(balance: 500000);
      final loan = makeLoan(principal: 100000, balance: -100000, emi: 50000, tenure: 2);
      final plan = makeEmiPlan(emi: 50000, tenure: 2);
      final category = makeCategory();

      final initialLedger = emptyLedgerState().copyWith(
        accounts: [bank, loan],
        transactions: [plan],
        categories: [category],
      );

      final container = ProviderContainer(
        overrides: [
          ledgerProvider.overrideWith(
            (ref) => LedgerController(
              StaticLedgerRepository(initialLedger),
              initialState: initialLedger,
            ),
          ),
        ],
      );

      // Verify initial state
      var state = container.read(ledgerProvider);
      expect(accountBalance(state, bank).amountMinor, 500000);
      expect(accountBalance(state, loan).amountMinor, -100000);
      expect(isPastLoan(state, loan), isFalse);

      final scheduledEmi = existingLoanEmi(state, loan.id);
      expect(scheduledEmi, isNotNull);
      expect(scheduledEmi!.id, plan.id);
      expect(scheduledEmi.recurrenceLimit, 2);

      // Post first payment of 50000
      await container.read(ledgerProvider.notifier).upsertTransaction(
        type: 'loan_repayment',
        accountId: bank.id,
        counterAccountId: loan.id,
        amountMinor: 50000,
        categoryId: 'cat-emi',
        status: 'cleared',
        originalTransactionId: plan.id,
        occurredAt: baseDate,
      );

      // Advance scheduled transaction
      await container.read(ledgerProvider.notifier).updateTransactionStatus(
        plan.id,
        'scheduled',
        occurredAt: DateTime(2026, 7, 1),
      );

      state = container.read(ledgerProvider);
      // Bank balance reduced by 50,000 -> 450,000
      expect(accountBalance(state, bank).amountMinor, 450000);
      // Loan liability reduced by 50,000 -> -50,000
      expect(accountBalance(state, loan).amountMinor, -50000);
      expect(isPastLoan(state, loan), isFalse);

      // Post second payment of 50000 (pays off loan)
      await container.read(ledgerProvider.notifier).upsertTransaction(
        type: 'loan_repayment',
        accountId: bank.id,
        counterAccountId: loan.id,
        amountMinor: 50000,
        categoryId: 'cat-emi',
        status: 'cleared',
        originalTransactionId: plan.id,
        occurredAt: DateTime(2026, 7, 1),
      );

      // Plan should now finish because loan is paid off and limit reached
      await container.read(ledgerProvider.notifier).updateTransactionStatus(
        plan.id,
        'finished',
      );

      state = container.read(ledgerProvider);
      expect(accountBalance(state, bank).amountMinor, 400000);
      expect(accountBalance(state, loan).amountMinor, 0);
      expect(isPastLoan(state, loan), isTrue);

      // No scheduled EMI remains
      expect(existingLoanEmi(state, loan.id), isNull);
    });

    testWidgets('AddRecordSelectorGrid shows Loan account for loan_repayment', (tester) async {
      final bank = makeBank();
      final loan = makeLoan();
      final state = emptyLedgerState().copyWith(accounts: [bank, loan]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddRecordSelectorGrid(
              state: state,
              sourceAccount: bank,
              counterAccount: loan,
              category: null,
              type: 'loan_repayment',
              onSelectAccount: () {},
              onSelectCounter: () {},
              onSelectCategory: () {},
            ),
          ),
        ),
      );

      expect(find.text('Loan account'), findsOneWidget);
      expect(find.text('Auto Loan'), findsOneWidget);
      expect(find.text('Category'), findsNothing);
    });

    testWidgets('AddRecordTypeTabs includes Loan tab when value is loan_repayment', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddRecordTypeTabs(
              value: 'loan_repayment',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Loan'), findsOneWidget);
    });

    testWidgets('TransactionRow displays source -> loan for loan_repayment', (tester) async {
      final bank = makeBank();
      final loan = makeLoan();
      final category = makeCategory();
      const amt = Money(amountMinor: 50000, currency: 'USD');
      final tx = TransactionRecord(
        id: 'tx-loan-1',
        type: 'loan_repayment',
        accountId: bank.id,
        counterAccountId: loan.id,
        amount: amt,
        baseAmount: amt,
        status: 'cleared',
        source: 'manual',
        categoryId: category.id,
        occurredAt: baseDate,
      );

      final state = emptyLedgerState().copyWith(
        accounts: [bank, loan],
        transactions: [tx],
        categories: [category],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerProvider.overrideWith(
              (ref) => LedgerController(
                StaticLedgerRepository(state),
                initialState: state,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: TransactionRow(
                  state: state,
                  transaction: tx,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Checking Bank → Auto Loan'), findsOneWidget);
      expect(find.text('Repayment to Auto Loan'), findsOneWidget);
    });

    testWidgets('LoanDetailView renders Pay EMI and Custom Repayment buttons when EMI scheduled', (tester) async {
      final bank = makeBank();
      final loan = makeLoan(principal: 100000, balance: -100000, emi: 50000, tenure: 2);
      final plan = makeEmiPlan(emi: 50000, tenure: 2);
      final category = makeCategory();

      final state = emptyLedgerState().copyWith(
        accounts: [bank, loan],
        transactions: [plan],
        categories: [category],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerProvider.overrideWith(
              (ref) => LedgerController(
                StaticLedgerRepository(state),
                initialState: state,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LoanDetailView(loan: loan),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Pay EMI'), findsOneWidget);
      expect(find.text('Custom repayment'), findsOneWidget);
      expect(find.text('View plan'), findsOneWidget);
    });

    testWidgets('LoanDetailView renders Record repayment when no EMI is scheduled', (tester) async {
      final bank = makeBank();
      final loan = Account(
        id: 'acc-loan-no-emi',
        name: 'Personal Loan',
        type: 'loan',
        currency: 'USD',
        openingBalance: const Money(amountMinor: -50000, currency: 'USD'),
      );
      final category = makeCategory();

      final state = emptyLedgerState().copyWith(
        accounts: [bank, loan],
        transactions: const [],
        categories: [category],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerProvider.overrideWith(
              (ref) => LedgerController(
                StaticLedgerRepository(state),
                initialState: state,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LoanDetailView(loan: loan),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Record repayment'), findsOneWidget);
      expect(find.text('Not scheduled'), findsOneWidget);
    });
  });
}
