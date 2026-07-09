import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _nonNumericPattern = RegExp(r'[^0-9.]');
final _numberPattern = RegExp(r'\d+(\.\d+)?');

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final String? locale;

  ThousandsSeparatorInputFormatter([this.locale]);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Keep only numbers and decimal points
    final numericString = newValue.text.replaceAll(_nonNumericPattern, '');

    // Prevent multiple decimal points
    if (numericString.indexOf('.') != numericString.lastIndexOf('.')) {
      return oldValue;
    }

    final formatter = NumberFormat.decimalPattern(locale);

    final parts = numericString.split('.');
    String formattedText = parts[0].isEmpty
        ? ''
        : formatter.format(int.parse(parts[0]));

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

String formatNumberExpression(String expr, String locale) {
  if (expr.isEmpty) return expr;

  final formatter = NumberFormat.decimalPattern(locale);
  // Match numbers that might have decimals
  return expr.replaceAllMapped(_numberPattern, (match) {
    final numericString = match.group(0)!;
    final parts = numericString.split('.');
    String formattedText = formatter.format(int.parse(parts[0]));
    if (parts.length > 1) {
      formattedText += '.${parts[1]}';
    } else if (numericString.endsWith('.')) {
      formattedText += '.';
    }
    return formattedText;
  });
}
