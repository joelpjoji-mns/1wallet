import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  group('PremiumRow surface defaults to opaque, glass is opt-in', () {
    testWidgets(
      'default PremiumRow renders an opaque row with no glass/BackdropFilter',
      (tester) async {
        var tapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PremiumRow(
                icon: Icons.category_outlined,
                title: 'Groceries',
                onTap: () => tapped = true,
              ),
            ),
          ),
        );

        // Dense scrolling lists (accounts/categories/currencies/etc.) render
        // many PremiumRow instances at once, so the default surface must not
        // pull in the package's refractive GlassCard shader per row.
        expect(find.byType(GlassCard), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(PremiumRow),
            matching: find.byType(Container).first,
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, isNotNull);
        expect(decoration.color, isNot(Colors.transparent));

        await tester.tap(find.byType(PremiumRow));
        expect(tapped, isTrue);
      },
    );

    testWidgets('PremiumRow(glass: true) opts into a GlassCard surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumRow(
              icon: Icons.category_outlined,
              title: 'Groceries',
              glass: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(GlassCard), findsOneWidget);
    });
  });
}
