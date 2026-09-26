// Regression coverage for the category editor dialog in categories_screen.dart:
//   1. Saving with an empty name shows an inline validation error and keeps
//      the dialog open instead of silently creating a blank category.
//   2. Saving a valid name creates the category, closes the dialog, and
//      shows a confirmation SnackBar.
//
// The success SnackBar previously risked being skipped: `_openCategoryEditor`
// took `BuildContext context` as a parameter, but the nested
// `StatefulBuilder(builder: (context, setDialogState) => ...)` rebound the
// name `context` to the dialog's own (about-to-be-popped) BuildContext. The
// post-save `if (!context.mounted) return;` / `ScaffoldMessenger.of(context)`
// therefore raced against the dialog being popped instead of reliably using
// the still-mounted CategoriesScreen context. The fix renames the outer
// parameter to `screenContext` so the post-pop mounted-check and
// ScaffoldMessenger lookup unambiguously target the screen, not the dialog.
// This test exercises that exact save path end-to-end.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/categories/categories_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpCategoriesScreen(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: const CategoriesScreen(),
          // NoSplash avoids the ink_sparkle shader, which is intermittently
          // unavailable in the test environment and otherwise makes button
          // taps flaky with a "shaders/ink_sparkle.frag not found" error.
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('rejects an empty category name and keeps the dialog open', (
    tester,
  ) async {
    await pumpCategoriesScreen(tester);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('New category'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a category name.'), findsOneWidget);
    // Dialog must still be open: no success SnackBar and the title is
    // still visible.
    expect(find.text('New category'), findsOneWidget);
    expect(find.text('Category created.'), findsNothing);
  });

  testWidgets(
    'saving a valid name creates the category, closes the dialog, and '
    'shows a confirmation SnackBar',
    (tester) async {
      final container = await pumpCategoriesScreen(tester);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Groceries Test',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog closed.
      expect(find.text('New category'), findsNothing);
      // Confirmation SnackBar shown via the screen's (still-mounted)
      // context, not the popped dialog context.
      expect(find.text('Category created.'), findsOneWidget);

      final categories = container.read(ledgerProvider).categories;
      expect(categories.where((c) => c.name == 'Groceries Test').length, 1);
    },
  );
}
