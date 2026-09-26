import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';

void main() {
  group('BrandFrostedPanel', () {
    testWidgets('uses the shared Liquid Glass package surface', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BrandFrostedPanel(child: Text('Body'))),
        ),
      );

      expect(find.byType(GlassCard), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('keeps its glass component when high contrast is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(highContrast: true),
          child: MaterialApp(
            home: Scaffold(body: BrandFrostedPanel(child: Text('Body'))),
          ),
        ),
      );

      expect(find.byType(GlassCard), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });
  });
}
