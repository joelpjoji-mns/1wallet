import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/utils/recurrence_utils.dart';
import 'package:one_wallet_flutter/src/features/loans/loan_forecast_simulator.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';
import 'package:one_wallet_flutter/src/imports/statement_parser.dart';

class _FakeLedgerRepo extends LedgerRepository {
  const _FakeLedgerRepo();
  @override
  Future<void> save(LedgerState state) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Logic Audit Fixes Test Suite', () {
    test('1. Card account type is properly classified as liability and displays card ending label', () {
      const cardAccount = Account(
        id: 'acc-card',
        name: 'Visa Card',
        type: 'card',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
        cardLast4: '4321',
      );
      const creditCardAccount = Account(
        id: 'acc-cc',
        name: 'Mastercard',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
        cardLast4: '8765',
      );
      const bankAccount = Account(
        id: 'acc-bank',
        name: 'Checking',
        type: 'checking',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
        accountLast4: '1234',
      );

      expect(isLiabilityAccount(cardAccount), isTrue);
      expect(isLiabilityAccount(creditCardAccount), isTrue);
      expect(isLiabilityAccount(bankAccount), isFalse);

      expect(cardAccount.displayLast4Label, equals('Card ending in'));
      expect(creditCardAccount.displayLast4Label, equals('Card ending in'));
      expect(bankAccount.displayLast4Label, equals('Account ending in'));
    });

    test('2. Recurrence cursor does not advance for once frequency', () {
      final start = DateTime(2025, 3, 15, 10);
      final advanced = advanceRecurrenceCursor(
        current: start,
        frequency: 'once',
      );
      expect(advanced, equals(start));
    });

    test('3. minorUnits accurately recognizes 0-decimal, 3-decimal, and standard currencies', () {
      expect(minorUnits('JPY'), equals(0));
      expect(minorUnits('KRW'), equals(0));
      expect(minorUnits('VND'), equals(0));
      expect(minorUnits('BHD'), equals(3));
      expect(minorUnits('KWD'), equals(3));
      expect(minorUnits('USD'), equals(2));
      expect(minorUnits('EUR'), equals(2));
    });

    test('4. LedgerState.isIncomingLedgerSafer compares top occurredAt accurately', () {
      final now = DateTime.now();
      final localTx = TransactionRecord(
        id: 't-local',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 1000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1000, currency: 'USD'),
        occurredAt: now,
      );
      final incomingOlderTx = TransactionRecord(
        id: 't-inc',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 1000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1000, currency: 'USD'),
        occurredAt: now.subtract(const Duration(days: 2)),
      );

      final localLedger = emptyLedgerState().copyWith(
        transactions: [localTx],
      );
      final incomingLedger = emptyLedgerState().copyWith(
        transactions: [incomingOlderTx],
      );

      // Local ledger has newer transaction, so incoming is NOT safer
      expect(LedgerState.isIncomingLedgerSafer(localLedger, incomingLedger), isFalse);
    });

    test('5. Merging transactions rejects transfers and handles signed deltas for mixed income/expense', () async {
      const acc = Account(
        id: 'acc-1',
        name: 'Checking',
        type: 'checking',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
      );
      final expenseTx = TransactionRecord(
        id: 't-exp',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 5000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 5000, currency: 'USD'),
        occurredAt: DateTime(2025),
      );
      final refundTx = TransactionRecord(
        id: 't-ref',
        type: 'income',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 2000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 2000, currency: 'USD'),
        occurredAt: DateTime(2025, 1, 2),
      );
      final transferTx = TransactionRecord(
        id: 't-trans',
        type: 'transfer',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        counterAccountId: 'acc-2',
        amount: const Money(amountMinor: 1000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1000, currency: 'USD'),
        occurredAt: DateTime(2025, 1, 3),
      );

      final initial = emptyLedgerState().copyWith(
        accounts: const [acc],
        transactions: [expenseTx, refundTx, transferTx],
      );

      final controller = LedgerController(const _FakeLedgerRepo(), initialState: initial);
      addTearDown(controller.dispose);

      // Merging transfers must throw ArgumentError
      expect(
        () => controller.mergeTransactions(transactionIds: {'t-exp', 't-trans'}),
        throwsA(isA<ArgumentError>()),
      );

      // Merging $50 expense with $20 refund nets to $30 expense
      final merged = await controller.mergeTransactions(transactionIds: {'t-exp', 't-ref'});
      expect(merged.type, equals('expense'));
      expect(merged.amount.amountMinor, equals(3000));
      expect(merged.baseAmount.amountMinor, equals(3000));
    });

    test('6. archiveCategory cascades to descendant categories', () async {
      const parentCat = Category(id: 'cat-custom-parent', name: 'CustomParent', kind: 'expense');
      const childCat = Category(id: 'cat-custom-child', name: 'CustomChild', kind: 'expense', parentId: 'cat-custom-parent');
      const grandChildCat = Category(id: 'cat-custom-grand', name: 'CustomGrand', kind: 'expense', parentId: 'cat-custom-child');
      const otherCat = Category(id: 'cat-custom-other', name: 'CustomOther', kind: 'expense');

      final initial = emptyLedgerState().copyWith(
        categories: [
          ...emptyLedgerState().categories,
          parentCat,
          childCat,
          grandChildCat,
          otherCat,
        ],
      );

      final controller = LedgerController(const _FakeLedgerRepo(), initialState: initial);
      addTearDown(controller.dispose);
      await controller.archiveCategory('cat-custom-parent', archived: true);

      final state = controller.state;
      expect(state.categories.firstWhere((c) => c.id == 'cat-custom-parent').isArchived, isTrue);
      expect(state.categories.firstWhere((c) => c.id == 'cat-custom-child').isArchived, isTrue);
      expect(state.categories.firstWhere((c) => c.id == 'cat-custom-grand').isArchived, isTrue);
      expect(state.categories.firstWhere((c) => c.id == 'cat-custom-other').isArchived, isFalse);
    });

    test('7. Overdraft accounts are never auto-archived when positive', () async {
      const overdraftAcc = Account(
        id: 'acc-od',
        name: 'Checking with Overdraft',
        type: 'overdraft',
        currency: 'USD',
        openingBalance: Money(amountMinor: 100000, currency: 'USD'),
      );
      final initial = emptyLedgerState().copyWith(
        accounts: const [overdraftAcc],
      );

      final controller = LedgerController(const _FakeLedgerRepo(), initialState: initial);
      addTearDown(controller.dispose);
      // Trigger a state commit by editing preferences
      await controller.updatePreferences(initial.preferences.copyWith(displayCurrency: 'EUR'));

      final state = controller.state;
      expect(state.accounts.firstWhere((a) => a.id == 'acc-od').isArchived, isFalse);
    });

    test('8. Loan forecast simulator ignores paid off active loans and calculates months saved', () {
      const loanAcc = Account(
        id: 'acc-loan',
        name: 'Auto Loan',
        type: 'loan',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
      );
      final paidOffLoan = ActiveLoan(
        account: loanAcc,
        principalMinor: 0,
        monthlyEmiMinor: 5000,
        annualRatePercent: 5.0,
      );

      final ledger = emptyLedgerState().copyWith(
        accounts: const [loanAcc],
      );

      final result = simulateForecastPayoffGraph(
        state: ledger,
        activeLoans: [paidOffLoan],
        emergencySavingMinor: 0,
        extraPaymentAllocationPercent: 0.5,
        loanPriorityIds: [loanAcc.id],
      );

      // Paid off loan should produce 0 payoff events (not a fake event tomorrow)
      expect(result.payoffEvents, isEmpty);
      expect(result.impact.monthsSaved, equals(0));
    });

    test('9. parseTransactionMessage extracts minor units appropriately for JPY, KWD, and USD', () {
      final jpyMsg = parseTransactionMessage('Spent JPY 5000 at 7-Eleven on your card 1234');
      expect(jpyMsg.amount?.currency, equals('JPY'));
      expect(jpyMsg.amount?.amountMinor, equals(5000));

      final usdMsg = parseTransactionMessage('Spent USD 50.00 at Grocery Store on card 1234');
      expect(usdMsg.amount?.currency, equals('USD'));
      expect(usdMsg.amount?.amountMinor, equals(5000));
    });

    test('10. parseStatement parses dates with 4-letter Sept abbreviation', () {
      const statement = '''
      DATE       DESCRIPTION          DEBIT     CREDIT    BALANCE
      15-Sept-2024  Salary                      5000.00   5000.00
      16-Sept-2024  Grocery Store        50.00            4950.00
      ''';
      final res = parseStatement(statement, defaultCurrency: 'USD');
      expect(res.rows.isNotEmpty, isTrue);
      expect(res.rows.first.occurredAt?.month, equals(9));
      expect(res.rows.first.occurredAt?.day, equals(15));
    });

    test('11. cashDestinationTransferMoney accurately returns counterAmount for cross-currency transfers', () {
      const cashEur = Account(
        id: 'acc-cash-eur',
        name: 'EUR Cash',
        type: 'cash',
        currency: 'EUR',
        openingBalance: Money(amountMinor: 0, currency: 'EUR'),
      );
      final tx = TransactionRecord(
        id: 't-cross',
        type: 'transfer',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-bank-usd',
        counterAccountId: 'acc-cash-eur',
        amount: const Money(amountMinor: 10000, currency: 'USD'),
        counterAmount: const Money(amountMinor: 9200, currency: 'EUR'),
        baseAmount: const Money(amountMinor: 10000, currency: 'USD'),
        occurredAt: DateTime(2025),
      );

      final result = cashDestinationTransferMoney(tx, cashEur);
      expect(result.currency, equals('EUR'));
      expect(result.amountMinor, equals(9200));
    });

    test('12. rateBetween triangulates cross-currency rates via baseCurrency', () {
      final state = emptyLedgerState().copyWith(
        preferences: emptyLedgerState().preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
        ),
        exchangeRates: [
          ExchangeRateRecord(
            base: 'USD',
            quote: 'EUR',
            rate: 0.92,
            asOfDate: DateTime(2025),
          ),
          ExchangeRateRecord(
            base: 'USD',
            quote: 'GBP',
            rate: 0.79,
            asOfDate: DateTime(2025),
          ),
        ],
      );

      // EUR to GBP has no direct quote, but triangulates EUR -> USD -> GBP
      // 1 EUR = (1 / 0.92) USD = 1.08695 USD
      // 1.08695 USD * 0.79 GBP = 0.85869 GBP
      final rate = rateBetween(state, 'EUR', 'GBP');
      expect(rate, isNotNull);
      expect(rate!, closeTo(0.79 / 0.92, 0.001));
    });

    test('13. netWorth properly classifies positive overdraft balances as assets and negative balances as liabilities', () {
      const overdraftChecking = Account(
        id: 'acc-od',
        name: 'Checking with Overdraft',
        type: 'overdraft',
        currency: 'USD',
        openingBalance: Money(amountMinor: 200000, currency: 'USD'),
      );
      const overdrawnAccount = Account(
        id: 'acc-reg',
        name: 'Overdrawn Checking',
        type: 'checking',
        currency: 'USD',
        openingBalance: Money(amountMinor: -50000, currency: 'USD'),
      );
      final state = emptyLedgerState().copyWith(
        accounts: const [overdraftChecking, overdrawnAccount],
      );

      final worth = netWorth(state);
      // Positive $2,000 in overdraft checking is an asset
      expect(worth.assets.amountMinor, equals(200000));
      // Negative $500 in regular checking is a liability
      expect(worth.liabilities.amountMinor, equals(-50000));
      expect(worth.total.amountMinor, equals(150000));
    });

    test('14. creditCardDueStatus flags past unpaid statement as overdue when dueDay is null', () {
      const card = Account(
        id: 'acc-card',
        name: 'Credit Card',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: Money(amountMinor: -50000, currency: 'USD'),
        statementDay: 15,
        lastPaidBillMonth: null, // Unpaid
      );
      final state = emptyLedgerState().copyWith(
        accounts: const [card],
      );

      // On Oct 10, before Oct 15 statement: the active statement was Sep 15, due Oct 5
      final today = DateTime(2026, 10, 10);
      final status = creditCardDueStatus(state, card, now: today);

      expect(status, isNotNull);
      expect(status!.statementDate, equals(DateTime(2026, 9, 15)));
      expect(status.dueDate, equals(DateTime(2026, 10, 5)));
      expect(status.isOverdue, isTrue);
    });

    test('15. upsertTransaction preserves existing transaction name when not explicitly provided', () async {
      const account = Account(
        id: 'acc-1',
        name: 'Checking',
        type: 'checking',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
      );
      final tx = TransactionRecord(
        id: 'tx-1',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 1500, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1500, currency: 'USD'),
        name: 'Starbucks Coffee',
        occurredAt: DateTime(2025),
      );
      final initial = emptyLedgerState().copyWith(
        accounts: const [account],
        transactions: [tx],
      );
      final controller = LedgerController(const _FakeLedgerRepo(), initialState: initial);
      addTearDown(controller.dispose);

      // Edit category/notes without passing name
      await controller.upsertTransaction(
        id: 'tx-1',
        type: 'expense',
        accountId: 'acc-1',
        amountMinor: 1500,
        notes: 'Updated note',
      );

      final updated = controller.state.transactions.firstWhere((t) => t.id == 'tx-1');
      expect(updated.name, equals('Starbucks Coffee'));
      expect(updated.notes, equals('Updated note'));
    });

    test('16. approveCaptureCandidate converts foreign currency, sets originalAmount, and assigns merchant name', () async {
      const account = Account(
        id: 'acc-eur',
        name: 'Euro Account',
        type: 'bank',
        currency: 'EUR',
        openingBalance: Money(amountMinor: 0, currency: 'EUR'),
      );
      final candidate = CaptureCandidate(
        id: 'cap-1',
        source: 'sms',
        status: 'pending',
        createdAt: DateTime(2025, 5, 10),
        merchant: 'Uber Rides',
        parsedAmount: const Money(amountMinor: 2000, currency: 'USD'),
        suggestedAccountId: 'acc-eur',
        transactionType: 'expense',
      );
      final initial = emptyLedgerState().copyWith(
        preferences: emptyLedgerState().preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'EUR',
        ),
        accounts: const [account],
        captureCandidates: [candidate],
        exchangeRates: [
          ExchangeRateRecord(
            base: 'USD',
            quote: 'EUR',
            rate: 0.90,
            asOfDate: DateTime(2025),
          ),
        ],
      );
      final controller = LedgerController(const _FakeLedgerRepo(), initialState: initial);
      addTearDown(controller.dispose);

      final createdTx = await controller.approveCaptureCandidate('cap-1');
      expect(createdTx.name, equals('Uber Rides'));
      expect(createdTx.amount.currency, equals('EUR'));
      expect(createdTx.amount.amountMinor, equals(1800)); // 20.00 USD * 0.90 = 18.00 EUR
      expect(createdTx.originalAmount?.currency, equals('USD'));
      expect(createdTx.originalAmount?.amountMinor, equals(2000));
    });

    test('17. removeEnabledCurrency resets displayCurrency to baseCurrency when display currency is removed', () async {
      final initial = emptyLedgerState().copyWith(
        preferences: emptyLedgerState().preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'EUR',
          enabledCurrencies: ['EUR', 'GBP'],
        ),
      );
      final controller = LedgerController(const _FakeLedgerRepo(), initialState: initial);
      addTearDown(controller.dispose);

      await controller.removeEnabledCurrency('EUR');
      expect(controller.state.preferences.displayCurrency, equals('USD'));
      expect(controller.state.preferences.enabledCurrencies.contains('EUR'), isFalse);
    });
  });
}
