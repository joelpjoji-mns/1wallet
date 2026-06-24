import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.decimalPattern();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Keep only numbers and decimal points
    final numericString = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');

    // Prevent multiple decimal points
    if (numericString.indexOf('.') != numericString.lastIndexOf('.')) {
      return oldValue;
    }

    final parts = numericString.split('.');
    String formattedText = parts[0].isEmpty
        ? ''
        : _formatter.format(int.parse(parts[0]));

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
  return expr.replaceAllMapped(RegExp(r'\d+(\.\d+)?'), (match) {
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
