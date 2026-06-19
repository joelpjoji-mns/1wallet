import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';

void main() {
  test('Test message parsing', () {
    final msg1 = "SBI Bank: Your A/C XXXXX8910 is credited with INR 10,000.00 on 12/06/26 by SALARY MAY 2026. Avl Bal INR 15,200.00. -SBI";
    final msg2 = "BARCLAYS: A Direct Debit of £35.50 was paid to Vodafone UK from your account ending 5678 on 01 Jun.";
    
    final r1 = parseTransactionMessage(msg1);
    final r2 = parseTransactionMessage(msg2);
    
    print("r1 ignored: ${r1.ignored}, amount: ${r1.amount?.amountMinor}, type: ${r1.transactionType}");
    print("r2 ignored: ${r2.ignored}, amount: ${r2.amount?.amountMinor}, type: ${r2.transactionType}");
  });
}
