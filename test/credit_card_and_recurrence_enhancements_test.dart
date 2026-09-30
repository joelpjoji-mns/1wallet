import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/utils/recurrence_utils.dart';
import 'package:one_wallet_flutter/src/features/notifications/notification_engine.dart';

void main() {
  group('Last day of month recurrence', () {
    test('advances cursor dynamically to the last day of each month for day 32', () {
      final start = DateTime(2026, 1, 31);
      final nextFeb = advanceRecurrenceCursor(
        current: start,
        frequency: 'monthly',
        interval: 1,
        daysOfMonth: [32],
      );
      expect(nextFeb, DateTime(2026, 2, 28));

      final nextMar = advanceRecurrenceCursor(
        current: nextFeb,
        frequency: 'monthly',
        interval: 1,
        daysOfMonth: [32],
      );
      expect(nextMar, DateTime(2026, 3, 31));

      final nextApr = advanceRecurrenceCursor(
        current: nextMar,
        frequency: 'monthly',
        interval: 1,
        daysOfMonth: [32],
      );
      expect(nextApr, DateTime(2026, 4, 30));
    });
  });

  group('Credit Card Due Date status and notifications', () {
    final account = Account(
      id: 'card-1',
      name: 'Sapphire Preferred',
      type: 'credit_card',
      currency: 'USD',
      openingBalance: const Money(amountMinor: 0, currency: 'USD'),
      creditLimit: const Money(amountMinor: 500000, currency: 'USD'),
      statementDay: 15,
      dueDay: 5,
      notifyDaysBeforeDue: 3,
    );

    final baseState = LedgerState(
      version: 1,
      userId: 'test-user',
      accounts: [account],
      transactions: [],
      categories: [],
      captureCandidates: [],
      preferences: const LedgerPreferences(
        baseCurrency: 'USD',
        channelScheduledEnabled: true,
      ),
    );

    test('calculates due status correctly when due in 2 days', () {
      // Current date: Oct 3, 2026. Due date: Oct 5, 2026.
      final now = DateTime(2026, 10, 3);
      final status = creditCardDueStatus(baseState, account, now: now);

      expect(status, isNotNull);
      expect(status!.daysUntilDue, 2);
      expect(status.isDueSoon, isTrue);
      expect(status.isOverdue, isFalse);
      expect(status.isPaid, isFalse);
      expect(status.cycleKey, '2026-10');

      expect(creditCardsDueSoonCount(baseState, now: now), 1);

      final notifications = buildNotificationInbox(baseState, now: now);
      expect(notifications.any((n) => n.id.startsWith('card_due_card-1_')), isTrue);
    });

    test('calculates overdue status when past due date and unpaid', () {
      // Current date: Oct 7, 2026. Due date was Oct 5, 2026.
      final now = DateTime(2026, 10, 7);
      final status = creditCardDueStatus(baseState, account, now: now);

      expect(status, isNotNull);
      expect(status!.daysUntilDue, -2);
      expect(status.isOverdue, isTrue);
      expect(status.isDueSoon, isFalse);
      expect(status.isPaid, isFalse);

      expect(creditCardsDueSoonCount(baseState, now: now), 1);
    });

    test('is marked paid when lastPaidBillMonth matches cycleKey', () {
      final paidAccount = account.copyWith(lastPaidBillMonth: '2026-10');
      final state = baseState.copyWith(accounts: [paidAccount]);

      final now = DateTime(2026, 10, 3);
      final status = creditCardDueStatus(state, paidAccount, now: now);

      expect(status, isNotNull);
      expect(status!.isPaid, isTrue);
      expect(status.isDueSoon, isFalse);
      expect(status.isOverdue, isFalse);

      expect(creditCardsDueSoonCount(state, now: now), 0);
    });

    test('supports statement-only configuration without explicit dueDay', () {
      final stmtOnlyAccount = Account(
        id: 'card-stmt-only',
        name: 'Statement Card',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: const Money(amountMinor: -20000, currency: 'USD'),
        statementDay: 1, // 1st of month
      );
      final state = baseState.copyWith(accounts: [stmtOnlyAccount]);
      final now = DateTime(2026, 10, 5); // After statement date

      final status = creditCardDueStatus(state, stmtOnlyAccount, now: now);
      expect(status, isNotNull);
      expect(status!.isStatementGenerated, isTrue);
      expect(status.statementDate, isNotNull);
      expect(status.statementDate!.day, 1);
      expect(status.dueDate, isNotNull); // Has default grace period

      final notifications = buildNotificationInbox(state, now: now);
      expect(
        notifications.any((n) => n.id.startsWith('card_statement_card-stmt-only_')),
        isTrue,
      );
    });

    test('supports due-only configuration without explicit statementDay', () {
      final dueOnlyAccount = Account(
        id: 'card-due-only',
        name: 'Due Only Card',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: const Money(amountMinor: -15000, currency: 'USD'),
        dueDay: 15,
        notifyDaysBeforeDue: 5,
      );
      final state = baseState.copyWith(accounts: [dueOnlyAccount]);
      final now = DateTime(2026, 10, 12); // 3 days before due date

      final status = creditCardDueStatus(state, dueOnlyAccount, now: now);
      expect(status, isNotNull);
      expect(status!.isDueSoon, isTrue);
      expect(status.daysUntilDue, 3);

      final notifications = buildNotificationInbox(state, now: now);
      expect(
        notifications.any((n) => n.id.startsWith('card_due_card-due-only_')),
        isTrue,
      );
    });

    test('dismissing card notification excludes it for today', () {
      final now = DateTime(2026, 10, 3);
      final todayKey = '2026-10-03';
      final dismissedId = 'card_due_${account.id}_$todayKey';

      final dismissedState = baseState.copyWith(
        preferences: baseState.preferences.copyWith(
          dismissedNotificationIds: [dismissedId],
        ),
      );

      expect(creditCardsDueSoonCount(dismissedState, now: now), 0);
      final notifications = buildNotificationInbox(dismissedState, now: now);
      expect(notifications.any((n) => n.id == dismissedId), isFalse);
    });
  });

  group('Ledger Codec Account serialization', () {
    test('serializes and deserializes credit card due date fields', () {
      final account = Account(
        id: 'acc-cc-1',
        name: 'Platinum Card',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: const Money(amountMinor: -15000, currency: 'USD'),
        creditLimit: const Money(amountMinor: 1000000, currency: 'USD'),
        statementDay: 20,
        dueDay: 10,
        notifyDaysBeforeDue: 4,
        lastPaidBillMonth: '2026-09',
      );

      final json = accountToJson(account);
      final decoded = accountFromJson(json);

      expect(decoded.statementDay, 20);
      expect(decoded.dueDay, 10);
      expect(decoded.notifyDaysBeforeDue, 4);
      expect(decoded.lastPaidBillMonth, '2026-09');
      expect(decoded.creditLimit?.amountMinor, 1000000);
    });
  });
}
