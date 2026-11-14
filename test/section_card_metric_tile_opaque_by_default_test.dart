// Focused regression test for the shared glass section and content-only
// metrics on a representative routed screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/categories/categories_screen.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('CategoriesScreen uses glass sections without nested metric '
      'GlassCards', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
          home: const CategoriesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sectionCards = find.byType(SectionCard);
    expect(sectionCards, findsWidgets);
    final metricTiles = find.byType(MetricTile);
    expect(metricTiles, findsWidgets);

    for (final element in sectionCards.evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(GlassCard),
        ),
        findsOneWidget,
      );
    }
    for (final element in metricTiles.evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(GlassCard),
        ),
        findsNothing,
      );
    }
  });
}
