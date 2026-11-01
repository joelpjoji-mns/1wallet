import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CaptureDiagnostics retention and auto-pruning', () {
    test('defaults to 30 days retention and persists updates', () async {
      expect(await CaptureDiagnostics.getRetentionDays(), 30);

      await CaptureDiagnostics.setRetentionDays(14);
      expect(await CaptureDiagnostics.getRetentionDays(), 14);

      await CaptureDiagnostics.setRetentionDays(7);
      expect(await CaptureDiagnostics.getRetentionDays(), 7);
    });

    test('prunes events older than the retention period', () async {
      const owner = 'test-user-retention';
      final now = DateTime.now();

      // Record an event from 40 days ago
      final oldEvent = CaptureDiagnosticEvent(
        id: 'event-old',
        timestamp: now.subtract(const Duration(days: 40)),
        source: 'sms',
        stage: 'test',
        decision: 'queued',
      );

      // Record an event from 10 days ago
      final recentEvent = CaptureDiagnosticEvent(
        id: 'event-recent',
        timestamp: now.subtract(const Duration(days: 10)),
        source: 'sms',
        stage: 'test',
        decision: 'queued',
      );

      // Record an event from today
      final freshEvent = CaptureDiagnosticEvent(
        id: 'event-fresh',
        timestamp: now,
        source: 'sms',
        stage: 'test',
        decision: 'queued',
      );

      await CaptureDiagnostics.recordEvent(oldEvent, ownerId: owner);
      await CaptureDiagnostics.recordEvent(recentEvent, ownerId: owner);
      await CaptureDiagnostics.recordEvent(freshEvent, ownerId: owner);

      // Default is 30 days. When pruneOldEvents runs, oldEvent (>30 days) is pruned.
      final prunedDefault = await CaptureDiagnostics.pruneOldEvents(ownerId: owner);
      expect(prunedDefault, 1);
      final eventsAfterDefault = await CaptureDiagnostics.recentEvents(ownerId: owner);
      expect(eventsAfterDefault.map((e) => e.id), containsAll(['event-fresh', 'event-recent']));
      expect(eventsAfterDefault.map((e) => e.id), isNot(contains('event-old')));

      // Now set retention to 7 days and prune
      await CaptureDiagnostics.setRetentionDays(7);
      final pruned = await CaptureDiagnostics.pruneOldEvents(ownerId: owner);
      expect(pruned, 1); // event-recent (10 days old) was pruned

      final eventsAfter7Days = await CaptureDiagnostics.recentEvents(ownerId: owner);
      expect(eventsAfter7Days, hasLength(1));
      expect(eventsAfter7Days.first.id, 'event-fresh');
    });
  });
}
