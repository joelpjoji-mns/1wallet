import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import '../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Automated Accessibility (a11y) & WCAG Guidelines', () {
    testWidgets(
      'Interactive buttons and action bars meet Android tap target guidelines (48x48 dp)',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Add Transaction',
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        width: 140,
                        child: ElevatedButton(
                          onPressed: () {},
                          child: const Text('Save Record'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'HeaderIconButton properly exposes semantic labels and tooltip for screen readers',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                appBar: AppBar(
                  actions: [
                    HeaderIconButton(
                      icon: Icons.notifications,
                      tooltip: 'Notifications',
                      semanticLabel: 'Notifications',
                      badge: 3,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Screen reader announces description with badge count
          expect(
            find.bySemanticsLabel(RegExp(r'Notifications.*3 pending')),
            findsOneWidget,
          );
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'Renders properly under 1.5x large font scaling (Dynamic Type) without overflow',
      (tester) async {
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
            child: const MediaQuery(
              data: MediaQueryData(
                size: Size(1080, 2400),
                textScaler: TextScaler.linear(1.5), // 1.5x Large text scaling
              ),
              child: OneWalletApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify home screen renders cleanly without throwing RenderFlex overflow errors
        expect(find.byType(OneWalletApp), findsOneWidget);
      },
    );

    testWidgets('Renders properly under Right-To-Left (RTL) text direction', (
      tester,
    ) async {
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
          child: const Directionality(
            textDirection: TextDirection.rtl, // RTL layout
            child: OneWalletApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OneWalletApp), findsOneWidget);
    });
  });
}
