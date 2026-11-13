import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/features/common/full_screen_picker.dart';

void main() {
  testWidgets(
    'showMultiSelectFullScreenPicker allows selecting multiple categories and applying',
    (tester) async {
      Set<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showMultiSelectFullScreenPicker<String>(
                      context: context,
                      title: 'Choose categories',
                      searchHint: 'Search categories',
                      options: const [
                        PickerOption(
                          value: '__uncategorized__',
                          title: 'Uncategorized',
                          subtitle: 'Records without a category',
                          icon: Icons.label_off_outlined,
                        ),
                        PickerOption(
                          value: 'cat-food',
                          title: 'Food & Dining',
                          subtitle: 'Expenses',
                          icon: Icons.restaurant_rounded,
                        ),
                        PickerOption(
                          value: 'cat-travel',
                          title: 'Travel',
                          subtitle: 'Expenses',
                          icon: Icons.flight_rounded,
                        ),
                        PickerOption(
                          value: 'cat-salary',
                          title: 'Salary',
                          subtitle: 'Income',
                          icon: Icons.work_rounded,
                        ),
                      ],
                      selectedValues: {'cat-food'},
                    );
                  },
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      // Tap to open picker
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Verify title and options rendered
      expect(find.text('Choose categories'), findsOneWidget);
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);

      // Verify cat-food is selected initially
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);

      // Tap 'Travel' to multi-select it
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();

      // Verify both are now selected (2 check_box_rounded widgets)
      expect(find.byIcon(Icons.check_box_rounded), findsNWidgets(2));

      // Tap 'Uncategorized' to also select it
      await tester.tap(find.text('Uncategorized'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_box_rounded), findsNWidgets(3));

      // Tap Apply button
      await tester.tap(find.text('Apply (3)'));
      await tester.pumpAndSettle();

      // Verify picker closed and returned all 3 selected values
      expect(find.text('Choose categories'), findsNothing);
      expect(result, isNotNull);
      expect(result, {'cat-food', 'cat-travel', '__uncategorized__'});
    },
  );

  testWidgets(
    'showMultiSelectFullScreenPicker clear all button resets selections',
    (tester) async {
      Set<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showMultiSelectFullScreenPicker<String>(
                      context: context,
                      title: 'Choose categories',
                      options: const [
                        PickerOption(value: 'cat-food', title: 'Food & Dining'),
                        PickerOption(value: 'cat-travel', title: 'Travel'),
                      ],
                      selectedValues: {'cat-food', 'cat-travel'},
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

      expect(find.byIcon(Icons.check_box_rounded), findsNWidgets(2));

      // Tap Clear all button in header
      await tester.tap(find.byTooltip('Clear all'));
      await tester.pumpAndSettle();

      // Verify all checkboxes unchecked
      expect(find.byIcon(Icons.check_box_rounded), findsNothing);

      // Tap 'Show all' (when selection is empty)
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, isEmpty);
    },
  );
}
