import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats a custom date range as a persistent storage key (e.g. `custom:2026-11-01..2026-11-15`).
String formatCustomDateRangeKey(DateTimeRange range) {
  final startStr = DateFormat('yyyy-MM-dd').format(range.start);
  final endStr = DateFormat('yyyy-MM-dd').format(range.end);
  return 'custom:$startStr..$endStr';
}

/// Parses a date range key into a [DateTimeRange].
/// Supports formats:
/// - `custom:2026-11-01..2026-11-15`
/// - `custom:2026-11-01:2026-11-15`
/// - `custom:2026-11-01_2026-11-15`
DateTimeRange? parseCustomDateRange(String period) {
  if (!period.startsWith('custom:') && !period.startsWith('Custom:')) {
    return null;
  }
  final payload = period.substring(7).trim();
  final separator = payload.contains('..')
      ? '..'
      : (payload.contains('_') ? '_' : ':');
  final parts = payload.split(separator);
  if (parts.length >= 2) {
    final start = DateTime.tryParse(parts[0].trim());
    final end = DateTime.tryParse(parts[1].trim());
    if (start != null && end != null) {
      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day);
      return DateTimeRange(start: s, end: e);
    }
  }
  return null;
}

/// Formats a custom range string into a friendly UI label, e.g. "Nov 1 – Nov 15, 2026".
String formatCustomDateRangeLabel(String period) {
  final range = parseCustomDateRange(period);
  if (range == null) return 'Custom range';
  final s = range.start;
  final e = range.end;
  if (s.year == e.year) {
    if (s.month == e.month && s.day == e.day) {
      return DateFormat('MMM d, yyyy').format(s);
    }
    return '${DateFormat('MMM d').format(s)} – ${DateFormat('MMM d, yyyy').format(e)}';
  }
  return '${DateFormat('MMM d, yyyy').format(s)} – ${DateFormat('MMM d, yyyy').format(e)}';
}

/// Prompts the user to pick a custom date range using Flutter's [showDateRangePicker].
Future<DateTimeRange?> promptCustomDateRange(
  BuildContext context, {
  DateTimeRange? initialRange,
  String? helpText,
}) async {
  return await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDateRange: initialRange,
    helpText: helpText ?? 'Select date range',
  );
}
