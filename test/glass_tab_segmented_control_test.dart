import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets('GlassTabSegmentedControl animates continuously with page drag',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(40),
                child: GlassTabSegmentedControl(
                  segments: [
                    GlassSegment(label: 'Keypad', icon: Icon(Icons.dialpad)),
                    GlassSegment(label: 'Details', icon: Icon(Icons.notes)),
                  ],
                ),
              ),
            ),
            body: const TabBarView(
              children: [
                Center(child: Text('Keypad View')),
                Center(child: Text('Details View')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initially at Keypad (page 0)
    expect(find.text('Keypad View'), findsOneWidget);
    AnimatedGlassIndicator indicator =
        tester.widget(find.byType(AnimatedGlassIndicator));
    expect(indicator.alignment, const AlignmentDirectional(-1.0, 0));

    // Start dragging leftward from page 0 towards page 1
    final gesture = await tester.startGesture(const Offset(600, 300));
    // Drag halfway across
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();

    // Mid-drag: indicator alignment must have moved continuously between -1.0 and 1.0
    indicator = tester.widget(find.byType(AnimatedGlassIndicator));
    final align = indicator.alignment as AlignmentDirectional;
    expect(align.start, greaterThan(-1.0));
    expect(align.start, lessThan(1.0));

    // Complete drag across to Details
    await gesture.moveBy(const Offset(-300, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Now settled at Details (page 1)
    expect(find.text('Details View'), findsOneWidget);
    indicator = tester.widget(find.byType(AnimatedGlassIndicator));
    expect(indicator.alignment, const AlignmentDirectional(1.0, 0));
  });
}
