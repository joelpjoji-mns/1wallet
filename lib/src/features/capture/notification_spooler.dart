import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/ledger_models.dart';

class NotificationSpooler {
  static const _spoolKey = 'one_wallet_flutter.notification_spool';

  /// Adds a new raw notification message to the background spool queue.
  static Future<void> spoolMessage(String sender, String body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final existingRaw = prefs.getString(_spoolKey) ?? '';
    List<dynamic> spooled;
    if (existingRaw.isNotEmpty) {
      try {
        spooled = (jsonDecode(existingRaw) as List).cast<dynamic>();
      } catch (_) {
        spooled = <dynamic>[];
      }
    } else {
      spooled = <dynamic>[];
    }

    final payload = jsonEncode({
      'sender': sender,
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
    });

    spooled.add(payload);
    await prefs.setString(_spoolKey, jsonEncode(spooled));
  }

  /// Retrieves all spooled messages and clears the queue.
  static Future<List<Map<String, dynamic>>> popSpooledMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final raw = prefs.getString(_spoolKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    List<dynamic> spooled;
    try {
      spooled = (jsonDecode(raw) as List).cast<dynamic>();
    } catch (_) {
      await prefs.remove(_spoolKey);
      return [];
    }

    final messages = <Map<String, dynamic>>[];
    for (final payload in spooled) {
      try {
        if (payload is String) {
          messages.add(jsonDecode(payload) as Map<String, dynamic>);
        } else if (payload is Map) {
          messages.add(Map<String, dynamic>.from(payload));
        }
      } catch (_) {}
    }

    await prefs.remove(_spoolKey);
    return messages;
  }

  /// Publishes the user's trigger + ignore + target packages lists
  /// to SharedPreferences so the native Android [NotificationReceiver] filters incoming
  /// notifications with the EXACT same rules the Dart parser uses.
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
