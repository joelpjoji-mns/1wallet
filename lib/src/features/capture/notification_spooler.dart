import 'dart:convert';
import 'capture_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/ledger_models.dart';

class NotificationSpooler {
  static Future<void> spoolMessage(
    String sender,
    String body, {
    String owner = 'local-user',
  }) => CaptureQueue.client.append(owner, 'notification', {
    'sender': sender,
    'body': body,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  });

  /// Reads without acknowledging; only a durable ledger commit permits removal.
  static Future<List<Map<String, dynamic>>> popSpooledMessages({
    String owner = 'local-user',
  }) async => [
    for (final entry in await CaptureQueue.client.pending(
      owner,
      'notification',
    ))
      {...entry.payload, '_queueId': entry.id},
  ];

  /// Maintains legacy settings caches. LedgerController publishes the native
  /// owner/filter snapshot transactionally through CaptureQueue.
  static Future<void> updateTriggerWords(LedgerState state) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> clean(List<String> words) => words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();

    await prefs.setString(
      'one_wallet_flutter.notification_trigger_words',
      jsonEncode(clean(state.preferences.notificationTriggerWords)),
    );
    await prefs.setString(
      'one_wallet_flutter.notification_ignore_words',
      jsonEncode(clean(state.preferences.notificationIgnoreWords)),
    );
    await prefs.setString(
      'one_wallet_flutter.notification_target_packages',
      jsonEncode(clean(state.preferences.notificationTargetPackages)),
    );
    await prefs.setBool(
      'one_wallet_flutter.notification_capture_enabled',
      state.preferences.notificationCaptureEnabled,
    );
  }
}
