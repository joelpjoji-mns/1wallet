// Focused tests for RouteScaffold's GlassAppBar leading-button behavior
// (lib/src/features/common/route_scaffold.dart), added when the shared
// Material AppBar was replaced by liquid_glass_widgets' GlassAppBar in both
// the mobile and desktop layout paths.
//
// This matters because GlassAppBar - unlike Material's AppBar - has no
// built-in awareness of the surrounding Scaffold/Navigator: Material's
// AppBar auto-injects a drawer button when `Scaffold.of(context).hasDrawer`
// and a back button when `Navigator.canPop(context)`, whenever no explicit
// `leading` is supplied. GlassAppBar does neither; RouteScaffold has to
// replicate both explicitly. The desktop path initially only handled the
// drawer case (`leading: hasDrawer ? SizedBox.shrink() : null`), silently
// dropping the back button on every pushed desktop sub-route without a
// persistent drawer - this file guards against that regression alongside
// the already-correct mobile behavior.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/common/route_scaffold.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAtWidth(
    WidgetTester tester,
    double width,
    Widget home,
  ) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  // `hasDrawer: true` (with no explicit `drawer:` override) renders the real
  // `AppMainDrawer`, a `ConsumerWidget` that needs Riverpod providers - the
  // plain `pumpAtWidth` MaterialApp has no ProviderScope, which is unrelated
  // to the GlassAppBar migration under test here.
  Future<void> pumpAtWidthWithProviders(
    WidgetTester tester,
    double width,
    Widget home,
  ) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
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
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('mobile layout (< 800px)', () {
    testWidgets('a root route with no drawer shows no leading button', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        400,
        const RouteScaffold(title: 'Root', child: Text('body')),
      );

      expect(find.byType(AppBackAction), findsNothing);
      expect(find.byType(AppMenuAction), findsNothing);
    });

    testWidgets('a pushed route with no drawer shows a back button that pops', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await pumpAtWidth(
        tester,
        400,
        Builder(
          builder: (context) => RouteScaffold(
            title: 'Home',
            child: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const RouteScaffold(
                      title: 'Detail',
                      child: Text('detail body'),
                    ),
                  ),
                ),
                child: const Text('Push detail'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push detail'));
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsOneWidget);

      final backButton = find.byType(AppBackAction);
      expect(backButton, findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Detail'), findsNothing);
      handle.dispose();
    });

    testWidgets('a drawer takes precedence and opens via the menu button', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        400,
        RouteScaffold(
          title: 'With drawer',
          hasDrawer: true,
          drawer: const Drawer(child: Text('drawer content')),
          child: const Text('body'),
        ),
      );

      expect(find.byType(AppBackAction), findsNothing);
      final menuButton = find.byType(AppMenuAction);
      expect(menuButton, findsOneWidget);

      expect(find.text('drawer content'), findsNothing);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      expect(find.text('drawer content'), findsOneWidget);
    });
  });

  group('desktop layout (>= 800px)', () {
    testWidgets(
      'a pushed route with no persistent drawer still shows a working '
      'back button (regression: GlassAppBar has no automatic Navigator '
      'awareness like Material\'s AppBar)',
      (tester) async {
        await pumpAtWidth(
          tester,
          1000,
          Builder(
            builder: (context) => RouteScaffold(
              title: 'Home',
              child: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const RouteScaffold(
                        title: 'Detail',
                        child: Text('detail body'),
                      ),
                    ),
                  ),
                  child: const Text('Push detail'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Push detail'));
        await tester.pumpAndSettle();
        expect(find.text('Detail'), findsOneWidget);

        final backButton = find.byType(AppBackAction);
        expect(backButton, findsOneWidget);

        await tester.tap(backButton);
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets(
      'a persistent drawer suppresses the leading button on desktop (no back '
      'button, no menu button - matches the pre-existing SizedBox.shrink '
      'behavior)',
      (tester) async {
        // Desktop always renders the real AppMainDrawer as the persistent
        // sidebar whenever a drawer is requested (it ignores any custom
        // `drawer:` override, unlike the mobile path) - use the
        // provider-backed pump helper so that ConsumerWidget renders
        // correctly instead of failing to find its Riverpod ancestors.
        await pumpAtWidthWithProviders(
          tester,
          1000,
          const RouteScaffold(
            title: 'Persistent drawer',
            hasDrawer: true,
            child: Text('body'),
          ),
        );

        // On desktop the drawer renders as a persistent sidebar (not a real
        // Scaffold drawer), so the app bar's leading slot must stay empty.
        expect(find.byType(AppBackAction), findsNothing);
        expect(find.byType(AppMenuAction), findsNothing);
      },
    );
  });
}
