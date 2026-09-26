// Focused tests for `RouteScaffold`'s optional `scrollView` parameter
// (lib/src/features/common/route_scaffold.dart), added so lazy/sliver-based
// screens (e.g. many live widget previews on a dashboard) can supply their
// own `CustomScrollView` instead of being eagerly wrapped in the default
// padded `ListView(children: [child])`.
//
// Coverage:
//   1. Existing `child:` callers are unaffected - content is still wrapped
//      in the same padded `ListView` as before.
//   2. A supplied `scrollView:` is used directly as the scaffold body,
//      bypassing the `ListView` wrapper entirely (the caller owns its own
//      scrolling/padding).
//   3. Exactly one of `child`/`scrollView` must be provided - passing both
//      or neither is an API misuse caught by an assertion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/features/common/route_scaffold.dart';

void main() {
  Future<void> pumpMobile(WidgetTester tester, Widget child) async {
    // The desktop/mobile breakpoint in AppResponsiveLayout is 800 logical
    // pixels wide; force a narrower surface so this test deterministically
    // exercises the mobile (single ListView/SafeArea) branch regardless of
    // the default test viewport size.
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // NoSplash avoids the ink_sparkle shader, which is intermittently
        // unavailable in the test environment.
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('child: is still wrapped in the default padded ListView', (
    tester,
  ) async {
    await pumpMobile(
      tester,
      const RouteScaffold(title: 'Child mode', child: Text('child content')),
    );

    expect(find.text('child content'), findsOneWidget);
    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(
      listView.padding,
      const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
    );
  });

  testWidgets(
    'scrollView: is used directly, bypassing the default ListView wrapper',
    (tester) async {
      await pumpMobile(
        tester,
        RouteScaffold(
          title: 'Sliver mode',
          scrollView: CustomScrollView(
            slivers: [SliverToBoxAdapter(child: const Text('sliver content'))],
          ),
        ),
      );

      expect(find.text('sliver content'), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      // No extra ListView should be inserted around the caller's scrollable.
      expect(find.byType(ListView), findsNothing);
    },
  );

  test('providing both child and scrollView is an assertion failure', () {
    expect(
      () => RouteScaffold(
        title: 'Invalid',
        scrollView: const CustomScrollView(slivers: []),
        child: const Text('child'),
      ),
      throwsAssertionError,
    );
  });

  test('providing neither child nor scrollView is an assertion failure', () {
    expect(() => RouteScaffold(title: 'Invalid'), throwsAssertionError);
  });
}
