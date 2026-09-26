import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';
import 'package:one_wallet_flutter/src/features/updates/updates_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

// AppUpdateProvider's real constructor fires off async Firebase/Firestore
// work via _init(), which is unreachable in a plain `flutter test` run
// (Firebase.apps is empty, so it returns early without touching state).
// Setting `state` here is legitimate subclass access (the setter is
// @protected, not private) — the standard state_notifier testing pattern
// for injecting a fixture without spinning up Firebase.
class _FixtureUpdateProvider extends AppUpdateProvider {
  _FixtureUpdateProvider(AppUpdateState fixture) {
    state = fixture;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'update status, release-details, and changelog sections render opaque '
    '(no GlassCard): glass is reserved for navigation/control chrome, not '
    'this scrolling page\'s content sections',
    (tester) async {
      final release = AppUpdateRelease(
        id: 'r1',
        platform: 'android',
        channel: 'stable',
        status: 'published',
        versionName: '1.2.3',
        versionCode: 123,
        runtimeVersion: '1.0.0',
        releaseType: 'ota',
        requirement: 'optional',
        mandatory: false,
        minimumSupportedVersionCode: 100,
        publishedAt: '2026-01-01T00:00:00.000Z',
        changelog: Changelog(
          newFeatures: const ['Feature A'],
          bugFixes: const ['Fix B'],
          notes: const ['Note C'],
        ),
        apk: ApkMetadata(
          downloadUrl: 'https://example.com/app.apk',
          fileName: 'app.apk',
          sizeBytes: 20 * 1024 * 1024,
          sha256: 'deadbeef',
          architecture: 'arm64',
        ),
      );
      final fixture = AppUpdateState(
        status: UpdateStatus.idle,
        latestRelease: release,
        currentVersionName: '1.2.2',
        currentVersionCode: 122,
      );

      final container = ProviderContainer(
        overrides: [
          appUpdateProvider.overrideWith(
            (ref) => _FixtureUpdateProvider(fixture),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const UpdatesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: all three content sections actually rendered from the
      // fixture (otherwise the GlassCard absence check below would be
      // vacuous).
      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Release Details'), findsOneWidget);
      expect(find.text("What's new in 1.2.3"), findsOneWidget);
      expect(find.text('Feature A'), findsOneWidget);
      expect(find.text('Fix B'), findsOneWidget);
      expect(find.text('Note C'), findsOneWidget);

      // Structural regression: none of this scrolling content uses
      // GlassCard.
      expect(find.byType(GlassCard), findsNothing);
    },
  );
}
