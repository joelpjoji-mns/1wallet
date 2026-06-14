import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/capture/message_parser.dart';

void main() {
  test('Test SMS parsing', () {
    final sms = 'ICICI Bank Acct XX173 debited for Rs 5059.00 on 15-Jun-26; CHEQ DIGITAL PR credited. UPI:653240699663. Call 18002662 for dispute. SMS BLOCK 173 to 9215676766.';
    final result = parseTransactionMessage(sms);
    print('ignored: ${result.ignored}');
    print('amount: ${result.amount?.amountMinor} ${result.amount?.currency}');
    print('merchant: ${result.merchant}');
    print('type: ${result.transactionType}');
    print('last4: ${result.last4}');
  });
}
