import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_archive.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/imports/wallet_csv_parser.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ledger codec round-trips current sample data', () {
    final state = sampleLedgerState();
    final restored = decodeLedgerState(encodeLedgerState(state));

    expect(restored.version, currentLedgerStateVersion);
    expect(restored.accounts.length, state.accounts.length);
    expect(restored.categories.length, state.categories.length);
    expect(restored.transactions.length, state.transactions.length);
    expect(restored.captureCandidates.length, state.captureCandidates.length);
    expect(restored.importBatches.length, state.importBatches.length);
    expect(restored.accounts.first.name, state.accounts.first.name);
  });

  test('starter wallet creation does not overwrite existing data', () async {
    final seeded = sampleLedgerState();
    final controller = LedgerController(
      const LedgerRepository(),
      initialState: seeded,
    );
    addTearDown(controller.dispose);

    await controller.createStarterWallet(
      userId: seeded.userId,
      accountName: 'Replacement wallet',
      currency: 'INR',
      accountColor: const Color(0xFF315DA8),
    );

    expect(controller.state.accounts.length, seeded.accounts.length);
    expect(controller.state.transactions.length, seeded.transactions.length);
    expect(
      controller.state.accounts.any(
        (item) => item.name == 'Replacement wallet',
      ),
      isFalse,
    );
  });

  test(
    'ledger controller persists account, transaction, and capture updates',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      await controller.upsertAccount(
        name: 'QA Savings',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 125000,
        institution: 'QA Bank',
      );
      final account = controller.state.accounts.firstWhere(
        (item) => item.name == 'QA Savings',
      );

      await controller.addTransaction(
        type: 'income',
        accountId: account.id,
        amountMinor: 50000,
        categoryId: controller.state.categories.first.id,
        notes: 'Persistence test',
      );
      final candidate = await controller.importSmsMessage(
        'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on 08-Jun.',
      );
      expect(candidate, isNotNull);
      await controller.updateCaptureCandidateStatus(candidate!.id, 'approved');

      final restored = await repository.load();
      expect(restored, isNotNull);
      expect(
        restored!.accounts.any((item) => item.name == 'QA Savings'),
        isTrue,
      );
      expect(
        restored.transactions.any((item) => item.notes == 'Persistence test'),
        isTrue,
      );
      expect(
        restored.captureCandidates
            .firstWhere((item) => item.id == candidate.id)
            .status,
        'approved',
      );
    },
  );

  test('ledger controller persists account color changes', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    final account = await controller.upsertAccount(
      name: 'Colorful account',
      type: 'bank',
      currency: 'INR',
      color: const Color(0xFF315DA8),
    );

    await controller.upsertAccount(
      id: account.id,
      name: account.name,
      type: account.type,
      currency: account.currency,
      color: const Color(0xFFFFE082),
    );

    final restored = await repository.load();
    expect(restored, isNotNull);
    expect(
      restored!.accounts.firstWhere((item) => item.id == account.id).color,
      const Color(0xFFFFE082),
    );
  });

  test('ledger controller updates and deletes transactions', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    final account = await controller.upsertAccount(
      id: 'acc-bank',
      name: 'HDFC Main',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 125000,
      institution: 'QA Bank',
    );
    final original = await controller.upsertTransaction(
      id: 'tx-original',
      type: 'expense',
      accountId: account.id,
      amountMinor: 5000,
      categoryId: controller.state.categories.first.id,
      notes: 'Original transaction',
      occurredAt: DateTime(2026, 6, 1),
    );
    await controller.upsertTransaction(
      id: original.id,
      type: 'income',
      accountId: account.id,
      amountMinor: 12345,
      categoryId: controller.state.categories.first.id,
      notes: 'Edited transaction',
    );

    expect(controller.state.transactions.length, 1);
    expect(
      controller.state.transactions
          .firstWhere((item) => item.id == original.id)
          .notes,
      'Edited transaction',
    );
    expect(
      controller.state.transactions
          .firstWhere((item) => item.id == original.id)
          .amount
          .amountMinor,
      12345,
    );

    await controller.deleteTransaction(original.id);
    expect(
      controller.state.transactions.any((item) => item.id == original.id),
      isFalse,
    );
  });

  test(
    'ledger controller deletes unused accounts and persists removal',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      final account = await controller.upsertAccount(
        id: 'acc-unused',
        name: 'Unused account',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 0,
      );

      await controller.deleteAccount(account.id);

      expect(
        controller.state.accounts.any((item) => item.id == account.id),
        isFalse,
      );
      final restored = await repository.load();
      expect(restored, isNotNull);
      expect(restored!.accounts.any((item) => item.id == account.id), isFalse);
    },
  );

  test('ledger controller archives accounts with linked records', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    final account = await controller.upsertAccount(
      id: 'acc-used',
      name: 'Used account',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 0,
    );
    final transaction = await controller.upsertTransaction(
      id: 'tx-linked',
      type: 'income',
      accountId: account.id,
      amountMinor: 1000,
      categoryId: controller.state.categories.first.id,
    );

    await controller.deleteAccount(account.id);

    final archived = controller.state.accounts.firstWhere(
      (item) => item.id == account.id,
    );
    expect(archived.isArchived, isTrue);
    expect(
      controller.state.transactions.any((item) => item.id == transaction.id),
      isTrue,
    );

    final restored = await repository.load();
    expect(restored, isNotNull);
    expect(
      restored!.accounts.firstWhere((item) => item.id == account.id).isArchived,
      isTrue,
    );
  });

  test(
    'ledger controller schedules, postpones, and posts recurring records',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      final account = await controller.upsertAccount(
        id: 'acc-bank',
        name: 'HDFC Main',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 125000,
        institution: 'QA Bank',
      );
      final nextDate = DateTime(2026, 7, 10);
      final scheduled = await controller.upsertTransaction(
        type: 'expense',
        accountId: account.id,
        amountMinor: 42000,
        status: 'scheduled',
        source: 'recurring',
        categoryId: controller.state.categories.first.id,
        paymentMethod: 'Auto debit',
        notes: 'Monthly Netflix subscription',
        recurrenceFrequency: 'monthly',
        occurredAt: nextDate,
      );

      expect(scheduled.status, 'scheduled');
      expect(scheduled.source, 'recurring');

      final postponed = await controller.postponeTransaction(
        scheduled.id,
        const Duration(days: 7),
      );
      expect(postponed.occurredAt, nextDate.add(const Duration(days: 7)));

      final posted = await controller.updateTransactionStatus(
        scheduled.id,
        'cleared',
        occurredAt: DateTime(2026, 7, 17),
      );
      expect(posted.status, 'cleared');
      expect(posted.occurredAt, DateTime(2026, 7, 17));

      final restored = await repository.load();
      expect(restored, isNotNull);
      expect(
        restored!.transactions
            .firstWhere((item) => item.id == scheduled.id)
            .status,
        'cleared',
      );
    },
  );

  test(
    'ledger controller creates loan accounts and scheduled EMI records',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      final source = await controller.upsertAccount(
        id: 'acc-bank',
        name: 'HDFC Main',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 125000,
        institution: 'QA Bank',
      );
      final loan = await controller.upsertAccount(
        name: 'QA Loan',
        type: 'loan',
        currency: 'INR',
        openingBalanceMinor: -1000000,
        institution: 'QA Lender',
        loanDetails: AccountLoanDetails(
          loanKind: 'loan',
          principal: const Money(amountMinor: 1000000, currency: 'INR'),
          repaymentAmount: const Money(amountMinor: 50000, currency: 'INR'),
          interestRatePercent: 9.5,
          repaymentCount: 24,
          repaymentStartsOn: DateTime(2026, 7, 5),
          repaymentSourceAccountId: 'acc-bank',
        ),
        includeInTotals: false,
        includeInNetWorth: true,
        showOnHome: false,
      );

      expect(loan.type, 'loan');
      expect(loan.openingBalance.amountMinor, -1000000);
      expect(loan.includeInTotals, isFalse);
      expect(loan.loanDetails?.interestRatePercent, 9.5);
      expect(loan.loanDetails?.repaymentCount, 24);

      final emi = await controller.upsertTransaction(
        type: 'loan_repayment',
        accountId: source.id,
        counterAccountId: loan.id,
        amountMinor: 50000,
        status: 'scheduled',
        source: 'recurring',
        occurredAt: DateTime(2026, 7, 5),
        recurrenceFrequency: 'monthly',
      );

      expect(emi.counterAccountId, loan.id);
      expect(emi.status, 'scheduled');

      final restored = await repository.load();
      expect(restored, isNotNull);
      expect(
        restored!.accounts.firstWhere((item) => item.id == loan.id).institution,
        'QA Lender',
      );
      final restoredLoan = restored.accounts.firstWhere(
        (item) => item.id == loan.id,
      );
      expect(restoredLoan.loanDetails?.principal?.amountMinor, 1000000);
      expect(restoredLoan.loanDetails?.repaymentAmount?.amountMinor, 50000);
      expect(restoredLoan.loanDetails?.interestRatePercent, 9.5);
      expect(restoredLoan.loanDetails?.repaymentCount, 24);
      expect(restoredLoan.loanDetails?.repaymentStartsOn, DateTime(2026, 7, 5));
      expect(restoredLoan.loanDetails?.repaymentSourceAccountId, 'acc-bank');
      expect(
        restored.transactions
            .firstWhere((item) => item.counterAccountId == loan.id)
            .type,
        'loan_repayment',
      );
    },
  );

  test('ledger controller persists budgets and goals', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    await controller.addBudget(name: 'QA budget', amountMinor: 250000);
    await controller.addGoal(name: 'QA goal', targetMinor: 750000);

    final restored = await repository.load();
    expect(restored, isNotNull);
    expect(restored!.budgets.first.name, 'QA budget');
    expect(restored.budgets.first.amount.amountMinor, 250000);
    expect(restored.goals.first.name, 'QA goal');
    expect(restored.goals.first.target.amountMinor, 750000);
  });

  test('ledger controller persists category create and archive', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    await controller.upsertCategory(name: 'QA category', kind: 'income');
    final category = controller.state.categories.firstWhere(
      (item) => item.name == 'QA category',
    );
    expect(category.kind, 'income');

    await controller.archiveCategory(category.id, archived: true);
    final restored = await repository.load();
    expect(restored, isNotNull);
    expect(
      restored!.categories
          .firstWhere((item) => item.id == category.id)
          .isArchived,
      isTrue,
    );
  });

  test(
    'ledger controller imports SMS messages as capture candidates',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      final candidate = await controller.importSmsMessage(
        'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on 08-Jun.',
      );

      expect(candidate, isNotNull);
      expect(candidate!.parsedAmount?.amountMinor, 89000);
      expect(candidate.merchant, 'SWIGGY');
      expect(candidate.transactionType, 'expense');

      final ignored = await controller.importSmsMessage(
        'Your OTP is 123456. Do not share it.',
      );
      expect(ignored, isNull);

      final restored = await repository.load();
      expect(restored, isNotNull);
      expect(restored!.captureCandidates.first.rawText, contains('SWIGGY'));
    },
  );

  test('ledger controller approves SMS candidates into transactions', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    await controller.upsertAccount(
      id: 'acc-bank',
      name: 'HDFC Main',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 125000,
      institution: 'QA Bank',
    );

    final candidate = await controller.importSmsMessage(
      'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on 08-Jun.',
    );
    final before = controller.state.transactions.length;
    final transaction = await controller.approveCaptureCandidate(candidate!.id);

    expect(transaction.amount.amountMinor, 89000);
    expect(transaction.source, 'sms');
    expect(transaction.notes, 'SWIGGY');
    expect(controller.state.transactions.length, before + 1);
    expect(
      controller.state.captureCandidates
          .firstWhere((item) => item.id == candidate.id)
          .status,
      'approved',
    );
  });

  test('ledger controller approves edited capture candidate fields', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    await controller.upsertAccount(
      id: 'acc-bank',
      name: 'HDFC Main',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 125000,
      institution: 'QA Bank',
    );
    await controller.upsertAccount(
      id: 'acc-cash',
      name: 'Cash Wallet',
      type: 'cash',
      currency: 'INR',
      openingBalanceMinor: 0,
      institution: 'QA Cash',
    );

    final candidate = await controller.importSmsMessage(
      'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on 08-Jun.',
    );
    await controller.updateCaptureCandidateDetails(
      id: candidate!.id,
      parsedAmount: const Money(amountMinor: 123400, currency: 'INR'),
      merchant: 'Edited merchant',
      transactionType: 'income',
      suggestedAccountId: 'acc-cash',
      suggestedCategoryId: 'cat-salary',
    );

    final transaction = await controller.approveCaptureCandidate(candidate.id);
    expect(transaction.type, 'income');
    expect(transaction.accountId, 'acc-cash');
    expect(transaction.categoryId, 'cat-salary');
    expect(transaction.amount.amountMinor, 123400);
    expect(transaction.notes, 'Edited merchant');
  });

  test(
    'ledger controller imports parsed wallet CSV rows as transactions',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      await controller.upsertAccount(
        id: 'acc-bank',
        name: 'HDFC Main',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 125000,
        institution: 'QA Bank',
      );

      final result = parseWalletCsv('''
date,account,amount,category,notes
2026-06-08,HDFC Main,-890,Food,Swiggy dinner
2026-06-07,HDFC Main,185000,Salary,QA monthly salary
''');
      final before = controller.state.transactions.length;
      final count = await controller.importWalletCsvRows(result.rows);

      expect(count, 2);
      expect(controller.state.transactions.length, before + 2);
      expect(controller.state.transactions.first.source, 'import');
      expect(controller.state.transactions.first.notes, 'Swiggy dinner');
      expect(controller.state.transactions.first.type, 'expense');

      final restored = await repository.load();
      expect(restored, isNotNull);
      expect(
        restored!.transactions.where((item) => item.source == 'import'),
        hasLength(2),
      );
      expect(restored.importBatches.first.importedCount, 2);
      expect(restored.importBatches.first.duplicateCount, 0);
    },
  );

  test(
    'ledger controller records CSV duplicate skips in import batches',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      await controller.upsertAccount(
        id: 'acc-bank',
        name: 'HDFC Main',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 125000,
        institution: 'QA Bank',
      );

      final rows = parseWalletCsv('''
date,account,amount,category,notes
2026-06-08,HDFC Main,-890,Food,Swiggy dinner
''').rows;
      expect(await controller.importWalletCsvRows(rows), 1);
      expect(await controller.importWalletCsvRows(rows), 0);

      expect(controller.state.importBatches.first.rowCount, 1);
      expect(controller.state.importBatches.first.importedCount, 0);
      expect(controller.state.importBatches.first.duplicateCount, 1);
    },
  );

  test(
    'ledger controller rolls back transactions linked to an import batch',
    () async {
      const repository = LedgerRepository();
      final controller = LedgerController(repository);
      addTearDown(controller.dispose);

      await controller.upsertAccount(
        id: 'acc-bank',
        name: 'HDFC Main',
        type: 'bank',
        currency: 'INR',
        openingBalanceMinor: 125000,
        institution: 'QA Bank',
      );

      final rows = parseWalletCsv('''
date,account,amount,category,notes
2026-06-08,HDFC Main,-890,Food,Swiggy dinner
2026-06-07,HDFC Main,185000,Salary,QA monthly salary
''').rows;
      final before = controller.state.transactions.length;
      await controller.importWalletCsvRows(rows);
      final batch = controller.state.importBatches.first;
      expect(controller.state.transactions.length, before + 2);
      expect(
        controller.state.transactions.where(
          (item) => item.importBatchId == batch.id,
        ),
        hasLength(2),
      );

      final removed = await controller.rollbackImportBatch(batch.id);
      expect(removed, 2);
      expect(controller.state.transactions.length, before);
      expect(controller.state.importBatches.first.status, 'rolled_back');
    },
  );

  test('ledger archive round-trips and rejects corrupted payloads', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    final account = await controller.upsertAccount(
      id: 'acc-bank',
      name: 'HDFC Main',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 125000,
      institution: 'QA Bank',
    );
    await controller.upsertTransaction(
      id: 'tx-salary',
      type: 'income',
      accountId: account.id,
      amountMinor: 18500000,
      categoryId: controller.state.categories.first.id,
      notes: 'Seed salary',
      occurredAt: DateTime(2026, 6, 1),
    );

    final archive = controller.exportArchive(source: 'test');
    final restored = decodeLedgerArchive(archive);
    expect(restored.accounts.length, controller.state.accounts.length);
    expect(restored.transactions.length, controller.state.transactions.length);

    await controller.deleteTransaction('tx-salary');
    expect(
      controller.state.transactions.any((item) => item.id == 'tx-salary'),
      isFalse,
    );
    await controller.importArchive(archive);
    expect(
      controller.state.transactions.any((item) => item.id == 'tx-salary'),
      isTrue,
    );

    final corrupted = archive.replaceFirst('tx-salary', 'tx-tampered');
    expect(() => decodeLedgerArchive(corrupted), throwsFormatException);
  });

  test('ledger controller persists home widget ordering', () async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    addTearDown(controller.dispose);

    await controller.setHomeWidgetOrder(['recentRecords', 'balanceHero']);
    var restored = await repository.load();
    expect(restored, isNotNull);
    expect(restored!.preferences.homeWidgetOrder, [
      'recentRecords',
      'balanceHero',
    ]);

    await controller.resetHomeWidgetOrder();
    restored = await repository.load();
    expect(
      restored!.preferences.homeWidgetOrder,
      const LedgerPreferences().homeWidgetOrder,
    );
  });

  test('repository returns null for empty storage', () async {
    const repository = LedgerRepository();
    final restored = await repository.load();

    expect(restored, isNull);
  });

  test('decode tolerates a minimal persisted ledger payload', () {
    final restored = decodeLedgerState('''
      {
        "accounts": [],
        "categories": [],
        "transactions": [],
        "budgets": [],
        "goals": [],
        "captureCandidates": []
      }
    ''');

    expect(restored.userId, 'local-user');
    expect(restored.preferences.baseCurrency, 'INR');
    expect(restored.accounts, isEmpty);
  });
}
