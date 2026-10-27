import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';
import 'package:one_wallet_flutter/src/features/updates/updates_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

class _UpdateFixture extends AppUpdateProvider {
  _UpdateFixture(Future<void> Function(String) notify)
    : super(notifyUpdate: notify);
  int downloads = 0;
  Future<void> discover(AppUpdateRelease release) =>
      publishAvailableRelease(release, allReleases: [release]);
  void installedVersion() {
    state = state.copyWith(
      currentVersionName: '2.2.01',
      currentVersionCode: 2104201,
    );
  }

  @override
  Future<void> downloadUpdate() async {
    downloads++;
  }
}

AppUpdateRelease _release() => AppUpdateRelease(
  id: 'stable-2102204',
  platform: 'android',
  channel: 'stable',
  status: 'published',
  versionName: '2.2.04',
  versionCode: 2102204,
  runtimeVersion: '2.2.04',
  releaseType: 'patch',
  requirement: 'optional',
  mandatory: false,
  minimumSupportedVersionCode: 0,
  publishedAt: '2026-10-27T17:00:00Z',
  changelog: Changelog(
    newFeatures: [],
    bugFixes: ['Keep notification icons'],
    notes: [],
  ),
  apk: ApkMetadata(
    downloadUrl: 'https://example.test/update.apk',
    fileName: 'update.apk',
    sizeBytes: 1024 * 1024,
    sha256: 'a' * 64,
    architecture: 'arm64-v8a',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'missing native icon leaves the discovered release available and retryable',
    () async {
      var fail = true;
      var calls = 0;
      final provider = _UpdateFixture((version) async {
        calls++;
        if (fail) {
          throw PlatformException(
            code: 'invalid_icon',
            message: 'The resource ic_notification could not be found.',
          );
        }
      });
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      final release = _release();
      provider.installedVersion();
      await provider.discover(release);

      expect(provider.state.status, UpdateStatus.idle);
      expect(provider.state.latestRelease, same(release));
      expect(provider.state.errorMessage, isNull);
      expect(
        provider.state.notificationWarning,
        contains('still download and install'),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('lastNotifiedVersionCode.stable'), isNull);

      fail = false;
      await provider.discover(release);
      expect(calls, 2);
      expect(provider.state.notificationWarning, isNull);
      expect(
        prefs.getInt('lastNotifiedVersionCode.stable'),
        release.versionCode,
      );
      await provider.discover(release);
      expect(
        calls,
        2,
        reason: 'Only successful notification delivery is deduplicated.',
      );
    },
  );

  test(
    'other notification or permission exceptions cannot become update lookup failures',
    () async {
      final provider = _UpdateFixture(
        (_) async => throw PlatformException(
          code: 'permission_denied',
          message: 'Notifications are blocked.',
        ),
      );
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      await provider.discover(_release());
      expect(provider.state.status, UpdateStatus.idle);
      expect(provider.state.latestRelease, isNotNull);
      expect(provider.state.notificationWarning, isNotNull);
      expect(provider.state.errorMessage, isNull);
    },
  );

  test(
    'notification failure after provider disposal does not publish state',
    () async {
      final delivered = Completer<void>();
      final started = Completer<void>();
      final provider = _UpdateFixture((_) {
        started.complete();
        return delivered.future;
      });
      await Future<void>.delayed(Duration.zero);
      final pending = provider.discover(_release());
      await started.future;
      provider.dispose();
      delivered.completeError(PlatformException(code: 'invalid_icon'));
      await expectLater(pending, completes);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('lastNotifiedVersionCode.stable'), isNull);
    },
  );

  testWidgets('the screenshot failure retains an actionable install button', (
    tester,
  ) async {
    final provider = _UpdateFixture(
      (_) async => throw PlatformException(
        code: 'invalid_icon',
        message: 'Missing ic_notification',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      provider.installedVersion();
      await provider.discover(_release());
    });
    final container = ProviderContainer(
      overrides: [appUpdateProvider.overrideWith((ref) => provider)],
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
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('Update check unavailable'), findsNothing);
    expect(find.textContaining('still download and install'), findsOneWidget);
    final install = find.text('Install Update (1.0 MB)');
    expect(install, findsOneWidget);
    await tester.ensureVisible(install);
    await tester.tap(install);
    expect(provider.downloads, 1);
  });
}
