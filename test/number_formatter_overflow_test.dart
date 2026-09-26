// Regression test for lib/src/utils/number_formatter.dart.
//
// Bug: both `ThousandsSeparatorInputFormatter.formatEditUpdate` and
// `formatNumberExpression` called `int.parse(parts[0])` on the digits typed
// so far with no bound on length. Once the integer part exceeds the 64-bit
// range (~19+ digits — reachable from a single paste, fast typing, or a
// misread OCR/SMS-imported amount feeding one of these amount fields),
// `int.parse` throws an uncaught `FormatException` synchronously inside
// Flutter's text-editing pipeline (a `TextInputFormatter` runs on every
// keystroke) instead of gracefully rejecting/ignoring the offending input.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/utils/number_formatter.dart';

void main() {
  group('ThousandsSeparatorInputFormatter', () {
    final formatter = ThousandsSeparatorInputFormatter();

    TextEditingValue format(String text) {
      return formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
    }

    test('formats a normal amount with grouping separators', () {
      expect(format('12345').text, '12,345');
    });

    test(
      'an integer part beyond the 64-bit range does not throw and rejects '
      'the edit instead of crashing',
      () {
        final huge = '9' * 25;
        expect(() => format(huge), returnsNormally);
        // Falls back to `oldValue` (empty), same as the existing
        // multiple-decimal-points guard does for other invalid input.
        expect(format(huge).text, '');
      },
    );

    test(
      'a merely large but valid amount still formats normally at the '
      'boundary of what a wallet amount could plausibly be',
      () {
        expect(format('999999999999').text, '999,999,999,999');
      },
    );
  });

  group('formatNumberExpression', () {
    test('formats numbers inside an expression with grouping separators', () {
      expect(formatNumberExpression('1000+2000', 'en_US'), '1,000+2,000');
    });

    test(
      'a number beyond the 64-bit range inside an expression does not '
      'throw and is left unformatted instead of breaking the whole '
      'expression',
      () {
        final huge = '9' * 25;
        expect(
          () => formatNumberExpression('$huge+500', 'en_US'),
          returnsNormally,
        );
        expect(formatNumberExpression('$huge+500', 'en_US'), '$huge+500');
      },
    );
  });
}
