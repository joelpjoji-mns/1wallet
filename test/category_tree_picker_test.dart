import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/common/category_tree_picker.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  testWidgets(
    'showCategoryTreeMultiSelectPicker renders category tree without checkboxes and supports multi-select',
    (tester) async {
      final base = sampleLedgerState();
      const parentCat = Category(
        id: 'cat-housing',
        name: 'Housing & Utilities',
        kind: 'expense',
      );
      const childCat1 = Category(
        id: 'cat-rent',
        name: 'Rent & Mortgage',
        kind: 'expense',
        parentId: 'cat-housing',
      );
      const childCat2 = Category(
        id: 'cat-electricity',
        name: 'Electricity & Gas',
        kind: 'expense',
        parentId: 'cat-housing',
      );
      const otherCat = Category(
        id: 'cat-groceries',
        name: 'Groceries',
        kind: 'expense',
      );

      final ledgerState = base.copyWith(
        categories: [parentCat, childCat1, childCat2, otherCat],
      );

      Set<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showCategoryTreeMultiSelectPicker(
                      context: context,
                      state: ledgerState,
                      initialSelectedCategoryIds: {'cat-rent'},
                      initialIncludeUncategorized: false,
                      title: 'Filter categories',
                    );
                  },
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Verify title and tree items rendered
      expect(find.text('Filter categories'), findsOneWidget);
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(find.text('Housing & Utilities'), findsOneWidget);
      expect(find.text('Rent & Mortgage'), findsOneWidget);
      expect(find.text('Electricity & Gas'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);

      // Verify NO checkboxes are used
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.check_box_rounded), findsNothing);

      // Verify cat-rent is initially selected with check circle
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // Tap 'Electricity & Gas' to multi-select it
      await tester.tap(find.text('Electricity & Gas'));
      await tester.pumpAndSettle();

      // Verify 2 items selected
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      expect(find.text('Apply (2)'), findsOneWidget);

      // Tap 'Uncategorized' to also include it
      await tester.tap(find.text('Uncategorized'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(find.text('Apply (3)'), findsOneWidget);

      // Tap Apply
      await tester.tap(find.text('Apply (3)'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, contains('cat-rent'));
      expect(result, contains('cat-electricity'));
      expect(result, contains(categoryTreeUncategorizedKey));
    },
  );

  testWidgets(
    'showCategoryTreeMultiSelectPicker search filters matching categories',
    (tester) async {
      final base = sampleLedgerState();
      const parentCat = Category(
        id: 'cat-housing',
        name: 'Housing & Utilities',
        kind: 'expense',
      );
      const childCat1 = Category(
        id: 'cat-rent',
        name: 'Rent & Mortgage',
        kind: 'expense',
        parentId: 'cat-housing',
      );

      final ledgerState = base.copyWith(categories: [parentCat, childCat1]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showCategoryTreeMultiSelectPicker(
                    context: context,
                    state: ledgerState,
                    initialSelectedCategoryIds: {},
                  ),
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Enter search text
      await tester.enterText(find.byType(EditableText), 'rent');
      await tester.pumpAndSettle();

      expect(find.text('Rent & Mortgage'), findsOneWidget);
      expect(find.text('Housing & Utilities'), findsNothing);
    },
  );

  testWidgets(
    'showCategoryTreeMultiSelectPicker has a back button that pops with null',
    (tester) async {
      final base = sampleLedgerState();
      Set<String>? result = {'dummy'};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCategoryTreeMultiSelectPicker(
                    context: context,
                    state: base,
                    initialSelectedCategoryIds: {},
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text('Choose categories'), findsNothing);
    },
  );

  testWidgets(
    'showCategoryTreeMultiSelectPicker pops on system back without throwing',
    (tester) async {
      final base = sampleLedgerState();
      Set<String>? result = {'dummy'};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCategoryTreeMultiSelectPicker(
                    context: context,
                    state: base,
                    initialSelectedCategoryIds: {},
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      final pickerContext = tester.element(find.text('Choose categories'));
      await Navigator.of(pickerContext).maybePop();
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text('Choose categories'), findsNothing);
    },
  );
}
