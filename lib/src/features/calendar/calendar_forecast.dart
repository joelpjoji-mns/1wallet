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
    
    int pastOccurrences = 0;
    if (template.recurrenceLimit != null) {
      pastOccurrences = state.transactions.where(
        (tx) => tx.originalTransactionId == template.id &&
            tx.status != 'scheduled' &&
            tx.status != 'void',
      ).length;
    }

    int count = 0;
    while (cursor.isBefore(horizonEnd) || cursor.isAtSameMomentAs(horizonEnd)) {
      if (template.recurrenceLimit != null && (pastOccurrences + count) >= template.recurrenceLimit!) break;
      if (template.recurrenceEndDate != null && cursor.isAfter(template.recurrenceEndDate!)) break;

      if (cursor.isAfter(horizonStart) ||
          cursor.isAtSameMomentAs(horizonStart)) {
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
