import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers — lightweight account & state builders
// ──────────────────────────────────────────────────────────────────────────────

Account _account({
  String id = 'acc-1',
  String name = 'My Account',
  String type = 'bank',
  String currency = 'INR',
  String? institution,
  String? groupName,
  String? cardLast4,
  String? accountLast4,
  bool isArchived = false,
  Map<String, String>? encryptedDetails,
}) {
  return Account(
    id: id,
    name: name,
    type: type,
    currency: currency,
    openingBalance: const Money(amountMinor: 0, currency: 'INR'),
    institution: institution,
    groupName: groupName,
    cardLast4: cardLast4,
    accountLast4: accountLast4,
    isArchived: isArchived,
    encryptedDetails: encryptedDetails,
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Tests for extractAllNumberFragments
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  group('extractAllNumberFragments', () {
    test('extracts masked XX patterns', () {
      final fragments = extractAllNumberFragments('XX1234 debited');
      expect(fragments, contains('1234'));
    });

    test('extracts masked **** patterns', () {
      final fragments = extractAllNumberFragments('card ****5678');
      expect(fragments, contains('5678'));
    });

    test('extracts dots masking ...1234', () {
      final fragments = extractAllNumberFragments('Acct...5678 credited');
      expect(fragments, contains('5678'));
    });

    test('extracts keyword-prefixed digits', () {
      final fragments =
          extractAllNumberFragments('account ending in 9012');
      expect(fragments, contains('9012'));
    });

    test('extracts bare standalone 3-4 digit sequences', () {
      final fragments =
          extractAllNumberFragments('From a/c 173 to merchant');
      expect(fragments, contains('173'));
    });

    test('extracts multiple fragments from complex SMS', () {
      final fragments = extractAllNumberFragments(
        'ICICI Bank Acct XX173 debited for Rs 5059.00 on 15-Jun; card ending 4567.',
      );
      expect(fragments, contains('173'));
      expect(fragments, contains('4567'));
    });

    test('generates sub-suffixes for longer sequences', () {
      final fragments = extractAllNumberFragments('XX12345 debited');
      expect(fragments, contains('12345'));
      expect(fragments, contains('2345')); // last 4
      expect(fragments, contains('345')); // last 3
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Tests for enhanced _extractLast4 (via parseTransactionMessage)
  // ────────────────────────────────────────────────────────────────────────────

  group('Enhanced _extractLast4', () {
    test('XX1234 pattern', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from XX1234 on 10-Jun.',
      );
      expect(p.last4, '1234');
    });

    test('****5678 pattern', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from card ****5678.',
      );
      expect(p.last4, '5678');
    });

    test('dots masking ...9012', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from acct...9012.',
      );
      expect(p.last4, '9012');
    });

    test('ending with 1234', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from card ending with 1234.',
      );
      expect(p.last4, '1234');
    });

    test('a/c no XX8910', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from A/C No.XX8910.',
      );
      expect(p.last4, '8910');
    });

    test('account no 5678', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from Account No 5678.',
      );
      expect(p.last4, '5678');
    });

    test('card no ending with 1234', () {
      final p = parseTransactionMessage(
        'Rs 500 spent on Card No ending with 1234 at Amazon.',
      );
      expect(p.last4, '1234');
    });

    test('3-digit account number (Indian banks)', () {
      final p = parseTransactionMessage(
        'ICICI Bank Acct XX173 debited for Rs 5059.00.',
      );
      expect(p.last4, '173');
    });

    test('xxxx lowercase masking', () {
      final p = parseTransactionMessage(
        'Rs 500 debited from card xxxx4567.',
      );
      expect(p.last4, '4567');
    });

    test('from a/c 1234 pattern', () {
      final p = parseTransactionMessage(
        'INR 2000 debited from a/c 1234 to Amazon.',
      );
      expect(p.last4, '1234');
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Tests for institution detection signals
  // ────────────────────────────────────────────────────────────────────────────

  group('Account matching signals', () {
    test('HDFC institution detected', () {
      final p = parseTransactionMessage(
        'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY.',
      );
      expect(p.institutionName, 'HDFC');
      expect(p.last4, '1234');
    });

    test('ICICI institution detected', () {
      final p = parseTransactionMessage(
        'ICICI Bank Acct XX173 debited for Rs 5059.00.',
      );
      expect(p.institutionName, 'ICICI');
      expect(p.last4, '173');
    });

    test('SBI institution detected', () {
      final p = parseTransactionMessage(
        'Your A/C XXXXX8910 is credited with INR 10,000.00 by SBI.',
      );
      expect(p.institutionName, 'SBI');
      expect(p.last4, '8910');
    });

    test('Chase institution detected', () {
      final p = parseTransactionMessage(
        r'Chase: A charge of $120.50 at AMAZON.COM on card ending 1234.',
      );
      expect(p.institutionName, 'Chase');
      expect(p.last4, '1234');
    });

    test('Barclays institution detected', () {
      final p = parseTransactionMessage(
        'BARCLAYS: A Direct Debit of £35.50 was paid to Vodafone UK from your account ending 5678.',
      );
      expect(p.institutionName, 'Barclays');
      expect(p.last4, '5678');
    });

    test('Monzo institution detected', () {
      final p = parseTransactionMessage(
        'Monzo: You spent £12.99 at Tesco Extra.',
      );
      expect(p.institutionName, 'Monzo');
    });

    test('Revolut institution detected', () {
      final p = parseTransactionMessage(
        'Revolut: You paid £25.00 to John Smith.',
      );
      expect(p.institutionName, 'Revolut');
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Real-world SMS samples — end-to-end last4 + institution extraction
  // ────────────────────────────────────────────────────────────────────────────

  group('Real-world SMS samples', () {
    test('Indian: Axis UPI debit with **', () {
      final p = parseTransactionMessage(
        'INR 450.00 debited from A/C **4567 on 15-May-26 to VPA shop@ybl (UPI Ref 3456789).',
      );
      expect(p.last4, '4567');
      expect(p.amount?.amountMinor, 45000);
      expect(p.transactionType, 'expense');
    });

    test('Indian: Kotak with ending in', () {
      final p = parseTransactionMessage(
        'Kotak: Rs 1200 debited from your account ending in 7890 on 20-Jun.',
      );
      expect(p.last4, '7890');
      expect(p.institutionName, 'Kotak');
      expect(p.amount?.amountMinor, 120000);
    });

    test('US: Amex charge', () {
      final p = parseTransactionMessage(
        r'Amex: A charge of $55.00 at UBER was authorized on your Card ending 4321.',
      );
      expect(p.last4, '4321');
      expect(p.institutionName, 'Amex');
      expect(p.amount?.amountMinor, 5500);
    });

    test('UK: HSBC direct debit', () {
      final p = parseTransactionMessage(
        'HSBC: £150.00 Direct Debit to Thames Water from account ending 6789 on 01 Jul.',
      );
      expect(p.last4, '6789');
      expect(p.institutionName, 'HSBC');
      expect(p.amount?.amountMinor, 15000);
    });

    test('UAE: AED cash withdrawal with card **', () {
      final p = parseTransactionMessage(
        'Cash withdrawal of AED 500.00 from ATM using Card **9999. Available Balance: AED 1500.00',
      );
      expect(p.last4, '9999');
      expect(p.amount?.amountMinor, 50000);
      expect(p.amount?.currency, 'AED');
    });

    test('Indian: HDFC credit card with xxxx', () {
      final p = parseTransactionMessage(
        'Alert: Rs.2500.00 spent on HDFC Bank Credit Card xxxx3456 at FLIPKART on 22-Jun.',
      );
      expect(p.last4, '3456');
      expect(p.institutionName, 'HDFC');
      expect(p.amount?.amountMinor, 250000);
    });

    test('Indian: SBI salary credit with XXXXX', () {
      final p = parseTransactionMessage(
        'Dear Customer, your A/C XXXXX4321 has been credited with Rs.85000.00 on 01-Jul (NEFT/Salary).',
      );
      expect(p.last4, '4321');
      expect(p.amount?.amountMinor, 8500000);
      expect(p.transactionType, 'income');
    });

    test('Indian: IndusInd with account no', () {
      final p = parseTransactionMessage(
        'IndusInd Bank: INR 750.00 debited from Account No XX5678 to Amazon Pay.',
      );
      expect(p.last4, '5678');
      expect(p.institutionName, 'IndusInd');
      expect(p.amount?.amountMinor, 75000);
    });

    test('US: Wells Fargo with dots masking', () {
      final p = parseTransactionMessage(
        r'Wells Fargo: $200.00 purchase at Target on card ...1111.',
      );
      expect(p.last4, '1111');
      expect(p.institutionName, 'Wells Fargo');
      expect(p.amount?.amountMinor, 20000);
    });

    test('Indian: PhonePe UPI (no card number)', () {
      final p = parseTransactionMessage(
        'PhonePe: Rs 99.00 paid to Netflix via UPI.',
      );
      expect(p.institutionName, 'PhonePe');
      expect(p.amount?.amountMinor, 9900);
      expect(p.last4, isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Edge cases
  // ────────────────────────────────────────────────────────────────────────────

  group('Edge cases', () {
    test('OTP message ignored', () {
      final p = parseTransactionMessage('Your OTP is 123456. Do not share it.');
      expect(p.ignored, isTrue);
    });

    test('Promotional message ignored', () {
      final p = parseTransactionMessage(
        'Exclusive offer! Get up to 50% off on your next order. Shop now at BigBazaar. T&C apply.',
      );
      expect(p.ignored, isTrue);
    });

    test('SMS with no amount is ignored', () {
      final p = parseTransactionMessage(
        'Your card ending 1234 has been activated.',
      );
      expect(p.ignored, isTrue);
    });

    test('Multiple digit sequences — primary last4 wins', () {
      final p = parseTransactionMessage(
        'ICICI Bank Acct XX173 debited for Rs 5059.00 on 15-Jun-26. Call 18002662.',
      );
      expect(p.last4, '173');
    });

    test('Case insensitivity in extraction', () {
      final p = parseTransactionMessage(
        'rs 500 DEBITED FROM CARD xx1234.',
      );
      expect(p.last4, '1234');
    });
  });
}
