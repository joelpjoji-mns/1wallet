import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  group('SectionCard surface defaults to opaque, glass is opt-in', () {
    testWidgets(
      'default SectionCard renders an opaque section with no glass/'
      'BackdropFilter',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SectionCard(
                title: 'Appearance',
                child: const Text('Body'),
              ),
            ),
          ),
        );

        // Settings/Categories/Loans/Sync/... all stack several SectionCards
        // as plain content sections on one scrolling screen, so the default
        // surface must not pull in the package's refractive GlassCard shader
        // per section.
        expect(find.byType(GlassCard), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(SectionCard),
            matching: find.byType(Container).first,
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, isNotNull);
        expect(decoration.color, isNot(Colors.transparent));
      },
    );

    testWidgets('SectionCard(glass: true) opts into a GlassCard surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionCard(
              title: 'Appearance',
              glass: true,
              child: const Text('Body'),
            ),
          ),
        ),
      );

      expect(find.byType(GlassCard), findsOneWidget);
    });
  });

  group('MetricTile surface defaults to opaque, glass is opt-in', () {
    testWidgets(
      'default MetricTile renders an opaque tile with no glass/'
      'BackdropFilter',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MetricTile(
                label: 'Loans',
                value: '3',
                icon: Icons.account_balance_outlined,
              ),
            ),
          ),
        );

        expect(find.byType(GlassCard), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MetricTile),
            matching: find.byType(Container).first,
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, isNotNull);
        expect(decoration.color, isNot(Colors.transparent));
      },
    );

    testWidgets('MetricTile(glass: true) opts into a GlassCard surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MetricTile(
              label: 'Loans',
              value: '3',
              icon: Icons.account_balance_outlined,
              glass: true,
            ),
          ),
        ),
      );

      expect(find.byType(GlassCard), findsOneWidget);
    });
  });

  testWidgets(
    'a SectionCard summary row of MetricTiles (the real-world composition '
    'used across Loans/Categories/Sync/Currencies/...) has zero nested '
    'GlassCards by default',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionCard(
              title: 'Loan control center',
              subtitle: 'Loan count and next scheduled EMI.',
              child: const Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Loans',
                      value: '3',
                      icon: Icons.account_balance_outlined,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: MetricTile(
                      label: 'Total EMI',
                      value: r'$450',
                      icon: Icons.event_repeat_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Previously this composition nested a refractive GlassCard (each
      // MetricTile) inside another refractive GlassCard (the SectionCard) —
      // the package's own "never nest refractive glass inside refractive
      // glass" anti-pattern. With both defaulting to opaque, there should be
      // no GlassCard anywhere in this tree at all.
      expect(find.byType(GlassCard), findsNothing);
      expect(find.byType(MetricTile), findsNWidgets(2));
    },
  );
}
