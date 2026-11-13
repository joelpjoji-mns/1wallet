import 'package:test/test.dart';
import 'package:one_wallet_money/one_wallet_money.dart';

void main() {
  group('Money Invariants & Integer Minor Units', () {
    test('constructs from integer minor units with exact representation', () {
      const money = Money(amountMinor: 1050, currency: 'USD');
      expect(money.amountMinor, equals(1050));
      expect(money.currency, equals('USD'));
      expect(money.toDecimalString(), equals('10.50'));
    });

    test('performs integer addition and subtraction without floating-point error', () {
      const a = Money(amountMinor: 1000, currency: 'USD');
      const b = Money(amountMinor: 250, currency: 'USD');

      final sum = a.add(b);
      final diff = a.subtract(b);

      expect(sum.amountMinor, equals(1250));
      expect(diff.amountMinor, equals(750));
      expect(sum.toDecimalString(), equals('12.50'));
      expect(diff.toDecimalString(), equals('7.50'));
    });

    test('handles negative money correctly in integer arithmetic', () {
      const negative = Money(amountMinor: -4550, currency: 'EUR');
      expect(negative.isNegative, isTrue);
      expect(negative.isPositive, isFalse);
      expect(negative.toDecimalString(), equals('-45.50'));
      expect(negative.negate().amountMinor, equals(4550));
    });

    test('throws ArgumentError on mismatched currency operations', () {
      const usd = Money(amountMinor: 1000, currency: 'USD');
      const eur = Money(amountMinor: 1000, currency: 'EUR');

      expect(() => usd.add(eur), throwsArgumentError);
      expect(() => usd.subtract(eur), throwsArgumentError);
    });

    test('toDecimalString formats small minor values with leading zeros', () {
      const cents = Money(amountMinor: 5, currency: 'USD');
      expect(cents.toDecimalString(), equals('0.05'));

      const zero = Money(amountMinor: 0, currency: 'USD');
      expect(zero.toDecimalString(), equals('0.00'));
      expect(zero.isZero, isTrue);
    });
  });
}
