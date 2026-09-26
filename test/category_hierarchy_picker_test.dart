// Focused regression tests for the shared category picker
// (`showCategoryHierarchyPicker` / `_CategoryHierarchyPicker` in
// category_hierarchy_picker.dart), covering search/selection/null/empty and
// category-tree edge cases flagged by the ledger audit:
//
//   1. System back (e.g. Android hardware back / swipe-back gesture) must
//      step up exactly one level in a multi-level category tree, matching
//      the on-screen back button. Before the fix, `PopScope`'s
//      `onPopInvokedWithResult` called `_showCategoryList()` unconditionally,
//      jumping straight to the top-level list and skipping intermediate
//      levels whenever the *system* back was used instead of the AppBar
//      button.
//   2. An empty option list must distinguish "there is nothing to pick from"
//      (no categories at all) from "your search matched nothing" - the
//      former must not offer a dead-end "Clear search" action.
//   3. A search query still finds and selects an unrelated match outside the
//      active subcategory view (search intentionally spans the whole tree,
//      not just the active level), returning the correct id through the
//      picker's Future.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/common/category_hierarchy_picker.dart';

/// Pumps a screen with a button that opens the category picker, and records
/// the value the picker's Future eventually resolves with.
class _PickerHarness {
  _PickerHarness(this.tester);

  final WidgetTester tester;
  String? result;

  Future<void> open(LedgerState state, {String? selectedCategoryId}) async {
    await tester.pumpWidget(
      MaterialApp(
        // NoSplash avoids the ink_sparkle shader, which is intermittently
        // unavailable in the test environment and otherwise makes tapping
        // "Open picker" / category rows flaky.
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showCategoryHierarchyPicker(
                    context: context,
                    state: state,
                    selectedCategoryId: selectedCategoryId,
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }
}

void main() {
  LedgerState ledgerWith(List<Category> categories) {
    return LedgerState(
      version: currentLedgerStateVersion,
      userId: 'test-user',
      preferences: const LedgerPreferences(),
      accounts: const [],
      categories: categories,
      transactions: const [],
      captureCandidates: const [],
    );
  }

  testWidgets(
    'system back steps up exactly one level in a 3-level category tree',
    (tester) async {
      final state = ledgerWith(const [
        Category(id: 'cat-bills', name: 'Bills', kind: 'expense'),
        Category(
          id: 'cat-utilities',
          name: 'Utilities',
          kind: 'expense',
          parentId: 'cat-bills',
        ),
        Category(
          id: 'cat-electricity',
          name: 'Electricity',
          kind: 'expense',
          parentId: 'cat-utilities',
        ),
      ]);

      final harness = _PickerHarness(tester);
      await harness.open(state);

      // Drill down: Bills -> Utilities -> Electricity.
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Pick a subcategory under Bills'),
        findsOneWidget,
      );

      await tester.tap(find.text('Utilities'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Pick a subcategory under Utilities'),
        findsOneWidget,
      );
      expect(find.text('Electricity'), findsOneWidget);

      // Simulate the system back gesture/button (not the on-screen AppBar
      // back button), which is what `PopScope.onPopInvokedWithResult`
      // intercepts.
      final pickerContext = tester.element(
        find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() == '_CategoryHierarchyPicker',
        ),
      );
      await Navigator.of(pickerContext).maybePop();
      await tester.pumpAndSettle();

      // Must land back on Bills' subcategory list (one level up), not jump
      // all the way to the top-level category list.
      expect(
        find.textContaining('Pick a subcategory under Bills'),
        findsOneWidget,
      );
      expect(find.text('Utilities'), findsOneWidget);
      expect(find.text('Choose category'), findsNothing);
    },
  );

  testWidgets('an empty category list shows a "nothing to choose from" message '
      'without a dead-end Clear search action', (tester) async {
    final harness = _PickerHarness(tester);
    await harness.open(ledgerWith(const []));

    expect(find.text('No categories yet'), findsOneWidget);
    expect(find.text('No matches'), findsNothing);
    expect(find.text('Clear search'), findsNothing);
  });

  testWidgets(
    'a search query with no matches shows "No matches" with a working '
    'Clear search action',
    (tester) async {
      final harness = _PickerHarness(tester);
      await harness.open(
        ledgerWith(const [
          Category(id: 'cat-food', name: 'Food', kind: 'expense'),
        ]),
      );

      await tester.enterText(find.byType(EditableText), 'zzz-nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Food'), findsNothing);

      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsOneWidget);
    },
  );

  testWidgets(
    'searching from within a subcategory view still finds and selects an '
    'unrelated top-level category',
    (tester) async {
      final state = ledgerWith(const [
        Category(id: 'cat-bills', name: 'Bills', kind: 'expense'),
        Category(
          id: 'cat-utilities',
          name: 'Utilities',
          kind: 'expense',
          parentId: 'cat-bills',
        ),
        Category(id: 'cat-food', name: 'Food', kind: 'expense'),
      ]);

      final harness = _PickerHarness(tester);
      await harness.open(state);

      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Pick a subcategory under Bills'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(EditableText), 'food');
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsWidgets);
      await tester.tap(find.text('Food').first);
      await tester.pumpAndSettle();

      expect(harness.result, 'cat-food');
    },
  );
}
