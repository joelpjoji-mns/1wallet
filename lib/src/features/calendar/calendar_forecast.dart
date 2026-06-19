import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';


List<TransactionRecord> forecastRecurringTransactions(
  LedgerState state,
  DateTime horizonStart,
  DateTime horizonEnd,
) {
  final occurrences = <TransactionRecord>[];
  
  // Find all scheduled transactions from recurring templates
  final templates = state.transactions.where((tx) =>
      tx.status == 'scheduled' && tx.source == 'recurring' && tx.status != 'void');
  
  for (final template in templates) {
    final frequency = template.recurrenceFrequency ?? 'monthly';
    
    var cursor = template.occurredAt;
    
    // We only want future occurrences that are NOT already covered by the actual 'scheduled' template
    // Actually, the template itself IS the next occurrence in Flutter's data model.
    // So the template should be considered as an occurrence!
    // But since `calendar_screen.dart` filters by `transaction.status == 'void'` inside `_summariesByDay`, 
    // it will naturally INCLUDE the 'scheduled' transaction if we don't skip it.
    // Wait, `_filteredTransactions` might include the 'scheduled' ones? 
    // Let's look at `calendar_screen.dart`: it iterates `_filteredTransactions(state)`.
    
    int count = 0;
    while (cursor.isBefore(horizonEnd) || cursor.isAtSameMomentAs(horizonEnd)) {
      if (cursor.isAfter(horizonStart) || cursor.isAtSameMomentAs(horizonStart)) {
        // To avoid duplicating the exact template record that is already in `state.transactions`,
        // we check if this cursor matches the template's occurredAt. If so, we can let the actual
        // template serve as the occurrence, OR we can hide the template and strictly use forecast.
        // It's cleaner to generate a 'forecast' record for ALL occurrences, including the first one,
        // so that we have a uniform 'forecast' status for UI coloring/logic.
        
        Money forecastAmount = template.amount;
        Money forecastBaseAmount = template.baseAmount;
        
        if (template.originalAmount != null) {
          forecastAmount = convertMoneyForDisplay(state, template.originalAmount!, template.amount.currency);
          forecastBaseAmount = convertMoneyForDisplay(state, template.originalAmount!, state.preferences.baseCurrency);
        } else {
          forecastBaseAmount = convertMoneyForDisplay(state, template.amount, state.preferences.baseCurrency);
        }

        occurrences.add(template.copyWith(
          id: 'forecast-${template.id}-${cursor.toIso8601String()}',
          status: 'forecast',
          occurredAt: cursor,
          amount: forecastAmount,
          baseAmount: forecastBaseAmount,
        ));
      }
      
      cursor = _advanceCursor(cursor, frequency);
      count++;
      if (count > 200) break; // Safety break
    }
  }
  
  return occurrences;
}

DateTime _advanceCursor(DateTime current, String frequency) {
  switch (frequency.toLowerCase()) {
    case 'daily':
      return current.add(const Duration(days: 1));
    case 'weekly':
      return current.add(const Duration(days: 7));
    case 'monthly':
      return _addMonths(current, 1);
    case 'yearly':
      return _addMonths(current, 12);
    default:
      return _addMonths(current, 1);
  }
}

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
