// Focused tests for the shared full-screen picker's navigation chrome
// (`showFullScreenPicker` / `_FullScreenPicker` in full_screen_picker.dart),
// covering the Material AppBar -> GlassAppBar conversion:
//   1. The back button (a GlassIconButton, unchanged since before the
//      conversion) still pops the route with a null result.
//   2. An optional trailing action icon still renders with its tooltip and
//      triggers its callback.
//   3. The title still renders, and tapping an option still pops with its
//      value.
// GlassAppBar has no automatic Navigator awareness the way Material's
// AppBar does, but this picker never relied on that auto-behavior - its
// leading was always an explicit GlassIconButton - so there's no equivalent
// regression risk here to the one found in RouteScaffold's desktop path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/common/full_screen_picker.dart';

/// Pumps a screen with a button that opens the picker, and records the
/// value the picker's Future eventually resolves with.
class _PickerHarness {
  _PickerHarness(this.tester);

  final WidgetTester tester;
  String? result;

  Future<void> open({
    IconData? actionIcon,
    String? actionTooltip,
    VoidCallback? onAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showFullScreenPicker<String>(
                    context: context,
                    title: 'Pick one',
                    options: const [
                      PickerOption(value: 'a', title: 'Option A'),
                      PickerOption(value: 'b', title: 'Option B'),
                    ],
                    actionIcon: actionIcon,
                    actionTooltip: actionTooltip,
                    onAction: onAction,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('the title renders and the back button pops with null', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    final harness = _PickerHarness(tester);
    await harness.open();
    expect(find.text('Pick one'), findsOneWidget);

    final backButton = find.bySemanticsLabel('Back');
    expect(backButton, findsOneWidget);

    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(harness.result, isNull);
    expect(find.text('Pick one'), findsNothing);

    handle.dispose();
  });

  testWidgets(
    'an optional trailing action renders with its tooltip and fires',
    (tester) async {
      final handle = tester.ensureSemantics();

      var actionFired = false;
      final harness = _PickerHarness(tester);
      await harness.open(
        actionIcon: Icons.add_rounded,
        actionTooltip: 'Add new',
        onAction: () => actionFired = true,
      );

      final actionButton = find.bySemanticsLabel('Add new');
      expect(actionButton, findsOneWidget);

      await tester.tap(actionButton);
      await tester.pumpAndSettle();
      expect(actionFired, isTrue);

      // Tooltip message is also reachable via a long-press-style Tooltip
      // widget lookup so the visual hint still works, not just semantics.
      expect(find.byTooltip('Add new'), findsOneWidget);

      handle.dispose();
    },
  );

  testWidgets('tapping an option pops the picker with its value', (
    tester,
  ) async {
    final harness = _PickerHarness(tester);
    await harness.open();

    await tester.tap(find.text('Option B'));
    await tester.pumpAndSettle();

    expect(harness.result, 'b');
  });
}
