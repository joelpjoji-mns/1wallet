import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  testWidgets('Add record screen tag input displays saved tags on focus and places chips inside box without #', (tester) async {
    final base = sampleLedgerState();
    final sampleTx = base.transactions.first;
    // Add existing transactions with tags
    final tx1 = sampleTx.copyWith(
      id: 'tx-with-tags-1',
      tags: ['Work', 'Travel'],
    );
    final tx2 = sampleTx.copyWith(
      id: 'tx-with-tags-2',
      tags: ['Groceries', 'Personal'],
    );

    final ledgerState = base.copyWith(
      transactions: [...base.transactions, tx1, tx2],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authenticatedSampleOverrides(ledger: ledgerState),
        ],
        child: const MaterialApp(
          home: AddRecordScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Details tab (index 1)
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    // Verify "Tags" label is present (not "Tags / Labels")
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Tags / Labels'), findsNothing);
    expect(find.byIcon(Icons.sell_outlined), findsOneWidget);

    final tagsBox = find.widgetWithText(InputDecorator, 'Tags');
    expect(tagsBox, findsOneWidget);

    final tagField = find.descendant(of: tagsBox, matching: find.byType(TextField));
    expect(tagField, findsOneWidget);

    // Tap the text field directly to focus it
    await tester.tap(tagField);
    await tester.pumpAndSettle();

    // Verify saved tags show immediately in the options view on focus
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);

    // Verify NO '#' appears anywhere in the options view
    expect(find.text('#Groceries'), findsNothing);
    expect(find.text('#Travel'), findsNothing);

    // Tap 'Groceries' to select it
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    // Verify 'Groceries' chip is now created inside an InputChip inside the tags box
    expect(find.descendant(of: tagsBox, matching: find.byType(InputChip)), findsOneWidget);
    expect(find.descendant(of: find.byType(InputChip), matching: find.text('Groceries')), findsOneWidget);

    // Tap field again and select 'Travel'
    await tester.tap(tagField);
    await tester.pumpAndSettle();

    expect(find.text('Travel'), findsOneWidget);
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();

    // Verify multiple tags are now present inside chips inside the tags box
    expect(find.descendant(of: tagsBox, matching: find.byType(InputChip)), findsNWidgets(2));
    expect(find.descendant(of: find.byType(InputChip), matching: find.text('Groceries')), findsOneWidget);
    expect(find.descendant(of: find.byType(InputChip), matching: find.text('Travel')), findsOneWidget);
  });
}
