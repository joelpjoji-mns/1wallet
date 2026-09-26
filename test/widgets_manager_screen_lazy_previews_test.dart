import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/features/home/widgets_manager_screen.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Regression coverage for the Widgets Gallery performance fix: it used to
/// build all ~16 live dashboard previews (each a real, potentially
/// data/async-heavy widget) inside a single non-lazy `Column`. It now uses a
/// `CustomScrollView` with a `SliverList.builder`, so only previews near the
/// viewport should be built at any given time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'offscreen dashboard previews are not all built initially, and '
    'scrolling builds more of them',
    (tester) async {
      // A modest phone-sized viewport so only a handful of ~16 previews fit
      // near the visible area at once.
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(
            ledger: sampleLedgerState(),
            prefs: prefs,
          ),
          child: const MaterialApp(home: WidgetsManagerScreen()),
        ),
      );
      // A single frame is enough for build() to run for whatever the sliver
      // list currently decides to construct; deliberately not
      // `pumpAndSettle` here so in-flight per-tile animations don't matter.
      await tester.pump();

      // Every preview renders exactly one date-preset `ActionChip`, which
      // makes it a reliable, type-safe proxy for "how many previews have
      // actually been built" without needing to reach into the private
      // `_LiveWidgetPreview` widget.
      final totalWidgetCount = HomeDashboardWidgetId.values.length;
      final builtInitially = find.byType(ActionChip).evaluate().length;

      expect(
        builtInitially,
        lessThan(totalWidgetCount),
        reason:
            'Expected only a subset of the $totalWidgetCount gallery '
            'previews to be built for a 400x700 viewport; got '
            '$builtInitially, suggesting the list is no longer lazy.',
      );
      expect(builtInitially, greaterThan(0));

      // Scrolling reveals (and builds) more previews further down the list.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      final builtAfterScroll = find.byType(ActionChip).evaluate().length;
      expect(builtAfterScroll, greaterThan(builtInitially));
    },
  );

  testWidgets(
    'toggling a preview switch still hides/restores it on Home after the '
    'sliver refactor',
    (tester) async {
      // Tall enough that every preview in the gallery is built up front (this
      // test is about toggle/restore correctness, not laziness — the first
      // test above already covers that).
      await tester.binding.setSurfaceSize(const Size(1080, 10000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(
          ledger: sampleLedgerState(),
          prefs: prefs,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WidgetsManagerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final initialHidden =
          container.read(ledgerProvider).preferences.homeWidgetHidden;
      expect(initialHidden, isEmpty);
      expect(find.text('Hidden'), findsNothing);

      // Hide the first previewed (currently visible) widget.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      final afterHide =
          container.read(ledgerProvider).preferences.homeWidgetHidden;
      expect(afterHide, hasLength(1));
      expect(find.text('Hidden'), findsOneWidget);

      // Find that exact preview (identified by its "Hidden" label, since
      // toggling one entry can reshuffle the gallery's display order) and
      // toggle it back on.
      final hiddenPreviewRow = find
          .ancestor(of: find.text('Hidden'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: hiddenPreviewRow, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      final afterRestore =
          container.read(ledgerProvider).preferences.homeWidgetHidden;
      expect(afterRestore, isEmpty);
      expect(find.text('Hidden'), findsNothing);

      // The restored widget's storage key must be reinserted exactly once,
      // not duplicated or dropped, preserving ordering behavior.
      final restoredOrder =
          container.read(ledgerProvider).preferences.homeWidgetOrder;
      expect(restoredOrder.toSet().length, restoredOrder.length);
    },
  );
}
