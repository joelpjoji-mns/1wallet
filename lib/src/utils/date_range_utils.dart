import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats a custom date range as a persistent storage key (e.g. `custom:2026-11-01..2026-11-15`).
String formatCustomDateRangeKey(DateTimeRange range) {
  final startStr = DateFormat('yyyy-MM-dd').format(range.start);
  final endStr = DateFormat('yyyy-MM-dd').format(range.end);
  return 'custom:$startStr..$endStr';
}

/// Safely adds or subtracts calendar days without DST shifts.
DateTime addCalendarDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

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

/// Formats a custom range string into a friendly UI label, e.g. "Last week", "Last month", "Yesterday", "Nov 1 – Nov 15, 2026".
String formatCustomDateRangeLabel(String period, {DateTime? now}) {
  final range = parseCustomDateRange(period);
  if (range == null) return 'Custom range';
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final s = range.start;
  final e = range.end;

  // Check 1-day ranges
  if (s.year == e.year && s.month == e.month && s.day == e.day) {
    if (s.year == today.year && s.month == today.month && s.day == today.day) {
      return 'Today';
    }
    final yesterday = addCalendarDays(today, -1);
    if (s.year == yesterday.year && s.month == yesterday.month && s.day == yesterday.day) {
      return 'Yesterday';
    }
    final tomorrow = addCalendarDays(today, 1);
    if (s.year == tomorrow.year && s.month == tomorrow.month && s.day == tomorrow.day) {
      return 'Tomorrow';
    }
    if (s.year == current.year) {
      return DateFormat('MMM d').format(s);
    }
    return DateFormat('MMM d, yyyy').format(s);
  }

  // Check week ranges (7 days, starts on Monday)
  final diff = current.weekday - 1;
  final thisWeekStart = addCalendarDays(today, -diff);
  final thisWeekEnd = addCalendarDays(thisWeekStart, 6);
  final lastWeekStart = addCalendarDays(thisWeekStart, -7);
  final lastWeekEnd = addCalendarDays(lastWeekStart, 6);

  if (s.year == thisWeekStart.year &&
      s.month == thisWeekStart.month &&
      s.day == thisWeekStart.day &&
      e.year == thisWeekEnd.year &&
      e.month == thisWeekEnd.month &&
      e.day == thisWeekEnd.day) {
    return 'This week';
  }
  if (s.year == lastWeekStart.year &&
      s.month == lastWeekStart.month &&
      s.day == lastWeekStart.day &&
      e.year == lastWeekEnd.year &&
      e.month == lastWeekEnd.month &&
      e.day == lastWeekEnd.day) {
    return 'Last week';
  }

  // Check full month ranges
  final isFirstOfMonth = s.day == 1;
  final nextDay = addCalendarDays(e, 1);
  final isEndOfMonth = nextDay.day == 1;
  if (isFirstOfMonth && isEndOfMonth && s.year == e.year && s.month == e.month) {
    if (s.year == current.year && s.month == current.month) {
      return 'This month';
    }
    final lastMonth = DateTime(current.year, current.month - 1, 1);
    if (s.year == lastMonth.year && s.month == lastMonth.month) {
      return 'Last month';
    }
    if (s.year == current.year) {
      return DateFormat('MMMM').format(s);
    }
    return DateFormat('MMM yyyy').format(s);
  }

  // Check full year ranges
  if (s.day == 1 && s.month == 1 && e.month == 12 && e.day == 31 && s.year == e.year) {
    if (s.year == current.year) return 'This year';
    if (s.year == current.year - 1) return 'Last year';
    return '${s.year}';
  }

  if (s.year == e.year) {
    return '${DateFormat('MMM d').format(s)} – ${DateFormat('MMM d, yyyy').format(e)}';
  }
  return '${DateFormat('MMM d, yyyy').format(s)} – ${DateFormat('MMM d, yyyy').format(e)}';
}

/// Shifts a date filter key backward (direction = -1) or forward (direction = 1) in time.
String shiftDateFilter(String currentFilter, int direction, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dir = direction >= 0 ? 1 : -1;

  final isTitle = currentFilter.isNotEmpty &&
      currentFilter[0] == currentFilter[0].toUpperCase() &&
      !currentFilter.startsWith('custom:') &&
      !currentFilter.startsWith('Custom:');
  final isCamel = !isTitle &&
      (currentFilter == 'thisWeek' ||
          currentFilter == 'thisMonth' ||
          currentFilter == '30Days' ||
          currentFilter == '6Months' ||
          currentFilter == 'thisYear' ||
          currentFilter == 'allTime');

  String formatPreset({
    required String snake,
    required String title,
    required String camel,
  }) {
    if (isTitle) return title;
    if (isCamel) return camel;
    return snake;
  }

  // Preserves 'all' if caller explicitly invokes with all
  if (currentFilter == 'all' ||
      currentFilter == 'allTime' ||
      currentFilter == 'All time') {
    return currentFilter;
  }

  // 1. Today / 1-day range
  if (currentFilter == 'today' || currentFilter == 'Today') {
    final target = addCalendarDays(today, dir);
    if (target.year == today.year && target.month == today.month && target.day == today.day) {
      return formatPreset(snake: 'today', title: 'Today', camel: 'today');
    }
    return formatCustomDateRangeKey(DateTimeRange(start: target, end: target));
  }

  // 2. This week / Week range
  final weekdayDiff = current.weekday - 1;
  final thisWeekStart = addCalendarDays(today, -weekdayDiff);

  if (currentFilter == 'this_week' || currentFilter == 'thisWeek' || currentFilter == 'This week') {
    final start = addCalendarDays(thisWeekStart, dir * 7);
    final end = addCalendarDays(start, 6);
    if (start.year == thisWeekStart.year &&
        start.month == thisWeekStart.month &&
        start.day == thisWeekStart.day) {
      return formatPreset(snake: 'this_week', title: 'This week', camel: 'thisWeek');
    }
    return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
  }

  // 3. This month / Month range
  if (currentFilter == 'this_month' || currentFilter == 'thisMonth' || currentFilter == 'This month') {
    final start = DateTime(current.year, current.month + dir, 1);
    final end = DateTime(start.year, start.month + 1, 0);
    if (start.year == current.year && start.month == current.month) {
      return formatPreset(snake: 'this_month', title: 'This month', camel: 'thisMonth');
    }
    return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
  }

  // 4. Last month
  if (currentFilter == 'last_month' || currentFilter == 'lastMonth' || currentFilter == 'Last month') {
    final start = DateTime(current.year, current.month - 1 + dir, 1);
    final end = DateTime(start.year, start.month + 1, 0);
    if (start.year == current.year && start.month == current.month) {
      return formatPreset(snake: 'this_month', title: 'This month', camel: 'thisMonth');
    }
    return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
  }

  // 5. 30 days
  if (currentFilter == '30_days' || currentFilter == '30Days' || currentFilter == '30 days' || currentFilter == 'last_30_days') {
    if (dir < 0) {
      final end = addCalendarDays(today, -30);
      final start = addCalendarDays(end, -29);
      return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
    } else {
      final start = addCalendarDays(today, 1);
      final end = addCalendarDays(start, 29);
      return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
    }
  }

  // 6. 6 months
  if (currentFilter == '6_months' || currentFilter == '6Months' || currentFilter == '6 months') {
    if (dir < 0) {
      final end = DateTime(current.year, current.month - 6, current.day);
      final start = DateTime(end.year, end.month - 6, end.day);
      return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
    } else {
      final start = DateTime(current.year, current.month + 6, current.day);
      final end = DateTime(start.year, start.month + 6, start.day);
      return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
    }
  }

  // 7. This year
  if (currentFilter == 'this_year' || currentFilter == 'thisYear' || currentFilter == 'This year') {
    final start = DateTime(current.year + dir, 1, 1);
    final end = DateTime(start.year, 12, 31);
    if (start.year == current.year) {
      return formatPreset(snake: 'this_year', title: 'This year', camel: 'thisYear');
    }
    return formatCustomDateRangeKey(DateTimeRange(start: start, end: end));
  }

  // 8. Custom date range
  final parsed = parseCustomDateRange(currentFilter);
  if (parsed != null) {
    final s = parsed.start;
    final e = parsed.end;

    // Check if it's a 1-day range
    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      final next = addCalendarDays(s, dir);
      if (next.year == today.year && next.month == today.month && next.day == today.day) {
        return 'today';
      }
      return formatCustomDateRangeKey(DateTimeRange(start: next, end: next));
    }

    // Check if it's a 7-day week range (calendar days difference = 6)
    final daySpan = addCalendarDays(e, 1).difference(s).inDays;
    if (daySpan == 7) {
      final nextStart = addCalendarDays(s, dir * 7);
      final nextEnd = addCalendarDays(nextStart, 6);
      if (nextStart.year == thisWeekStart.year &&
          nextStart.month == thisWeekStart.month &&
          nextStart.day == thisWeekStart.day) {
        return 'this_week';
      }
      return formatCustomDateRangeKey(DateTimeRange(start: nextStart, end: nextEnd));
    }

    // Check if it's a full calendar month (1st to last day of month)
    final isFirstOfMonth = s.day == 1;
    final isEndOfMonth = addCalendarDays(e, 1).day == 1;
    if (isFirstOfMonth && isEndOfMonth && s.year == e.year && s.month == e.month) {
      final nextStart = DateTime(s.year, s.month + dir, 1);
      final nextEnd = DateTime(nextStart.year, nextStart.month + 1, 0);
      if (nextStart.year == current.year && nextStart.month == current.month) return 'this_month';
      return formatCustomDateRangeKey(DateTimeRange(start: nextStart, end: nextEnd));
    }

    // Check if it's a 30-day range
    if (daySpan == 30) {
      final nextStart = addCalendarDays(s, dir * 30);
      final nextEnd = addCalendarDays(e, dir * 30);
      if (nextEnd.year == today.year && nextEnd.month == today.month && nextEnd.day == today.day) {
        return '30_days';
      }
      return formatCustomDateRangeKey(DateTimeRange(start: nextStart, end: nextEnd));
    }

    // Check if it's a full calendar year
    if (s.day == 1 && s.month == 1 && e.month == 12 && e.day == 31 && s.year == e.year) {
      final nextStart = DateTime(s.year + dir, 1, 1);
      final nextEnd = DateTime(nextStart.year, 12, 31);
      if (nextStart.year == current.year) return 'this_year';
      return formatCustomDateRangeKey(DateTimeRange(start: nextStart, end: nextEnd));
    }

    // General span
    final nextStart = addCalendarDays(s, dir * daySpan);
    final nextEnd = addCalendarDays(e, dir * daySpan);
    return formatCustomDateRangeKey(DateTimeRange(start: nextStart, end: nextEnd));
  }

  return currentFilter;
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
