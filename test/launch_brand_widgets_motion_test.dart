import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';

void main() {
  group('Reduce Motion respected by launch animations', () {
    testWidgets(
      'LaunchBackdrop stops its continuous float animation and its heavy '
      'BackdropFilter blur recompute when Reduce Motion is enabled',
      (tester) async {
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: Scaffold(body: LaunchBackdrop())),
          ),
        );

        // AnimationController.repeat() never completes on its own, so if
        // Reduce Motion weren't respected this would time out instead of
        // settling.
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'LaunchBrandMark stops its continuous pulse/glint animation when '
      'Reduce Motion is enabled',
      (tester) async {
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Scaffold(body: Center(child: LaunchBrandMark())),
            ),
          ),
        );

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'LaunchBrandMark(animated: false) still settles regardless of Reduce '
      'Motion',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: LaunchBrandMark(animated: false)),
            ),
          ),
        );

        await tester.pumpAndSettle();
      },
    );
  });
}
