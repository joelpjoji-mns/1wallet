import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
}
