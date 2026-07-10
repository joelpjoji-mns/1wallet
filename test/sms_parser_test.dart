import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';

void main() {
  group('parseTransactionMessage accept rule', () {
    test('accepts a real debit SMS', () {
      final parsed = parseTransactionMessage(
        'Rs.500 debited from a/c XX1234 at AMAZON on 01-01-24. Avl Bal Rs.2000',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isFalse);
      expect(parsed.amount?.amountMinor, 50000);
      expect(parsed.transactionType, 'expense');
    });

    test('accepts a credit SMS as income', () {
      final parsed = parseTransactionMessage(
        'INR 1,200.00 credited to your account via UPI Ref 123.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isFalse);
      expect(parsed.transactionType, 'income');
    });

    test('ignores OTP / security messages', () {
      final parsed = parseTransactionMessage(
        'Your OTP is 123456 for a payment of Rs.999. Do not share.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isTrue);
    });

    test('ignores promotional offers even with an amount', () {
      final parsed = parseTransactionMessage(
        'Special offer! Spend Rs.999 and get cashback. Sale ends soon.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isTrue);
    });

    test('ignores future / mandate notices ("will be debited")', () {
      final parsed = parseTransactionMessage(
        'Rs.5000 will be debited for your SIP on 05-01-24.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isTrue);
    });

    test('ignores payment requests', () {
      final parsed = parseTransactionMessage(
        'Payment request of Rs.300 received from john@upi. Approve now.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isTrue);
    });

    test('ignores a trigger word with no amount', () {
      final parsed = parseTransactionMessage(
        'Transaction alert on your card ending 5678.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isTrue);
    });

    test('ignores an amount with no trigger word', () {
      final parsed = parseTransactionMessage(
        'Your account statement for Rs.1000 is ready to view.',
        fallbackCurrency: 'INR',
      );
      expect(parsed.ignored, isTrue);
    });

    test('respects custom trigger and ignore lists', () {
      final accepted = parseTransactionMessage(
        'promo code redeemed Rs.100',
        fallbackCurrency: 'INR',
        triggerWords: const ['redeemed'],
        ignoreWords: const [],
      );
      expect(accepted.ignored, isFalse);

      final blocked = parseTransactionMessage(
        'promo code redeemed Rs.100',
        fallbackCurrency: 'INR',
        triggerWords: const ['redeemed'],
        ignoreWords: const ['promo'],
      );
      expect(blocked.ignored, isTrue);
    });

    test('smsLooksLikeTransaction mirrors the parser', () {
      expect(
        smsLooksLikeTransaction('Rs.500 spent at CAFE via UPI'),
        isTrue,
      );
      expect(
        smsLooksLikeTransaction('Your OTP is 4321'),
        isFalse,
      );
    });
  });
}
