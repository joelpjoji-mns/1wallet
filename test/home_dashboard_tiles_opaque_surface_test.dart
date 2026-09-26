import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/features/home/home_widget_card.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

/// Structural regression coverage for the Liquid Glass performance fix:
/// `HomeWidgetCard` and `DashboardCard` wrap scrolling dashboard/list/chart
/// content, which the `liquid_glass_widgets` package's own guidance says
/// should stay opaque (blur is reserved for the navigation/control layer).
/// These tiles must no longer render a `GlassCard`/blur surface, and must
/// still expose a themed, visible, tappable opaque container.
void main() {
  testWidgets(
    'HomeWidgetCard renders an opaque themed surface instead of GlassCard',
    (tester) async {
      const scheme = ColorScheme.light(
        surface: Color(0xFF112233),
        outlineVariant: Color(0xFF445566),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Scaffold(
            body: HomeWidgetCard(
              title: 'Net worth',
              icon: Icons.account_balance_outlined,
              child: const Text('tile body'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No glass/blur surface should be present anywhere under the tile.
      expect(find.byType(GlassCard), findsNothing);
      expect(find.byType(AdaptiveLiquidGlassLayer), findsNothing);

      // The card content still renders.
      expect(find.text('Net worth'), findsOneWidget);
      expect(find.text('tile body'), findsOneWidget);

      // An opaque, themed container backs the tile.
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text('tile body'), matching: find.byType(Container))
            .last,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, scheme.surface);
      expect(decoration.border, isNotNull);
    },
  );

  testWidgets(
    'DashboardCard renders an opaque themed surface instead of GlassCard '
    'and still forwards taps',
    (tester) async {
      const scheme = ColorScheme.light(surface: Color(0xFF223344));
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Scaffold(
            body: DashboardCard(
              onTap: () => tapped = true,
              child: const Text('dashboard body'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GlassCard), findsNothing);
      expect(find.byType(AdaptiveLiquidGlassLayer), findsNothing);
      expect(find.text('dashboard body'), findsOneWidget);

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('dashboard body'),
              matching: find.byType(Container),
            )
            .last,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, scheme.surface);

      await tester.tap(find.byType(DashboardCard));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    },
  );
}
