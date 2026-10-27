import 'dart:convert';
import 'capture_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/ledger_models.dart';

class SmsSpooler {
  static Future<void> spoolMessage(
    String sender,
    String body, {
    String owner = 'local-user',
  }) => CaptureQueue.client.append(owner, 'sms', {
    'sender': sender,
    'body': body,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  });

  /// Reads without acknowledging; only a durable ledger commit permits removal.
  static Future<List<Map<String, dynamic>>> popSpooledMessages({
    String owner = 'local-user',
  }) async => [
    for (final entry in await CaptureQueue.client.pending(owner, 'sms'))
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
      'one_wallet_flutter.sms_trigger_words',
      jsonEncode(clean(state.preferences.smsTriggerWords)),
    );
    await prefs.setString(
      'one_wallet_flutter.sms_ignore_words',
      jsonEncode(clean(state.preferences.smsIgnoreWords)),
    );
    await prefs.setBool(
      'one_wallet_flutter.sms_capture_enabled',
      state.preferences.smsCaptureEnabled,
    );
  }
}
