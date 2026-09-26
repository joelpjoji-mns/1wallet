import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';

void main() {
  group('BrandFrostedPanel', () {
    testWidgets(
      'renders a translucent frosted blur by default',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: BrandFrostedPanel(child: Text('Body'))),
          ),
        );

        final filter = tester.widget<BackdropFilter>(
          find.byType(BackdropFilter),
        );
        expect(filter.filter, isA<ImageFilter>());

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(BrandFrostedPanel),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        // Translucent white tint, not the opaque Reduce Transparency
        // fallback color.
        expect(decoration.color!.a, lessThan(1.0));
      },
    );

    testWidgets(
      'falls back to an opaque panel (no blur) when Reduce Transparency is '
      'enabled, mirroring how liquid_glass_widgets degrades its own '
      'GlassCard',
      (tester) async {
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(highContrast: true),
            child: MaterialApp(
              home: Scaffold(body: BrandFrostedPanel(child: Text('Body'))),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(BrandFrostedPanel),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        // Fully opaque fallback surface instead of a translucent blur.
        expect(decoration.color!.a, 1.0);
      },
    );
  });
}
