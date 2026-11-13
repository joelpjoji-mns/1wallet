import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/capture/message_parser.dart';

void main() {
  test('parses debit SMS amount merchant and type', () {
    final parsed = parseTransactionMessage(
      'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on 08-Jun.',
    );

    expect(parsed.ignored, isFalse);
    expect(parsed.amount?.amountMinor, 89000);
    expect(parsed.amount?.currency, 'INR');
    expect(parsed.merchant, 'SWIGGY');
    expect(parsed.transactionType, 'expense');
  });

  test('parses credited SMS as income', () {
    final parsed = parseTransactionMessage(
      'Salary credited INR 185000.00 from ACME PRIVATE LIMITED.',
    );

    expect(parsed.ignored, isFalse);
    expect(parsed.amount?.amountMinor, 18500000);
    expect(parsed.transactionType, 'income');
  });

  test('ignores OTP and security messages', () {
    final parsed = parseTransactionMessage(
      'Your OTP is 123456. Do not share it.',
    );

    expect(parsed.ignored, isTrue);
  });

  test('parses Indian bank SMS with exact timestamp 03-11-26, 23:22:06', () {
    const raw = '''INR 30000.00 debited
A/c no. XX0655
03-11-26, 23:22:06''';
    final parsed = parseTransactionMessage(raw);

    expect(parsed.ignored, isFalse);
    expect(parsed.amount?.amountMinor, 3000000);
    expect(parsed.amount?.currency, 'INR');
    expect(parsed.transactionDate, isNotNull);
    expect(parsed.transactionDate?.year, 2026);
    expect(parsed.transactionDate?.month, 11);
    expect(parsed.transactionDate?.day, 3);
    expect(parsed.transactionDate?.hour, 23);
    expect(parsed.transactionDate?.minute, 22);
    expect(parsed.transactionDate?.second, 6);
  });

  test('extracts MUTUAL FUNDS ICCL merchant instead of "to"', () {
    const raw = '''Sent Rs.30000.00
From HDFC Bank A/C *2906
To MUTUAL FUNDS ICCL''';
    final parsed = parseTransactionMessage(raw);

    expect(parsed.ignored, isFalse);
    expect(parsed.amount?.amountMinor, 3000000);
    expect(parsed.merchant, 'MUTUAL FUNDS ICCL');
  });

  test(
    'extractTransactionDateTime handles 12-hour AM/PM and other date formats',
    () {
      final dt1 = extractTransactionDateTime(
        'Debited \$50 on 15/04/2026 at 02:30 PM',
      );
      expect(dt1, isNotNull);
      expect(dt1?.year, 2026);
      expect(dt1?.month, 4);
      expect(dt1?.day, 15);
      expect(dt1?.hour, 14);
      expect(dt1?.minute, 30);

      final dt2 = extractTransactionDateTime(
        'Paid EUR 10 at 10:15 on 2026-08-20',
      );
      expect(dt2, isNotNull);
      expect(dt2?.year, 2026);
      expect(dt2?.month, 8);
      expect(dt2?.day, 20);
      expect(dt2?.hour, 10);
      expect(dt2?.minute, 15);
    },
  );
}
