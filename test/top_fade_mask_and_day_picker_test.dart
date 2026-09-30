import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/features/accounts/account_editor_screen.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets('AppTopFadeMask applies ShaderMask with BlendMode.dstIn', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppTopFadeMask(
            fadeHeight: 28.0,
            child: SizedBox(
              width: 200,
              height: 200,
              child: Text('Content'),
            ),
          ),
        ),
      ),
    );

    final shaderMaskFinder = find.byType(ShaderMask);
    expect(shaderMaskFinder, findsOneWidget);

    final shaderMask = tester.widget<ShaderMask>(shaderMaskFinder);
    expect(shaderMask.blendMode, equals(BlendMode.dstIn));

    // Verify shader callback executes without errors
    final shader = shaderMask.shaderCallback(const Rect.fromLTWH(0, 0, 200, 200));
    expect(shader, isNotNull);
  });

  testWidgets('showDayOfMonthPicker displays days 1 to 31 and picks a day', (tester) async {
    int? pickedDay;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                pickedDay = await showDayOfMonthPicker(
                  context: context,
                  title: 'Select Due Date',
                  initialDay: 5,
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );

    // Tap to open picker
    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    // Verify picker title and days are shown
    expect(find.text('Select Due Date'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);

    // Tap day 15
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    // Verify day 15 was returned
    expect(pickedDay, equals(15));
  });
}
