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
    var cursor = template.occurredAt;
    
    int pastOccurrences = 0;
    if (template.recurrenceLimit != null) {
      pastOccurrences = state.transactions.where(
        (tx) => tx.originalTransactionId == template.id &&
            tx.status != 'scheduled' &&
            tx.status != 'void',
      ).length;
    }

    // `occurrenceIndex` counts every iteration of the recurrence rule (even
    // occurrences before the visible horizon) so the recurrenceLimit check
    // reflects the rule's true position. `displayCount` only counts
    // occurrences that actually fall within the horizon and get added to the
    // result, capping how many we render. `iterationGuard` is an absolute
    // safety net against runaway loops when neither limit nor horizon end up
    // terminating the loop (e.g. malformed template data).
    int occurrenceIndex = 0;
    int displayCount = 0;
    int iterationGuard = 0;
    while (cursor.isBefore(horizonEnd) || cursor.isAtSameMomentAs(horizonEnd)) {
      iterationGuard++;
      if (iterationGuard > 5000) break; // Absolute safety break
      if (template.recurrenceLimit != null && (pastOccurrences + occurrenceIndex) >= template.recurrenceLimit!) break;
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
            originalTransactionId: template.id,
          ),
        );
        displayCount++;
        if (displayCount > 200) break; // Display cap, post-horizon only
      }

      cursor = advanceTransactionRecurrence(cursor, template);
      occurrenceIndex++;
    }
  }

  return occurrences;
}
