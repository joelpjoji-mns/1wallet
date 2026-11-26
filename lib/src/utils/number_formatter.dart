import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _nonNumericPattern = RegExp(r'[^0-9.]');
final _numberPattern = RegExp(r'\d+(\.\d+)?');

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final String? locale;
  final bool allowNegative;

  ThousandsSeparatorInputFormatter([this.locale]) : allowNegative = false;

  ThousandsSeparatorInputFormatter.signed([this.locale]) : allowNegative = true;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    if (allowNegative &&
        (newValue.text.indexOf('-', 1) != -1 ||
            (newValue.text.contains('-') && !newValue.text.startsWith('-')))) {
      return oldValue;
    }
    final sign = allowNegative && newValue.text.startsWith('-') ? '-' : '';

    // Keep only numbers and decimal points
    final numericString = newValue.text.replaceAll(_nonNumericPattern, '');

    // Prevent multiple decimal points
    if (numericString.indexOf('.') != numericString.lastIndexOf('.')) {
      return oldValue;
    }

    final formatter = NumberFormat.decimalPattern(locale);

    final parts = numericString.split('.');
    // `int.parse` throws `FormatException` once the digit string exceeds
    // the 64-bit integer range (e.g. a stray long paste, or ~19+ digits
    // typed quickly) — an uncaught throw here happens synchronously inside
    // Flutter's text-editing pipeline on every keystroke, so it would take
    // down the whole edit instead of just rejecting the change. Reject the
    // edit (like the "multiple decimal points" guard above) instead of
    // crashing when the integer part is unparseable.
    final integerValue = parts[0].isEmpty ? 0 : int.tryParse(parts[0]);
    if (integerValue == null) {
      return oldValue;
    }
    String formattedText =
        sign + (parts[0].isEmpty ? '' : formatter.format(integerValue));

    if (parts.length > 1) {
      formattedText += '.${parts[1]}';
    } else if (numericString.endsWith('.')) {
      formattedText += '.';
    }

    // Calculate new cursor position
    int selectionIndex =
        formattedText.length - (newValue.text.length - newValue.selection.end);

    // Safety bounds for cursor
    if (selectionIndex < 0) {
      selectionIndex = 0;
    } else if (selectionIndex > formattedText.length) {
      selectionIndex = formattedText.length;
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}

/// Parses a grouped, optionally signed decimal amount without floating point.
/// Extra fractional digits round to the nearest minor unit, away from zero.
int? parseDecimalMinorUnits(String input, int fractionDigits) {
  if (fractionDigits < 0) {
    throw RangeError.range(fractionDigits, 0, null, 'fractionDigits');
  }
  final clean = input.trim().replaceAll(',', '');
  if (clean.isEmpty) return 0;
  if (!RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(clean)) return null;

  final negative = clean.startsWith('-');
  final parts = (negative ? clean.substring(1) : clean).split('.');
  final whole = parts.first.isEmpty ? '0' : parts.first;
  final fraction = parts.length == 1 ? '' : parts[1];
  final minorDigits = fraction
      .padRight(fractionDigits, '0')
      .substring(0, fractionDigits);
  var amount = BigInt.parse('$whole$minorDigits');
  if (fraction.length > fractionDigits &&
      fraction.codeUnitAt(fractionDigits) >= 0x35) {
    amount += BigInt.one;
  }

  // The same exact integer must survive JSON and Flutter web serialization.
  if (amount > BigInt.from(9007199254740991)) return null;
  final result = amount.toInt();
  return negative ? -result : result;
}

String formatNumberExpression(String expr, String locale) {
  if (expr.isEmpty) return expr;

  final formatter = NumberFormat.decimalPattern(locale);
  // Match numbers that might have decimals
  return expr.replaceAllMapped(_numberPattern, (match) {
    final numericString = match.group(0)!;
    final parts = numericString.split('.');
    // See the matching guard in `ThousandsSeparatorInputFormatter` above:
    // `int.parse` throws once the integer part exceeds the 64-bit range.
    // This runs per-match inside a calculator-style expression, so leave
    // that one unparseable number as-is rather than throwing and breaking
    // formatting for the rest of the expression.
    final integerValue = int.tryParse(parts[0]);
    if (integerValue == null) {
      return numericString;
    }
    String formattedText = formatter.format(integerValue);
    if (parts.length > 1) {
      formattedText += '.${parts[1]}';
    } else if (numericString.endsWith('.')) {
      formattedText += '.';
    }
    return formattedText;
  });
}
