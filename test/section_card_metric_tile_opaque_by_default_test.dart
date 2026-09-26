// Focused regression test confirming the shared `SectionCard`/`MetricTile`
// widgets (lib/src/widgets/app_kit.dart) render opaque by default - not
// wrapped in a refractive `GlassCard` - when used by screens in this
// feature's ownership (categories/settings/loans/common).
//
// `SectionCard`/`MetricTile` used to unconditionally wrap themselves in
// `GlassCard`, stacking a refractive surface into every scrolling section on
// every screen (an anti-pattern per the liquid_glass_widgets package
// guidance - reserve glass for the navigation/control layer, and never
// nest one refractive surface inside another). The shared widgets were
// fixed to default to `glass: false` (a plain opaque `Container`), matching
// the same pattern `PremiumRow` already used. None of this feature's call
// sites ever passed `glass: true` (the parameter didn't exist before), so
// they all pick up the corrected default automatically - this test locks
// that in for a real screen rather than trusting the shared widget's own
// default in isolation.
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

  testWidgets('CategoriesScreen\'s SectionCard and MetricTile render opaque by '
      'default (no GlassCard)', (tester) async {
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

    for (final finder in [sectionCards, metricTiles]) {
      for (final element in finder.evaluate()) {
        final glassInside = find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(GlassCard),
        );
        expect(
          glassInside,
          findsNothing,
          reason:
              '${element.widget.runtimeType} must stay opaque by default '
              '(no nested GlassCard) on a scrolling screen.',
        );
      }
    }
  });
}
