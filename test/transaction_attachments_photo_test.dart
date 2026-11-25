import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/attachment_thumbnail.dart';
import 'package:one_wallet_flutter/src/features/transactions/transaction_detail_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  testWidgets(
    'AddRecordScreen displays attached photos and allows deleting them',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final base = sampleLedgerState();
      final sampleTx = base.transactions.first;

      const attachment = TransactionAttachment(
        id: 'att-1',
        source: 'library',
        name: 'receipt.jpg',
        uri: 'test/receipt.jpg',
      );

      final txWithAttachment = sampleTx.copyWith(
        id: 'tx-with-photo',
        attachments: [attachment],
      );

      final ledgerState = base.copyWith(
        transactions: [txWithAttachment, ...base.transactions.skip(1)],
        preferences: base.preferences.copyWith(
          displayCurrency: 'USD',
          locale: 'en_US',
        ),
      );

      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(),
      );
      addTearDown(container.dispose);

      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(ledgerState);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: AddRecordScreen(
                transactionId: 'tx-with-photo',
                initialTab: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify 'Attached photos' section exists and renders the thumbnail
      expect(find.text('Attached photos'), findsOneWidget);
      expect(find.byType(AttachmentThumbnail), findsOneWidget);

      // Tap delete on the thumbnail
      final deleteIcon = find.byIcon(Icons.close_rounded);
      expect(deleteIcon, findsOneWidget);
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      // Verify it is now deleted from the draft
      expect(find.text('No photos attached yet.'), findsOneWidget);
      expect(find.byType(AttachmentThumbnail), findsNothing);
    },
  );

  testWidgets(
    'TransactionDetailScreen renders AttachmentThumbnail for attachments',
    (tester) async {
      final base = sampleLedgerState();
      final sampleTx = base.transactions.first;

      const attachment = TransactionAttachment(
        id: 'att-2',
        source: 'camera',
        name: 'bill.png',
        uri: 'test/bill.png',
      );

      final txWithAttachment = sampleTx.copyWith(
        id: 'tx-detail-photo',
        attachments: [attachment],
      );

      final ledgerState = base.copyWith(
        transactions: [txWithAttachment],
        preferences: base.preferences.copyWith(
          displayCurrency: 'USD',
          locale: 'en_US',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [...authenticatedSampleOverrides(ledger: ledgerState)],
          child: const MaterialApp(
            home: Scaffold(
              body: TransactionDetailScreen(transactionId: 'tx-detail-photo'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(AttachmentThumbnail), findsOneWidget);
    },
  );

  testWidgets('large transaction amounts stay on one line on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = sampleLedgerState();
    const amount = Money(amountMinor: 18500000, currency: 'INR');
    final transaction = base.transactions.first.copyWith(
      id: 'tx-large-amount',
      amount: amount,
      baseAmount: amount,
    );
    final ledger = base.copyWith(
      transactions: [transaction],
      preferences: base.preferences.copyWith(
        displayCurrency: 'INR',
        locale: 'en_US',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: ledger),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: TransactionDetailScreen(transactionId: 'tx-large-amount'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amountText = find.textContaining('185,000.00');
    expect(amountText, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(amountText);
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    expect(painter.computeLineMetrics(), hasLength(1));
    expect(paragraph.didExceedMaxLines, isFalse);
    painter.dispose();
    expect(tester.takeException(), isNull);
  });
}
