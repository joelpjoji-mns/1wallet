import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';

void main() {
  test('test manual scan', () async {
    final container = ProviderContainer();
    final ledgerNotifier = container.read(ledgerProvider.notifier);
    
    // Wait for init
    await Future.delayed(Duration(seconds: 1));

    final sms = "Paid Rs. 500 at Amazon using card ending 1234. Ref: 123456789";
    
    final parsed = parseTransactionMessage(sms);
    print("Parsed ignored: \${parsed.ignored}");
    print("Parsed amount: \${parsed.amount?.amountMinor}");
    
    final candidate = await ledgerNotifier.importSmsMessage(sms);
    print("Candidate: \$candidate");
    
    final state = container.read(ledgerProvider);
    print("Candidates in state: \${state.captureCandidates.length}");
  });
}
