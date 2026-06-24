import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import '../../utils/recurrence_utils.dart';

List<TransactionRecord> forecastRecurringTransactions(
  LedgerState state,
  DateTime horizonStart,
  DateTime horizonEnd,
) {
  final occurrences = <TransactionRecord>[];

  // Find all scheduled transactions from recurring templates
  final templates = state.transactions.where(
    (tx) =>
        tx.status == 'scheduled' &&
        tx.source == 'recurring' &&
        tx.status != 'void',
  );

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
      if (cursor.isAfter(horizonStart) ||
          cursor.isAtSameMomentAs(horizonStart)) {
        // To avoid duplicating the exact template record that is already in `state.transactions`,
        // we check if this cursor matches the template's occurredAt. If so, we can let the actual
        // template serve as the occurrence, OR we can hide the template and strictly use forecast.
        // It's cleaner to generate a 'forecast' record for ALL occurrences, including the first one,
        // so that we have a uniform 'forecast' status for UI coloring/logic.

        Money forecastAmount = template.amount;
        Money forecastBaseAmount = template.baseAmount;

        if (template.originalAmount != null) {
          forecastAmount = convertMoneyForDisplay(
            state,
            template.originalAmount!,
            template.amount.currency,
          );
          forecastBaseAmount = convertMoneyForDisplay(
            state,
            template.originalAmount!,
            state.preferences.baseCurrency,
          );
        } else {
          forecastBaseAmount = convertMoneyForDisplay(
            state,
            template.amount,
            state.preferences.baseCurrency,
          );
        }

        occurrences.add(
          template.copyWith(
            id: 'forecast-${template.id}-${cursor.toIso8601String()}',
            status: 'forecast',
            occurredAt: cursor,
            amount: forecastAmount,
            baseAmount: forecastBaseAmount,
          ),
        );
      }

      cursor = advanceTransactionRecurrence(cursor, template);
      count++;
      if (count > 200) break; // Safety break
    }
  }

  return occurrences;
}
