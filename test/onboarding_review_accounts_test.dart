import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid_glass;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';
import 'package:one_wallet_flutter/src/features/onboarding/onboarding_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

// OnboardingScreen (like LoginScreen) is wrapped in LaunchBackdrop, which
// runs a deliberate, continuously-repeating decorative animation
// (AnimationController.repeat(reverse: true)). That keeps a frame scheduled
// forever, so `pumpAndSettle()` — which waits for scheduling to stop — always
// times out here. This is a real backdrop-widget characteristic (owned by
// the launch/brand_widgets scope, not something to "fix"), not a bug in this
// screen, so we drive the test with a bounded number of fixed-duration pumps
// instead, which is enough for the one-shot entrance/page-transition
// animations to finish.
Future<void> _pumpBounded(
  WidgetTester tester, {
  int times = 10,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('review-accounts step shows the added account on an opaque row, '
      'not a per-item BrandFrostedPanel (glass stays reserved for the '
      'standalone profile/account-entry/permissions panels)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await _pumpBounded(tester);

    // PageView only builds pages within its cache extent, so each step's
    // "Continue" button is (re)built fresh as the previous one scrolls
    // out — using `.first` each time reliably targets the current step's
    // controls rather than assuming every step is simultaneously mounted.

    // Step 1 (Profile) -> Step 2 (Use cases).
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').first);
    await _pumpBounded(tester);

    // Step 2 (Use cases) -> Step 3 (Account).
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').first);
    await _pumpBounded(tester);

    // Step 3 (Account): fill in one account and save it, which advances
    // straight to the review step.
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Test Wallet');
    await tester.enterText(textFields.at(1), '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
    await _pumpBounded(tester);

    // Step 4 (Review): the account must render...
    final accountName = find.text('Test Wallet');
    expect(accountName, findsOneWidget);

    // ...but its row must not be wrapped in a BrandFrostedPanel (the
    // bespoke, brand_widgets-owned panel used by the standalone
    // profile/account-entry/permissions panels) anywhere in its ancestor
    // chain, nor in the real `package:liquid_glass_widgets` GlassCard
    // (imported here under a distinct `liquid_glass.` prefix so the two
    // "glass card" concepts can never be confused with each other):
    // glass is reserved for navigation/control chrome and those standalone
    // panels, not this scrolling per-account list row. (PageView only
    // builds pages within its cache extent, so asserting a fixed panel
    // *count* across the whole tree would be brittle; checking this
    // specific row's ancestry is the precise, page-agnostic regression
    // check.)
    expect(
      find.ancestor(of: accountName, matching: find.byType(BrandFrostedPanel)),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: accountName,
        matching: find.byType(liquid_glass.GlassCard),
      ),
      findsNothing,
    );
  });
}
