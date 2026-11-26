import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  testWidgets('startup message stays reachable on short large-text screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: child!,
        ),
        home: const BrandedLoadingState(
          stage: StartupStage.wallet,
          message:
              'Checking your encrypted wallet and securely recovering local data before continuing. Please keep this screen open.',
          progress: 0.5,
        ),
      ),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(LinearProgressIndicator));
    await tester.pump();
    expect(
      tester.getBottomLeft(find.byType(LinearProgressIndicator)).dy,
      lessThanOrEqualTo(296),
    );
  });

  group('Reduce Motion respected by launch animations', () {
    testWidgets('staggered content appears immediately with reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(
            body: StaggeredFadeIn(
              delay: Duration(seconds: 1),
              child: Text('Ready'),
            ),
          ),
        ),
      );

      final content = find.byType(StaggeredFadeIn);
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(of: content, matching: find.byType(FadeTransition)),
      );
      final slides = tester.widgetList<SlideTransition>(
        find.descendant(of: content, matching: find.byType(SlideTransition)),
      );
      expect(find.text('Ready'), findsOneWidget);
      expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
      expect(
        slides.every((slide) => slide.position.value == Offset.zero),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
    });

    testWidgets('enabling reduced motion finishes a pending entrance', (
      tester,
    ) async {
      var reduceMotion = false;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduceMotion),
                child: child!,
              ),
              home: const Scaffold(
                body: StaggeredFadeIn(
                  delay: Duration(seconds: 1),
                  child: Text('Ready'),
                ),
              ),
            );
          },
        ),
      );
      final fade = find.descendant(
        of: find.byType(StaggeredFadeIn),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
      update(() => reduceMotion = true);
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      update(() => reduceMotion = false);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    });

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
