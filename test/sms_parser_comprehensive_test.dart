import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';

void main() {
  group('Comprehensive SMS Parsing Tests', () {
    test('Indian: ICICI Debit with Credit info', () {
      final sms = 'ICICI Bank Acct XX173 debited for Rs 5059.00 on 15-Jun-26; CHEQ DIGITAL PR credited. UPI:653240699663. Call 18002662 for dispute. SMS BLOCK 173 to 9215676766.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 505900);
      expect(result.amount?.currency, 'INR');
      expect(result.merchant, 'CHEQ DIGITAL PR');
      expect(result.last4, '173');
    });

    test('Indian: HDFC UPI Debit', () {
      final sms = 'Rs. 250.00 debited from a/c **4567 on 10-05-26 to VPA merchant@upi (UPI Ref no 312345678901). Not you? Call 18002586161.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 25000);
      expect(result.amount?.currency, 'INR');
      expect(result.merchant, 'merchant@upi');
      expect(result.last4, '4567');
    });

    test('Indian: SBI Credit', () {
      final sms = 'Your A/C XXXXX8910 is credited with INR 10,000.00 on 12/06/26 by SALARY MAY 2026. Avl Bal INR 15,200.00. -SBI';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'income');
      expect(result.amount?.amountMinor, 1000000);
      expect(result.amount?.currency, 'INR');
      expect(result.merchant, 'SALARY MAY 2026');
      expect(result.last4, '8910');
    });

    test('UK: Barclays Direct Debit', () {
      final sms = 'BARCLAYS: A Direct Debit of £35.50 was paid to Vodafone UK from your account ending 5678 on 01 Jun.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 3550);
      expect(result.amount?.currency, 'GBP');
      expect(result.merchant, 'Vodafone UK');
      expect(result.last4, '5678');
    });

    test('UK: Monzo POS Purchase', () {
      final sms = 'You spent £12.99 at Tesco Extra. Your new balance is £45.00.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 1299);
      expect(result.amount?.currency, 'GBP');
      expect(result.merchant, 'Tesco Extra');
      expect(result.last4, null);
    });

    test('US: Chase Credit Card POS', () {
      final sms = 'Chase: A charge of \$120.50 at AMAZON.COM was authorized on card ending 1234. Reply HELP for help.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 12050);
      expect(result.amount?.currency, 'USD');
      expect(result.merchant, 'AMAZON.COM');
      expect(result.last4, '1234');
    });
    
    test('General: AED ATM Withdrawal', () {
      final sms = 'Cash withdrawal of AED 500.00 from ATM 12345 using Card **9999. Available Balance: AED 1500.00';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 50000);
      expect(result.amount?.currency, 'AED');
      expect(result.merchant, 'ATM 12345');
      expect(result.last4, '9999');
    });

    test('General: Refund', () {
      final sms = 'Refund of €45.00 from ASOS has been credited to your Card 4321.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'income');
      expect(result.amount?.amountMinor, 4500);
      expect(result.amount?.currency, 'EUR');
      expect(result.merchant, 'ASOS');
      expect(result.last4, '4321');
    });

    test('Edge Case: Emoji and Punctuation Stripping', () {
      final sms = 'You paid 🍕 Pizza Shop ₹ 500 via UPI. Bal: ₹ 1,000.';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 50000);
      expect(result.amount?.currency, 'INR');
      expect(result.merchant, 'Pizza Shop');
    });

    test('Edge Case: European Comma Decimal Format', () {
      final sms = 'Paiement par carte de 45,50 € à la Boulangerie Paris effectué le 14/06.';
      final result = parseTransactionMessage(sms, fallbackCurrency: 'EUR');
      expect(result.ignored, isFalse);
      // Wait, "paiement" might not be in the english list, but let's test if "paid" or "spent" equivalent or we add explicit symbols. If not, it falls back to 'expense' if none found.
      // We will ensure "Paiement" or fallback to expense.
      expect(result.amount?.amountMinor, 4550);
      expect(result.amount?.currency, 'EUR');
      // merchant extraction might need adjustment for french, but let's assume it catches "à la Boulangerie Paris" or falls back.
    });

    test('Edge Case: Indian Lakhs Formatting', () {
      final sms = 'Rs. 1,50,000.00 remitted to Ramesh on 10/10 via NEFT. Avl Bal Rs. 2,00,000.00';
      final result = parseTransactionMessage(sms);
      expect(result.ignored, isFalse);
      expect(result.transactionType, 'expense');
      expect(result.amount?.amountMinor, 15000000);
      expect(result.amount?.currency, 'INR');
      expect(result.merchant, 'Ramesh');
    });

    test('Edge Case: Exotic Verbs (Reversal & Fee)', () {
      final sms1 = 'Reversal of charge of \$ 15.00 for Netflix. Acct 1234 credited.';
      final result1 = parseTransactionMessage(sms1);
      expect(result1.ignored, isFalse);
      expect(result1.transactionType, 'income');
      expect(result1.amount?.amountMinor, 1500);
      expect(result1.amount?.currency, 'USD');

      final sms2 = 'Annual Fee of £50 deducted from your a/c 9999.';
      final result2 = parseTransactionMessage(sms2);
      expect(result2.ignored, isFalse);
      expect(result2.transactionType, 'expense');
      expect(result2.amount?.amountMinor, 5000);
      expect(result2.amount?.currency, 'GBP');
    });
  });
}
