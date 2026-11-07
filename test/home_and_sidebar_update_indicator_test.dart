import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/main/main_shell.dart';
import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

class _MockAppUpdateProvider extends AppUpdateProvider {
  _MockAppUpdateProvider({AppUpdateRelease? release}) {
    if (release != null) {
      state = state.copyWith(latestRelease: release);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final updateRelease = AppUpdateRelease(
    id: '2.1.107',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.107',
    versionCode: 201107,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-11-01T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const ['New test update feature'],
      bugFixes: const [],
      notes: const [],
    ),
  );

  testWidgets(
    'AppScreen reflects menuIndicator on hamburger menu button in mobile layout',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: AppScreen(
                title: '1Wallet',
                onMenuPressed: () {},
                menuIndicator: true,
                child: const Text('Content'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menuAction = tester.widget<AppMenuAction>(find.byType(AppMenuAction));
      expect(menuAction.showIndicator, isTrue);

      expect(
        find.bySemanticsLabel('Open menu, update available'),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  testWidgets(
    'AppScreen hides menuIndicator on hamburger menu button when false in mobile layout',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: AppScreen(
                title: '1Wallet',
                onMenuPressed: () {},
                menuIndicator: false,
                child: const Text('Content'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menuAction = tester.widget<AppMenuAction>(find.byType(AppMenuAction));
      expect(menuAction.showIndicator, isFalse);
      expect(
        find.bySemanticsLabel('Open menu'),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  testWidgets(
    'AppMainDrawer shows updates badge when update is available',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(),
          appUpdateProvider.overrideWith(
            (ref) => _MockAppUpdateProvider(release: updateRelease),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              drawer: AppMainDrawer(
                selectedIndex: 0,
                onTabSelected: (_) {},
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open drawer
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      // Scroll to ensure bottom section is visible if needed
      await tester.scrollUntilVisible(find.text('Updates'), 200);
      await tester.pumpAndSettle();

      // Verify "Updates" row is present with badge "!"
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    },
  );
}
