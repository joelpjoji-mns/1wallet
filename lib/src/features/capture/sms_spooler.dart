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

  /// Extracts keywords from the ledger state and saves them as trigger words
  /// so that the Android SmsReceiver can filter incoming messages.
  static Future<void> updateTriggerWords(LedgerState state) async {
    final prefs = await SharedPreferences.getInstance();

    final words = <String>{
      // Common transaction words
      'debited', 'credited', 'spent', 'paid', 'received', 'transaction',
      'payment', 'a/c', 'acct', 'tx', 'txn', 'balance', 'deducted',
      'refund', 'reversal', 'reversed', 'charge', 'withdrawal', 'purchase',
      'fee', 'remitted', 'deposited', 'salary', 'cashback', 'added',
      'withdrawn', 'sent', 'transfer', 'remittance', 'dr', 'cr',
      'upi', 'vpa', 'inr', 'rs', 'usd', 'eur', 'gbp',
    };

    for (final account in state.accounts) {
      if (account.isArchived) continue;

      // Add currency
      words.add(account.currency.toLowerCase());

      // Add parts of account name
      final parts = account.name.split(RegExp(r'\s+'));
      for (final part in parts) {
        if (part.length > 2) {
          words.add(part.toLowerCase());
        }
      }

      // Add parts of group name if present
      if (account.groupName != null) {
        final groupParts = account.groupName!.split(RegExp(r'\s+'));
        for (final part in groupParts) {
          if (part.length > 2) {
            words.add(part.toLowerCase());
          }
        }
      }

      // Add parts of institution if present
      if (account.institution != null) {
        final instParts = account.institution!.split(RegExp(r'\s+'));
        for (final part in instParts) {
          if (part.length > 2) {
            words.add(part.toLowerCase());
          }
        }
      }
    }

    final triggerWords = words.toList();
    await prefs.setString(
      'one_wallet_flutter.sms_trigger_words',
      jsonEncode(triggerWords),
    );
  }
}
