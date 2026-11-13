import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

void main() {
  group('i18n & Locale-Correct Financial Formatting', () {
    String formatMoneyWithLocale({
      required Money money,
      required String locale,
      int decimals = 2,
    }) {
      final sign = money.amountMinor < 0 ? '-' : '';
      final absMinor = money.amountMinor.abs();

      var factor = 1;
      for (var i = 0; i < decimals; i++) {
        factor *= 10;
      }

      final major = absMinor ~/ factor;
      final minorPart = absMinor % factor;

      // Locale-specific integer grouping
      final formatter = NumberFormat.decimalPattern(locale);
      final formattedMajor = formatter.format(major);
      final decimalSeparator =
          locale.startsWith('de') || locale.startsWith('fr') ? ',' : '.';
      final formattedMinor = minorPart.toString().padLeft(decimals, '0');

      return '$sign$formattedMajor$decimalSeparator$formattedMinor';
    }

    test('formats USD in en_US locale with standard commas and period', () {
      const money = Money(
        amountMinor: 12345678,
        currency: 'USD',
      ); // $123,456.78
      final formatted = formatMoneyWithLocale(money: money, locale: 'en_US');

      expect(formatted, equals('123,456.78'));
    });

    test(
      'formats EUR in de_DE locale with dots for thousands and comma for decimals',
      () {
        const money = Money(
          amountMinor: 12345678,
          currency: 'EUR',
        ); // 123.456,78 €
        final formatted = formatMoneyWithLocale(money: money, locale: 'de_DE');

        expect(formatted, equals('123.456,78'));
      },
    );

    test(
      'formats INR in en_IN locale using Indian numbering system grouping (lakhs/crores)',
      () {
        const money = Money(
          amountMinor: 12345678,
          currency: 'INR',
        ); // ₹1,23,456.78
        final formatted = formatMoneyWithLocale(money: money, locale: 'en_IN');

        expect(formatted, equals('1,23,456.78'));
      },
    );

    test('handles exact negative minor amounts across locales', () {
      const money = Money(amountMinor: -45000, currency: 'USD'); // -$450.00
      final us = formatMoneyWithLocale(money: money, locale: 'en_US');
      final de = formatMoneyWithLocale(money: money, locale: 'de_DE');

      expect(us, equals('-450.00'));
      expect(de, equals('-450,00'));
    });

    test(
      'never loses precision on small or fractional minor unit balances',
      () {
        const cents = Money(amountMinor: 5, currency: 'USD'); // $0.05
        final formatted = formatMoneyWithLocale(money: cents, locale: 'en_US');

        expect(formatted, equals('0.05'));
      },
    );
  });
}
