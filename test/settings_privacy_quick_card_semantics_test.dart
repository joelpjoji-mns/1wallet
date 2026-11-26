// Regression coverage for the "Privacy mode" quick-toggle card on the
// Settings screen (`_PrivacyQuickCard` in settings_screen.dart).
//
// Before this fix, the card's interactive Switch was wrapped only in
// `IgnorePointer` (to route real touches through the surrounding InkWell)
// with no `MergeSemantics`/`ExcludeFocus`. That left screen readers with
// three disconnected stops for one conceptual control: the InkWell's
// generic tappable region, the "Privacy mode" label text, and the Switch's
// own on/off node claiming its own focus/tab stop. The fix mirrors the
// already-established pattern used by `AppSwitchListTile` and the drawer's
// `_DrawerPrivacyToggle`: `MergeSemantics` + `ExcludeFocus` collapse
// everything into one semantics node that carries the combined label and
// toggled state.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Privacy mode quick card merges label/switch into one semantics node '
    'and stays in sync when tapped',
    (tester) async {
      final handle = tester.ensureSemantics();

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(prefs: prefs),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: const SettingsScreen(),
            // NoSplash avoids the ink_sparkle shader, which is
            // intermittently unavailable in the test environment and
            // otherwise makes tapping the card flaky.
            theme: ThemeData(
              useMaterial3: true,
              splashFactory: NoSplash.splashFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // _PrivacyQuickCard is private to settings_screen.dart; match it by
      // runtimeType so this regression test doesn't need an export.
      final cardFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_PrivacyQuickCard',
      );
      expect(cardFinder, findsOneWidget);

      final initiallyEnabled = container
          .read(ledgerProvider)
          .preferences
          .privacyModeEnabled;

      final data = tester.getSemantics(cardFinder).getSemanticsData();
      expect(data.label, contains('Privacy mode'));
      expect(data.flagsCollection.isToggled, isNot(Tristate.none));
      expect(
        data.flagsCollection.isToggled,
        initiallyEnabled ? Tristate.isTrue : Tristate.isFalse,
      );

      // Tapping anywhere in the merged region toggles the underlying
      // preference, same as tapping the Switch itself would.
      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(
        container.read(ledgerProvider).preferences.privacyModeEnabled,
        !initiallyEnabled,
      );
      final toggledData = tester.getSemantics(cardFinder).getSemanticsData();
      expect(
        toggledData.flagsCollection.isToggled,
        initiallyEnabled ? Tristate.isFalse : Tristate.isTrue,
      );

      handle.dispose();
    },
  );

  testWidgets('large-text privacy description is readable and tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: const SettingsScreen(),
          theme: AppTheme.light(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_PrivacyQuickCard',
    );
    final description = find.text('Hide balances and amounts across the app.');
    expect(
      tester.getRect(description).width,
      greaterThan(tester.getRect(card).width * 0.75),
    );
    await tester.ensureVisible(description);
    await tester.pumpAndSettle();
    await tester.tap(description);
    await tester.pumpAndSettle();
    expect(
      container.read(ledgerProvider).preferences.privacyModeEnabled,
      isTrue,
    );
    expect(
      find.text('Balances and amounts are hidden across the app.'),
      findsOneWidget,
    );
  });
}
