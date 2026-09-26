// Focused tests for `PermissionsSetupScreen`'s navigation chrome
// (lib/src/features/settings/permissions_setup_screen.dart), covering the
// Material AppBar -> GlassAppBar conversion.
//
// This screen never had an explicit `leading:` before the conversion, so it
// relied entirely on Material's AppBar auto-injecting a back button when
// `Navigator.canPop(context)`. GlassAppBar has no such auto-detection, so
// the conversion had to replicate that explicitly
// (`Navigator.of(context).canPop() ? const AppBackAction() : null`) - this
// test guards that replication for both the root-route (no back button) and
// pushed-route (back button that pops) cases, mirroring the same regression
// already found and fixed in RouteScaffold's desktop path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/features/settings/permissions_setup_screen.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
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

  testWidgets('as a root route it shows no back button', (tester) async {
    await pump(tester, const PermissionsSetupScreen());

    expect(find.text('Setup'), findsOneWidget);
    expect(find.byType(AppBackAction), findsNothing);
  });

  testWidgets('when pushed it shows a back button that pops', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const PermissionsSetupScreen(),
                ),
              ),
              child: const Text('Push setup'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Push setup'));
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsOneWidget);

    final backButton = find.byType(AppBackAction);
    expect(backButton, findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsNothing);
    expect(find.text('Push setup'), findsOneWidget);

    handle.dispose();
  });
}
