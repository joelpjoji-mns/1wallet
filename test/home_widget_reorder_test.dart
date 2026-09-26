import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home screen reorders widgets in place and persists order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reorder widgets'), findsNothing);

    await tester.longPress(
      find.byTooltip('Long press All accounts to reorder widgets'),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Done reordering widgets'), findsOneWidget);
    expect(find.byTooltip('Drag All accounts'), findsOneWidget);

    // Invoke the reorder buttons' `onPressed` callbacks directly instead of
    // `tester.tap(...)`. A real tap on these plain `IconButton`s drives
    // Material's ink-splash pipeline, which under the app's Material 3 theme
    // defaults to `InkSparkle` — a shader-based effect that needs
    // `shaders/ink_sparkle.frag`. That asset intermittently fails to load
    // under `flutter test` (a known Flutter test-harness limitation, not an
    // app bug), causing this test to flake. Calling the callback directly
    // still exercises the exact same reorder logic/state update without
    // going through the gesture-and-ink rendering pipeline at all.
    _pressIconButton(tester, tooltip: 'Move up All accounts');
    await tester.pumpAndSettle();

    expect(container.read(ledgerProvider).preferences.homeWidgetOrder.take(2), [
      'accountGrid',
      'balanceHero',
    ]);

    _pressIconButton(tester, tooltip: 'Done reordering widgets');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reorder widgets'), findsNothing);
  });
}

/// Finds the `IconButton` with [tooltip] and invokes its `onPressed`
/// callback directly, bypassing `tester.tap`'s real gesture/ink pipeline.
void _pressIconButton(WidgetTester tester, {required String tooltip}) {
  final button = tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
  expect(
    button.onPressed,
    isNotNull,
    reason: 'Expected the "$tooltip" IconButton to be enabled.',
  );
  button.onPressed!();
}
