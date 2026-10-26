import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets('RightSwipeToOpenDrawer triggers callback on swipe right and not on swipe left', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: RightSwipeToOpenDrawer(
                onOpenDrawer: () => opened = true,
                child: const ColoredBox(
                  color: Colors.blue,
                  child: Text('Swipe Me'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Swipe left: should not trigger
    await tester.drag(find.text('Swipe Me'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(opened, isFalse);

    // Swipe right: should trigger
    await tester.drag(find.text('Swipe Me'), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}
