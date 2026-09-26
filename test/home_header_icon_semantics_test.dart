import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';

import 'test_harness.dart';

/// Accessibility regression coverage for the Home screen's notifications
/// `HeaderIconButton`. It's a Liquid Glass button (not a plain `IconButton`),
/// so without an explicit `semanticLabel` it announces no description at all
/// to screen readers — a `Tooltip`-based finder would not catch this gap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'notifications header button exposes a semantic label for screen '
    'readers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final handle = tester.ensureSemantics();
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(prefs: prefs),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OneWalletApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The pending/notification badge count is folded into the label (e.g.
      // "Notifications, 2 pending"), so match the base label as a substring
      // rather than pinning the exact count from the sample fixture data.
      expect(find.bySemanticsLabel(RegExp('Notifications')), findsOneWidget);

      handle.dispose();
    },
  );
}
