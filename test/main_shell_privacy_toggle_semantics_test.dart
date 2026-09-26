import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/main/main_shell.dart';

import 'test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Drawer privacy toggle merges label/switch into one semantics node and '
    'stays in sync when tapped',
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
            home: Scaffold(
              body: AppMainDrawer(
                selectedIndex: 0,
                isStatic: true,
                onTabSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // _DrawerPrivacyToggle is private to main_shell.dart; match it by
      // runtimeType so this regression test doesn't need an export.
      final toggleFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_DrawerPrivacyToggle',
      );
      expect(toggleFinder, findsOneWidget);

      final initiallyEnabled = container
          .read(ledgerProvider)
          .preferences
          .privacyModeEnabled;

      // A single merged semantics node should carry the toggled state and
      // the combined label, instead of the InkWell, label text, and
      // GlassSwitch each exposing their own disconnected semantics nodes.
      final data = tester.getSemantics(toggleFinder).getSemanticsData();
      expect(data.label, contains('Privacy mode'));
      expect(data.flagsCollection.isToggled, isNot(Tristate.none));
      expect(
        data.flagsCollection.isToggled,
        initiallyEnabled ? Tristate.isTrue : Tristate.isFalse,
      );

      // Tapping anywhere in the merged region toggles the underlying
      // preference, same as tapping a real SwitchListTile would.
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      expect(
        container.read(ledgerProvider).preferences.privacyModeEnabled,
        !initiallyEnabled,
      );
      final toggledData = tester.getSemantics(toggleFinder).getSemanticsData();
      expect(
        toggledData.flagsCollection.isToggled,
        initiallyEnabled ? Tristate.isFalse : Tristate.isTrue,
      );

      handle.dispose();
    },
  );
}
