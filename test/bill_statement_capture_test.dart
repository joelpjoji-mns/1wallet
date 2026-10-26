import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

void main() {
  group('Bill Statement Detection and Parsing', () {
    test('detects statement and bill notifications', () {
      expect(
        isBillStatementMessage(
          'Statement generated for your HDFC Bank Credit Card ending 1234. Total Amount Due: INR 12,450.00, Payment Due Date: 15-Nov-2026.',
        ),
        isTrue,
      );
      expect(
        isBillStatementMessage(
          'Your ICICI Bank Credit Card XX5678 statement has been generated. Total Amt Due: Rs. 4,320.50 Due Date: 20/11/2026.',
        ),
        isTrue,
      );
      expect(
        isBillStatementMessage(
          'Chase Card ending 4321: Your monthly statement is ready. Payment of \$342.18 is due on Nov 18, 2026.',
        ),
        isTrue,
      );
      expect(
        isBillStatementMessage(
          'Dear Customer, e-bill for your SBI Card ending 9012 is generated. Total Due: Rs 25,000, Min Due: Rs 1,250, Due Date: 05-Dec-26.',
        ),
        isTrue,
      );
      expect(
        isBillStatementMessage(
          'Capital One: Minimum amount due \$25.00 by 12/05/2026 on card ending 9988.',
        ),
        isTrue,
      );
      expect(
        isBillStatementMessage(
          'Rs.500 debited from a/c XX1234 at AMAZON on 01-01-24.',
        ),
        isFalse,
      );
    });

    test('parses Indian bank statement SMS with due date and amounts', () {
      const text =
          'Statement generated for your HDFC Bank Credit Card ending 1234. Total Amount Due: INR 12,450.00, Min Amount Due: INR 650.00, Payment Due Date: 15-Nov-2026.';
      final notice = parseBillStatementNotice(text, fallbackCurrency: 'INR');

      expect(notice, isNotNull);
      expect(notice!.amount?.amountMinor, 1245000);
      expect(notice.amount?.currency, 'INR');
      expect(notice.minAmountDue?.amountMinor, 65000);
      expect(notice.dueDay, 15);
      expect(notice.dueDate?.day, 15);
      expect(notice.dueDate?.month, 11);
      expect(notice.dueDate?.year, 2026);
      expect(notice.last4, '1234');
      expect(notice.institution, 'HDFC');
    });

    test('parses numeric date format (DD/MM/YYYY)', () {
      const text =
          'Your ICICI Bank Credit Card XX5678 statement has been generated. Total Amt Due: Rs. 4,320.50 Due Date: 20/11/2026.';
      final notice = parseBillStatementNotice(text, fallbackCurrency: 'INR');

      expect(notice, isNotNull);
      expect(notice!.amount?.amountMinor, 432050);
      expect(notice.dueDay, 20);
      expect(notice.dueDate?.day, 20);
      expect(notice.dueDate?.month, 11);
      expect(notice.dueDate?.year, 2026);
      expect(notice.last4, '5678');
      expect(notice.institution, 'ICICI');
    });

    test('parses US credit card statement with month name and dollar amount', () {
      const text =
          'Chase Card ending 4321: Your monthly statement is ready. Payment of \$342.18 is due on Nov 18, 2026.';
      final notice = parseBillStatementNotice(text, fallbackCurrency: 'USD');

      expect(notice, isNotNull);
      expect(notice!.amount?.amountMinor, 34218);
      expect(notice.amount?.currency, 'USD');
      expect(notice.dueDay, 18);
      expect(notice.dueDate?.month, 11);
      expect(notice.last4, '4321');
      expect(notice.institution, 'Chase');
    });

    test('falls back statement day to receivedAt if not explicit in text', () {
      const text =
          'Axis Bank Credit Card ending 7788: Bill is generated. Total Due Rs 8,000. Payment due on 25th.';
      final receivedAt = DateTime(2026, 10, 5, 14, 30);
      final notice = parseBillStatementNotice(
        text,
        fallbackCurrency: 'INR',
        receivedAt: receivedAt,
      );

      expect(notice, isNotNull);
      expect(notice!.amount?.amountMinor, 800000);
      expect(notice.dueDay, 25);
      expect(notice.statementDay, 5);
      expect(notice.last4, '7788');
      expect(notice.institution, 'Axis');
    });
  });

  group('matchAccountForStatement', () {
    const cardAccount = Account(
      id: 'acc_hdfc_card',
      name: 'HDFC Millennia',
      type: 'credit_card',
      currency: 'INR',
      openingBalance: Money(amountMinor: 0, currency: 'INR'),
      institution: 'HDFC',
      cardLast4: '1234',
    );

    const bankAccount = Account(
      id: 'acc_sbi_savings',
      name: 'SBI Savings',
      type: 'savings',
      currency: 'INR',
      openingBalance: Money(amountMinor: 100000, currency: 'INR'),
      institution: 'SBI',
      accountLast4: '9999',
    );

    const amexCard = Account(
      id: 'acc_amex',
      name: 'Amex Platinum',
      type: 'credit_card',
      currency: 'USD',
      openingBalance: Money(amountMinor: 0, currency: 'USD'),
      institution: 'Amex',
      cardLast4: '3001',
    );

    const ledgerState = LedgerState(
      version: 1,
      userId: 'test_user',
      preferences: LedgerPreferences(),
      accounts: [cardAccount, bankAccount, amexCard],
      categories: [],
      transactions: [],
      captureCandidates: [],
    );

    test('matches account exactly by cardLast4 and institution', () {
      const text =
          'Statement generated for HDFC Card ending 1234. Total Due: Rs. 15,000. Due on 10th.';
      final notice = parseBillStatementNotice(text, fallbackCurrency: 'INR')!;
      final matched = matchAccountForStatement(ledgerState, notice);

      expect(matched, isNotNull);
      expect(matched!.id, 'acc_hdfc_card');
    });

    test('matches credit card loosely by institution and card context when last4 is masked differently', () {
      const text =
          'HDFC Bank Credit Card statement generated. Total Due Rs. 5,000 due by Nov 12.';
      final notice = parseBillStatementNotice(text, fallbackCurrency: 'INR')!;
      final matched = matchAccountForStatement(ledgerState, notice);

      expect(matched, isNotNull);
      expect(matched!.id, 'acc_hdfc_card');
    });

    test('matches account by full accountNumber in encryptedDetails', () {
      const customCard = Account(
        id: 'acc_custom_card',
        name: 'Custom Rewards Card',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: Money(amountMinor: 0, currency: 'USD'),
        institution: 'Capital One',
        encryptedDetails: {'accountNumber': '5412750099887766'},
      );
      const customState = LedgerState(
        version: 1,
        userId: 'test_user',
        preferences: LedgerPreferences(),
        accounts: [customCard],
        categories: [],
        transactions: [],
        captureCandidates: [],
      );

      const text =
          'Your Capital One Card ending 7766 statement is ready. Amount due \$150.00 by 11/25/2026.';
      final notice = parseBillStatementNotice(text, fallbackCurrency: 'USD')!;
      final matched = matchAccountForStatement(customState, notice);

      expect(matched, isNotNull);
      expect(matched!.id, 'acc_custom_card');
    });
  });
}
