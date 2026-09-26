import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets(
    'AppSwitchListTile merges title/subtitle/switch into one semantics node',
    (tester) async {
      final handle = tester.ensureSemantics();

      var value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppSwitchListTile(
                  title: const Text('Quiet hours'),
                  subtitle: const Text('Mute notifications overnight'),
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                );
              },
            ),
          ),
        ),
      );

      // A single merged semantics node should carry the toggled state and
      // the combined label, instead of the title, subtitle, and Switch each
      // exposing their own separate semantics nodes to screen readers.
      // `SemanticsNode.hasFlag`/`.label` only reflect the boundary node's own
      // *unmerged* local config; the data actually exposed to platform
      // accessibility services (TalkBack/VoiceOver) is the fully assembled
      // `SemanticsData`, so assert against `getSemanticsData()` here.
      final data = tester
          .getSemantics(find.byType(AppSwitchListTile))
          .getSemanticsData();
      expect(data.flagsCollection.isToggled, isNot(Tristate.none));
      expect(data.flagsCollection.isToggled, Tristate.isFalse);
      expect(data.label, contains('Quiet hours'));
      expect(data.label, contains('Mute notifications overnight'));

      // Tapping the merged region toggles the switch through onChanged, same
      // as tapping the Switch itself would.
      await tester.tap(find.byType(AppSwitchListTile));
      await tester.pumpAndSettle();

      final toggledData = tester
          .getSemantics(find.byType(AppSwitchListTile))
          .getSemanticsData();
      expect(toggledData.flagsCollection.isToggled, Tristate.isTrue);
      expect(value, isTrue);

      handle.dispose();
    },
  );

  testWidgets(
    'AppSwitchListTile uses the package GlassSwitch control (not the plain '
    'Material Switch), matching the app-wide liquid_glass_widgets usage',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSwitchListTile(
              title: const Text('Quiet hours'),
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(GlassSwitch), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    },
  );

  testWidgets(
    'AppSwitchListTile does not nest its GlassSwitch inside a refractive '
    'GlassCard when composed in the real SectionCard summary pattern',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionCard(
              title: 'Notifications',
              child: AppSwitchListTile(
                title: const Text('Notification inbox'),
                value: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // SectionCard defaults to an opaque surface, so nesting the switch's
      // GlassSwitch inside it does not create the "refractive glass inside
      // refractive glass" anti-pattern the package warns against.
      expect(find.byType(GlassSwitch), findsOneWidget);
      expect(find.byType(GlassCard), findsNothing);
    },
  );

  testWidgets(
    'a disabled AppSwitchListTile (onChanged: null) ignores taps instead of '
    'crashing on GlassSwitch\'s non-nullable onChanged',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSwitchListTile(
              title: Text('Quiet hours'),
              value: false,
              onChanged: null,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(AppSwitchListTile));
      await tester.pumpAndSettle();

      // Still off — a disabled tile must not toggle, and the widget itself
      // has no internal state that could have silently changed.
      final data = tester
          .getSemantics(find.byType(AppSwitchListTile))
          .getSemanticsData();
      expect(data.flagsCollection.isToggled, Tristate.isFalse);
      expect(tester.takeException(), isNull);

      handle.dispose();
    },
  );
}
