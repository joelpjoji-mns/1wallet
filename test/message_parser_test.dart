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
    expect(parsed.warnings, isEmpty);
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
    expect(parsed.warnings.single, contains('Ignored'));
  });
}
