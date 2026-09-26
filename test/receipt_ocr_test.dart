import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/capture/receipt_ocr.dart';

void main() {
  const options = ReceiptPhotoOptions(
    fallbackCurrency: 'USD',
    fallbackOccurredAt: '2024-01-01T00:00:00.000Z',
  );

  test(
    'stitches a keyword label and its amount across adjacent lines instead of '
    'picking an unrelated bottom-of-receipt number',
    () {
      // "Total" and its value sit on separate OCR lines (very common for
      // receipts), while an unrelated, larger number ("Tip" of 99.00) sits
      // below it. The labeled total must win even though it is not the last
      // or largest number on the receipt.
      const text = 'Total\n45.00\nTip\n99.00';

      final fields = parseReceiptText(text, options);

      expect(fields.status, ReceiptOcrStatus.parsed);
      expect(fields.amountMinor, 4500);
    },
  );

  test(
    'parses a comma-decimal amount (e.g. European "12,34") next to a total '
    'keyword instead of silently dropping the amount',
    () {
      const text = 'Total 12,34';
      const eurOptions = ReceiptPhotoOptions(
        fallbackCurrency: 'EUR',
        fallbackOccurredAt: '2024-01-01T00:00:00.000Z',
      );

      final fields = parseReceiptText(text, eurOptions);

      expect(fields.amountMinor, 1234);
      expect(fields.currency, 'EUR');
    },
  );

  test('returns no amount for receipts with no numeric text', () {
    const fields = ReceiptOcrStatus.failed;
    final result = parseReceiptText('', options);
    expect(result.status, fields);
    expect(result.amountMinor, isNull);
  });
}
