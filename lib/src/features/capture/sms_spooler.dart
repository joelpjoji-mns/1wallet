import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/ledger_models.dart';

class SmsSpooler {
  static const _spoolKey = 'one_wallet_flutter.sms_spool';

  /// Adds a new raw SMS message to the background spool queue.
  static Future<void> spoolMessage(String sender, String body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final spooled = prefs.getStringList(_spoolKey) ?? <String>[];

    final payload = jsonEncode({
      'sender': sender,
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
    });

    spooled.add(payload);
    await prefs.setStringList(_spoolKey, spooled);
  }

  /// Retrieves all spooled messages and clears the queue.
  static Future<List<Map<String, dynamic>>> popSpooledMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final spooled = prefs.getStringList(_spoolKey);
    if (spooled == null || spooled.isEmpty) {
      return [];
    }

    final messages = <Map<String, dynamic>>[];
    for (final payload in spooled) {
      try {
        messages.add(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {}
    }

    await prefs.remove(_spoolKey);
    return messages;
  }

  /// Publishes the user's trigger + ignore word lists (and the enable flag)
  /// to SharedPreferences so the native Android [SmsReceiver] filters incoming
  /// messages with the EXACT same rule the Dart parser uses. Keeping the two
  /// in lock-step is what guarantees a notification is raised if and only if a
  /// review candidate would be created.
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
