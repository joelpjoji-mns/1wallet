import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/capture/capture_pipeline.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/review_queue_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

Future<void> _pumpBounded(
  WidgetTester tester, {
  int times = 5,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CaptureCandidate Codec with Transfer fields', () {
    test('serializes and deserializes transfer fields correctly', () {
      final now = DateTime.now();
      final candidate = CaptureCandidate(
        id: 'cap-transfer-1',
        source: 'sms',
        status: 'pending',
        createdAt: now,
        rawText: 'Debited INR 5,000.00 from A/C 1234',
        parsedAmount: const Money(amountMinor: 500000, currency: 'INR'),
        merchant: 'Transfer to Savings',
        transactionType: 'transfer',
        suggestedAccountId: 'acc-checking',
        suggestedCounterAccountId: 'acc-savings',
        pairedCandidateId: 'cap-transfer-2',
      );

      final json = captureCandidateToJson(candidate);
      expect(json['suggestedCounterAccountId'], 'acc-savings');
      expect(json['pairedCandidateId'], 'cap-transfer-2');
      expect(json['transactionType'], 'transfer');

      final decoded = captureCandidateFromJson(json);
      expect(decoded.id, 'cap-transfer-1');
      expect(decoded.suggestedCounterAccountId, 'acc-savings');
      expect(decoded.pairedCandidateId, 'cap-transfer-2');
      expect(decoded.transactionType, 'transfer');
    });
  });

  group('Transfer Capture Pipeline', () {
    test(
      'debit in account A and credit in account B with same amount are both queued and can be linked as transfer',
      () async {
        final seedState = emptyLedgerState().copyWith(
          accounts: [
            const Account(
              id: 'acc-checking',
              name: 'Checking',
              type: 'bank',
              currency: 'INR',
              accountLast4: '1234',
              openingBalance: Money(amountMinor: 1000000, currency: 'INR'),
            ),
            const Account(
              id: 'acc-savings',
              name: 'Savings',
              type: 'bank',
              currency: 'INR',
              accountLast4: '5678',
              openingBalance: Money(amountMinor: 500000, currency: 'INR'),
            ),
          ],
          preferences: const LedgerPreferences(
            baseCurrency: 'INR',
            displayCurrency: 'INR',
            enabledCurrencies: ['INR'],
          ),
        );

        final controller = LedgerController(
          StaticLedgerRepository(seedState),
          setLoadState: (_) {},
          initialState: seedState,
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        final now = DateTime.now();

        // 1. Ingest debit SMS for Checking account
        final debitResult = await controller.importSmsMessageDetailed(
          'Alert: INR 5000.00 debited from A/C ending 1234 on 28-Oct.',
          receivedAt: now,
          forceQueue: true,
        );

        expect(debitResult.queued, isTrue);
        expect(debitResult.candidate?.suggestedAccountId, 'acc-checking');
        expect(debitResult.candidate?.transactionType, 'expense');
        expect(controller.state.captureCandidates.length, 1);

        // 2. Ingest credit SMS for Savings account with the same amount
        final creditResult = await controller.importSmsMessageDetailed(
          'Alert: INR 5000.00 credited to A/C ending 5678 on 28-Oct.',
          receivedAt: now.add(const Duration(seconds: 15)),
          forceQueue: true,
        );

        // Crucial invariant: Should NOT be discarded as duplicate!
        expect(creditResult.status, CaptureImportStatus.queued);
        expect(creditResult.candidate?.suggestedAccountId, 'acc-savings');
        expect(creditResult.candidate?.transactionType, 'income');
        expect(controller.state.captureCandidates.length, 2);

        // 3. Link them as transfer
        await controller.linkTransferCandidates(
          debitCandidateId: debitResult.candidate!.id,
          creditCandidateId: creditResult.candidate!.id,
        );

        final updatedDebit = controller.state.captureCandidates.firstWhere(
          (c) => c.id == debitResult.candidate!.id,
        );
        final updatedCredit = controller.state.captureCandidates.firstWhere(
          (c) => c.id == creditResult.candidate!.id,
        );

        expect(updatedDebit.transactionType, 'transfer');
        expect(updatedDebit.suggestedCounterAccountId, 'acc-savings');
        expect(updatedDebit.pairedCandidateId, updatedCredit.id);

        expect(updatedCredit.transactionType, 'transfer');
        expect(updatedCredit.suggestedCounterAccountId, 'acc-checking');
        expect(updatedCredit.pairedCandidateId, updatedDebit.id);

        // 4. Approving one approves both
        await controller.approveCaptureCandidate(updatedDebit.id);
        final finalDebit = controller.state.captureCandidates.firstWhere(
          (c) => c.id == updatedDebit.id,
        );
        final finalCredit = controller.state.captureCandidates.firstWhere(
          (c) => c.id == updatedCredit.id,
        );
        expect(finalDebit.status, 'approved');
        expect(finalCredit.status, 'approved');
        expect(controller.state.transactions.first.type, 'transfer');
      },
    );
  });

  group('ReviewQueueScreen UI for Transfers and Planned Payments', () {
    testWidgets(
      'renders unified Transfer detected card when debit and credit candidates match',
      (tester) async {
        final now = DateTime.now();
        final checking = const Account(
          id: 'acc-chk',
          name: 'HDFC Checking',
          type: 'bank',
          currency: 'INR',
          accountLast4: '1111',
          openingBalance: Money(amountMinor: 5000000, currency: 'INR'),
        );
        final savings = const Account(
          id: 'acc-svg',
          name: 'ICICI Savings',
          type: 'bank',
          currency: 'INR',
          accountLast4: '2222',
          openingBalance: Money(amountMinor: 1000000, currency: 'INR'),
        );

        final debitCand = CaptureCandidate(
          id: 'cand-debit',
          source: 'sms',
          status: 'pending',
          createdAt: now,
          rawText: 'INR 2500 debited from HDFC 1111',
          parsedAmount: const Money(amountMinor: 250000, currency: 'INR'),
          transactionType: 'expense',
          suggestedAccountId: 'acc-chk',
        );
        final creditCand = CaptureCandidate(
          id: 'cand-credit',
          source: 'sms',
          status: 'pending',
          createdAt: now.add(const Duration(minutes: 1)),
          rawText: 'INR 2500 credited to ICICI 2222',
          parsedAmount: const Money(amountMinor: 250000, currency: 'INR'),
          transactionType: 'income',
          suggestedAccountId: 'acc-svg',
        );

        final seedState = emptyLedgerState().copyWith(
          accounts: [checking, savings],
          captureCandidates: [debitCand, creditCand],
          preferences: const LedgerPreferences(
            baseCurrency: 'INR',
            displayCurrency: 'INR',
            enabledCurrencies: ['INR'],
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(ledger: seedState, prefs: prefs),
        );
        addTearDown(container.dispose);
        await container.read(ledgerProvider.notifier).restoreLedgerState(seedState);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light().copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              home: const ReviewQueueScreen(),
            ),
          ),
        );

        await _pumpBounded(tester);

        // Verify unified Transfer Card
        expect(find.text('Transfer detected'), findsOneWidget);
        expect(find.text('Confirm Transfer'), findsOneWidget);
        expect(find.textContaining('From: HDFC Checking'), findsOneWidget);
        expect(find.textContaining('To: ICICI Savings'), findsOneWidget);
      },
    );

    testWidgets(
      'renders Planned payment detected badge and Pay Plan button when candidate matches scheduled payment',
      (tester) async {
        final now = DateTime.now();
        final checking = const Account(
          id: 'acc-chk',
          name: 'Main Checking',
          type: 'bank',
          currency: 'USD',
          accountLast4: '4444',
          openingBalance: Money(amountMinor: 200000, currency: 'USD'),
        );

        // Scheduled transaction due tomorrow for $79.99
        final plannedTx = TransactionRecord(
          id: 'plan-wifi',
          type: 'expense',
          status: 'scheduled',
          source: 'manual',
          name: 'Home Internet',
          accountId: 'acc-chk',
          amount: const Money(amountMinor: 7999, currency: 'USD'),
          baseAmount: const Money(amountMinor: 7999, currency: 'USD'),
          occurredAt: now.add(const Duration(days: 1)),
        );

        // Candidate arriving today with matching $79.99
        final candidate = CaptureCandidate(
          id: 'cand-wifi',
          source: 'sms',
          status: 'pending',
          createdAt: now,
          rawText: 'Charged \$79.99 at Comcast Internet',
          merchant: 'Comcast Internet',
          parsedAmount: const Money(amountMinor: 7999, currency: 'USD'),
          transactionType: 'expense',
          suggestedAccountId: 'acc-chk',
        );

        final seedState = emptyLedgerState().copyWith(
          accounts: [checking],
          transactions: [plannedTx],
          captureCandidates: [candidate],
          preferences: const LedgerPreferences(
            baseCurrency: 'USD',
            displayCurrency: 'USD',
            enabledCurrencies: ['USD'],
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(ledger: seedState, prefs: prefs),
        );
        addTearDown(container.dispose);
        await container.read(ledgerProvider.notifier).restoreLedgerState(seedState);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light().copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              home: const ReviewQueueScreen(),
            ),
          ),
        );

        await _pumpBounded(tester);

        // Verify Planned Payment badge and Pay Plan button
        expect(find.text('Planned: Home Internet'), findsOneWidget);
        expect(find.text('Pay Plan'), findsOneWidget);
        // And standard Confirm button is still present!
        expect(find.text('Confirm'), findsOneWidget);
      },
    );

    testWidgets(
      'AddRecordScreen pre-populates Transfer mode with counter account from paired candidate',
      (tester) async {
        final now = DateTime.now();
        final checking = const Account(
          id: 'acc-chk',
          name: 'HDFC Checking',
          type: 'bank',
          currency: 'INR',
          accountLast4: '1111',
          openingBalance: Money(amountMinor: 5000000, currency: 'INR'),
        );
        final savings = const Account(
          id: 'acc-svg',
          name: 'ICICI Savings',
          type: 'bank',
          currency: 'INR',
          accountLast4: '2222',
          openingBalance: Money(amountMinor: 1000000, currency: 'INR'),
        );

        final transferCandidate = CaptureCandidate(
          id: 'cand-debit-1',
          source: 'sms',
          status: 'pending',
          createdAt: now,
          rawText: 'INR 2500 debited from HDFC 1111',
          parsedAmount: const Money(amountMinor: 250000, currency: 'INR'),
          transactionType: 'transfer',
          suggestedAccountId: 'acc-chk',
          suggestedCounterAccountId: 'acc-svg',
          pairedCandidateId: 'cand-credit-1',
        );

        final pairedCandidate = CaptureCandidate(
          id: 'cand-credit-1',
          source: 'sms',
          status: 'pending',
          createdAt: now,
          rawText: 'INR 2500 credited to ICICI 2222',
          parsedAmount: const Money(amountMinor: 250000, currency: 'INR'),
          transactionType: 'transfer',
          suggestedAccountId: 'acc-svg',
          suggestedCounterAccountId: 'acc-chk',
          pairedCandidateId: 'cand-debit-1',
        );

        final seedState = emptyLedgerState().copyWith(
          accounts: [checking, savings],
          captureCandidates: [transferCandidate, pairedCandidate],
          preferences: const LedgerPreferences(
            baseCurrency: 'INR',
            displayCurrency: 'INR',
            enabledCurrencies: ['INR'],
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(ledger: seedState, prefs: prefs),
        );
        addTearDown(container.dispose);
        await container.read(ledgerProvider.notifier).restoreLedgerState(seedState);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light().copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              home: AddRecordScreen(
                captureCandidateId: transferCandidate.id,
              ),
            ),
          ),
        );

        await _pumpBounded(tester);

        // Verify Transfer type is selected and both accounts are present
        expect(find.text('Transfer'), findsWidgets);
        expect(find.text('HDFC Checking'), findsOneWidget);
        expect(find.text('ICICI Savings'), findsOneWidget);
      },
    );

    testWidgets(
      'AddRecordScreen pre-populates Planned payment and candidate and clears both on save',
      (tester) async {
        final now = DateTime.now();
        final checking = const Account(
          id: 'acc-chk',
          name: 'Main Checking',
          type: 'bank',
          currency: 'USD',
          accountLast4: '4444',
          openingBalance: Money(amountMinor: 200000, currency: 'USD'),
        );

        const category = Category(
          id: 'cat-utilities',
          name: 'Utilities',
          kind: 'expense',
        );

        final plannedTx = TransactionRecord(
          id: 'plan-wifi',
          type: 'expense',
          status: 'scheduled',
          source: 'manual',
          name: 'Home Internet',
          accountId: 'acc-chk',
          categoryId: 'cat-utilities',
          amount: const Money(amountMinor: 7999, currency: 'USD'),
          baseAmount: const Money(amountMinor: 7999, currency: 'USD'),
          occurredAt: now.add(const Duration(days: 1)),
        );

        final candidate = CaptureCandidate(
          id: 'cand-wifi',
          source: 'sms',
          status: 'pending',
          createdAt: now,
          rawText: 'Charged \$79.99 at Comcast Internet',
          merchant: 'Comcast Internet',
          parsedAmount: const Money(amountMinor: 7999, currency: 'USD'),
          transactionType: 'expense',
          suggestedAccountId: 'acc-chk',
        );

        final seedState = emptyLedgerState().copyWith(
          accounts: [checking],
          categories: [category],
          transactions: [plannedTx],
          captureCandidates: [candidate],
          preferences: const LedgerPreferences(
            baseCurrency: 'USD',
            displayCurrency: 'USD',
            enabledCurrencies: ['USD'],
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(ledger: seedState, prefs: prefs),
        );
        addTearDown(container.dispose);
        await container.read(ledgerProvider.notifier).restoreLedgerState(seedState);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light().copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              home: AddRecordScreen(
                plannedId: plannedTx.id,
                captureCandidateId: candidate.id,
              ),
            ),
          ),
        );

        await _pumpBounded(tester);

        // Save the transaction by tapping the save check button
        final saveBtn = find.byIcon(Icons.check_rounded).first;
        await tester.tap(saveBtn);
        await _pumpBounded(tester);

        final updatedState = container.read(ledgerProvider);

        // Candidate marked approved
        final approvedCandidate = updatedState.captureCandidates.firstWhere(
          (c) => c.id == candidate.id,
        );
        expect(approvedCandidate.status, 'approved');

        // Planned transaction marked finished (non-recurring)
        final finishedPlan = updatedState.transactions.firstWhere(
          (t) => t.id == plannedTx.id,
        );
        expect(finishedPlan.status, 'finished');

        // New cleared transaction created
        final newTx = updatedState.transactions.firstWhere(
          (t) => t.id != plannedTx.id,
        );
        expect(newTx.status, 'cleared');
        expect(newTx.amount.amountMinor, 7999);
      },
    );
  });
}
