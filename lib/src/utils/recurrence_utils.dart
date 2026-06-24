import '../data/ledger_models.dart';

DateTime _addMonths(DateTime date, int months) {
  var year = date.year;
  var month = date.month + months;
  while (month > 12) {
    year++;
    month -= 12;
  }
  while (month < 1) {
    year--;
    month += 12;
  }
  var day = date.day;
  final daysInNextMonth = DateTime(year, month + 1, 0).day;
  if (day > daysInNextMonth) {
    day = daysInNextMonth;
  }
  return DateTime(year, month, day, date.hour, date.minute, date.second);
}

DateTime advanceRecurrenceCursor({
  required DateTime current,
  required String frequency,
  int interval = 1,
  List<int>? daysOfWeek,
  List<int>? daysOfMonth,
}) {
  final freq = frequency.toLowerCase();
  if (interval < 1) interval = 1;

  if (freq == 'daily') {
    return current.add(Duration(days: interval));
  }

  if (freq == 'weekly') {
    if (daysOfWeek != null && daysOfWeek.isNotEmpty) {
      final sortedDays = List<int>.from(daysOfWeek)..sort();
      final currentWeekday = current.weekday;

      // Look for the next day in the SAME week
      for (final day in sortedDays) {
        if (day > currentWeekday) {
          return current.add(Duration(days: day - currentWeekday));
        }
      }

      // If none found in this week, jump to the first day in the NEXT interval week
      final daysToNextWeekMonday = 8 - currentWeekday; // jump to next Monday
      final jumpToIntervalWeek = daysToNextWeekMonday + ((interval - 1) * 7);

      // The first selected day in that target week
      final targetDay = sortedDays.first;
      return current.add(Duration(days: jumpToIntervalWeek + (targetDay - 1)));
    } else {
      return current.add(Duration(days: 7 * interval));
    }
  }

  if (freq == 'monthly') {
    if (daysOfMonth != null && daysOfMonth.isNotEmpty) {
      final sortedDays = List<int>.from(daysOfMonth)..sort();
      final currentDay = current.day;

      // Look for the next day in the SAME month
      for (final day in sortedDays) {
        if (day > currentDay) {
          // ensure the day exists in the current month (e.g. Feb 30 -> Feb 28)
          final maxDay = DateTime(current.year, current.month + 1, 0).day;
          final safeDay = day > maxDay ? maxDay : day;
          if (safeDay > currentDay) {
            return DateTime(
              current.year,
              current.month,
              safeDay,
              current.hour,
              current.minute,
              current.second,
            );
          }
        }
      }

      // If none found, jump to the next interval month
      final nextMonthDate = _addMonths(current, interval);
      final targetDay = sortedDays.first;
      final maxDayNextMonth = DateTime(
        nextMonthDate.year,
        nextMonthDate.month + 1,
        0,
      ).day;
      final safeDay = targetDay > maxDayNextMonth ? maxDayNextMonth : targetDay;

      return DateTime(
        nextMonthDate.year,
        nextMonthDate.month,
        safeDay,
        current.hour,
        current.minute,
        current.second,
      );
    } else {
      return _addMonths(current, interval);
    }
  }

  if (freq == 'yearly') {
    return _addMonths(current, 12 * interval);
  }

  return _addMonths(current, interval);
}

DateTime advanceTransactionRecurrence(
  DateTime current,
  TransactionRecord record,
) {
  return advanceRecurrenceCursor(
    current: current,
    frequency: record.recurrenceFrequency ?? 'monthly',
    interval: record.recurrenceInterval ?? 1,
    daysOfWeek: record.recurrenceDaysOfWeek,
    daysOfMonth: record.recurrenceDaysOfMonth,
  );
}
