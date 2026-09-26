import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/home/home_widget_card.dart';

/// Regression coverage for MiniLineChart's touch-tooltip painter: it used to
/// hold a `BuildContext` field and call `Theme.of(context)` from inside
/// `paint()` to resolve the touch-dot background color. That's resolved via
/// a themed color passed in from the widget's build method instead, so a
/// drag gesture (which repaints every frame without rebuilding the parent
/// widget tree) must keep working without throwing and must reflect the
/// current theme's surface color.
void main() {
  testWidgets(
    'dragging across the chart repaints the touch tooltip without error '
    'and using the themed surface color',
    (tester) async {
      const surfaceColor = Color(0xFF123456);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light().copyWith(
              surface: surfaceColor,
            ),
          ),
          home: Scaffold(
            body: MiniLineChart(
              values: const [10, 40, 15, 60, 25],
              tooltipFormatter: (value) => value.toStringAsFixed(0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);

      final center = tester.getCenter(find.byType(MiniLineChart));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(20, 5));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
