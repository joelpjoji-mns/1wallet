import 'dart:developer' as developer;
import 'package:flutter/widgets.dart';

import '../../capture/message_parser.dart'; // From phase 1
import 'sms_spooler.dart';

class HeadlessSmsPayload {
  final String? sender;
  final String? body;
  final String? receivedAt;

  const HeadlessSmsPayload({this.sender, this.body, this.receivedAt});
}

@pragma('vm:entry-point')
Future<void> processIncomingSmsHeadlessTask(HeadlessSmsPayload payload) async {
  WidgetsFlutterBinding.ensureInitialized();

  final body = payload.body?.trim() ?? '';
  if (body.isEmpty) return;

  try {
    // Headless isolates do not share Riverpod state with the foreground app.
    // Parse the incoming payload only; foreground review/import flows persist
    // candidates through the ledger controller when permissions and storage are
    // available.
    final parsed = parseTransactionMessage(body, fallbackCurrency: 'INR');

    if (!parsed.ignored) {
      developer.log(
        '[1wallet] SMS auto-capture processed: ${parsed.transactionType} ${parsed.amount?.amountMinor}',
        name: 'smsCapture',
      );
      await SmsSpooler.spoolMessage(payload.sender ?? 'Unknown', body);
    } else {
      developer.log(
        '[1wallet] SMS auto-capture ignored: ${parsed.warnings.join(", ")}',
        name: 'smsCapture',
      );
    }
  } catch (error) {
    developer.log(
      '[1wallet] SMS auto-capture failed: \$error',
      name: 'smsCapture',
      level: 900,
    );
  }
}
