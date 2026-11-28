import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';
import 'package:one_wallet_flutter/src/features/updates/play_store_update_service.dart';
import 'package:one_wallet_flutter/src/features/updates/play_update_sheet.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayStoreUpdateService Unit Tests', () {
    test('initial state is idle', () {
      final service = PlayStoreUpdateService();
      expect(service.state.status, PlayStoreUpdateStatus.idle);
      expect(service.state.updateInfo, isNull);
      expect(service.state.errorMessage, isNull);
    });

    test(
      'checkForUpdate sets notSupported on non-Android test environment',
      () async {
        final service = PlayStoreUpdateService();
        final result = await service.checkForUpdate();
        expect(result, isNull);
        expect(service.state.status, PlayStoreUpdateStatus.notSupported);
      },
    );

    test('state copyWith behaves immutably', () {
      const initial = PlayStoreUpdateState();
      final updated = initial.copyWith(
        status: PlayStoreUpdateStatus.updateAvailable,
        errorMessage: 'Test error',
      );
      expect(updated.status, PlayStoreUpdateStatus.updateAvailable);
      expect(updated.errorMessage, 'Test error');

      final cleared = updated.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
      expect(cleared.status, PlayStoreUpdateStatus.updateAvailable);
    });
  });

  _dailyCheckTests();

  testWidgets(
    'update offer explains the required Play screens without promises',
    (tester) async {
      final gateway = _FakeGateway(
        info: _info(availability: UpdateAvailability.updateAvailable),
      );
      final service = PlayStoreUpdateService(gateway: gateway);
      await service.checkForUpdate();
      final container = ProviderContainer(
        overrides: [playStoreUpdateProvider.overrideWith((ref) => service)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: PlayUpdateSheet()),
          ),
        ),
      );
      expect(
        find.text('Google Play asks you to confirm the update'),
        findsOneWidget,
      );
      expect(
        find.text('Google Play handles installation and the app restart'),
        findsOneWidget,
      );
      expect(find.text('Downloads while you keep using the app'), findsNothing);
      expect(
        find.textContaining('its own update and installation screens'),
        findsOneWidget,
      );
    },
  );

  testWidgets('update sheet shows live download progress', (tester) async {
    final gateway = _FakeGateway(
      info: _info(
        availability: UpdateAvailability.updateAvailable,
        installStatus: InstallStatus.downloading,
      ),
    );
    final service = PlayStoreUpdateService(gateway: gateway);
    await service.checkForUpdate();
    final container = ProviderContainer(
      overrides: [playStoreUpdateProvider.overrideWith((ref) => service)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PlayUpdateSheet()),
        ),
      ),
    );
    gateway.progressController.add(
      const PlayUpdateProgress(
        status: InstallStatus.downloading,
        bytesDownloaded: 3 * 1024 * 1024,
        totalBytes: 12 * 1024 * 1024,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Downloading update'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('3.0 MB of 12.0 MB'), findsOneWidget);

    gateway.progressController.add(
      const PlayUpdateProgress(
        status: InstallStatus.downloaded,
        bytesDownloaded: 12 * 1024 * 1024,
        totalBytes: 12 * 1024 * 1024,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Update downloaded'), findsOneWidget);
    // No "Later": the update installs and restarts on its own.
    expect(find.byKey(const ValueKey('play-update-secondary')), findsNothing);
    expect(find.byKey(const ValueKey('play-update-primary')), findsNothing);
    expect(gateway.completes, 0);

    await tester.pump(const Duration(seconds: 2));
    expect(gateway.completes, 1);
    expect(service.state.status, PlayStoreUpdateStatus.installing);
    expect(find.text('Installing…'), findsOneWidget);
  });

  group('Settings Screen Updates & Version Section Widget Tests', () {
    testWidgets(
      'renders App updates & version section and opens Whats New sheet',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            ...authenticatedSampleOverrides(prefs: prefs),
            packageInfoProvider.overrideWith(
              (ref) async => PackageInfo(
                appName: '1Wallet',
                packageName: 'com.joelpjoji.one.wallet',
                version: '1.0.14',
                buildNumber: '14',
                buildSignature: '',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll down to reveal App updates & version section
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pumpAndSettle();

        // Find the App updates & version section
        expect(find.text('App updates & version'), findsOneWidget);
        expect(find.textContaining('1Wallet v1.0.14 (14)'), findsOneWidget);
        expect(find.text("What's new"), findsOneWidget);
        expect(find.text('Google Play Store'), findsOneWidget);

        // Tap on "What's new" to open sheet
        await tester.tap(find.text("What's new"));
        await tester.pumpAndSettle();

        // Verify What's New sheet is open
        expect(find.text("What's New in 1Wallet"), findsOneWidget);
        expect(find.text('Recent releases & improvements'), findsOneWidget);
      },
    );
  });
}

class _FakeGateway implements PlayUpdateGateway {
  _FakeGateway({this.info});

  AppUpdateInfo? info;
  Object? error;
  Completer<void>? gate;
  int checks = 0;
  final progressController = StreamController<PlayUpdateProgress>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Future<AppUpdateInfo> checkForUpdate() async {
    checks++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return info ?? _info();
  }

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async =>
      AppUpdateResult.success;

  @override
  Future<AppUpdateResult> performImmediateUpdate() async =>
      AppUpdateResult.success;

  @override
  Future<void> completeFlexibleUpdate() async => completes++;

  int completes = 0;

  @override
  Stream<PlayUpdateProgress> get progress => progressController.stream;
}

AppUpdateInfo _info({
  UpdateAvailability availability = UpdateAvailability.updateNotAvailable,
  InstallStatus installStatus = InstallStatus.unknown,
}) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: true,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: true,
  flexibleAllowedPreconditions: null,
  availableVersionCode: 22,
  installStatus: installStatus,
  packageName: 'com.joelpjoji.one.wallet',
  clientVersionStalenessDays: 2,
  updatePriority: 0,
);

void _dailyCheckTests() {
  group('Play update daily check', () {
    late DateTime now;
    late _FakeGateway gateway;
    late PlayStoreUpdateService service;

    setUp(() {
      now = DateTime(2026, 3, 10, 9);
      gateway = _FakeGateway();
      service = PlayStoreUpdateService(
        gateway: gateway,
        now: () => now,
        autoInstallDelay: const Duration(milliseconds: 10),
      );
    });

    tearDown(() => service.dispose());

    test('checks once per calendar day, once after days away', () async {
      expect(await service.checkOnAppOpen(), isTrue);
      now = DateTime(2026, 3, 10, 23, 59);
      expect(await service.checkOnAppOpen(), isFalse);
      expect(gateway.checks, 1);

      now = DateTime(2026, 3, 13, 8);
      expect(await service.checkOnAppOpen(), isTrue);
      expect(await service.checkOnAppOpen(), isFalse);
      expect(gateway.checks, 2);

      // A clock moved backwards is a different day, so it may check again.
      now = DateTime(2026, 3, 12, 8);
      expect(await service.checkOnAppOpen(), isTrue);
      expect(gateway.checks, 3);
    });

    test('the day survives an app restart', () async {
      await service.checkOnAppOpen();
      final restarted = PlayStoreUpdateService(
        gateway: gateway,
        now: () => now.add(const Duration(hours: 3)),
      );
      addTearDown(restarted.dispose);
      expect(await restarted.checkOnAppOpen(), isFalse);
      expect(gateway.checks, 1);
    });

    test('overlapping opens share one Play request', () async {
      gateway.gate = Completer<void>();
      final first = service.checkOnAppOpen();
      final second = service.checkOnAppOpen();
      await Future<void>.delayed(Duration.zero);
      gateway.gate!.complete();
      await Future.wait([first, second]);
      expect(gateway.checks, 1);
    });

    test('transient failures back off, then retry the same day', () async {
      gateway.error = Exception('network down');
      await service.checkOnAppOpen();
      expect(service.state.status, PlayStoreUpdateStatus.failed);

      gateway.error = null;
      now = now.add(const Duration(hours: 1));
      expect(await service.checkOnAppOpen(), isFalse);
      now = now.add(const Duration(hours: 3));
      expect(await service.checkOnAppOpen(), isTrue);
      expect(gateway.checks, 2);
    });

    test('a sideloaded build (not owned on Play) stops for the day', () async {
      gateway.error = Exception('Install Error(-10): The app is not owned');
      await service.checkOnAppOpen();
      gateway.error = null;
      now = now.add(const Duration(hours: 5));
      expect(await service.checkOnAppOpen(), isFalse);
      expect(gateway.checks, 1);
    });

    test('an available update asks for the sheet once', () async {
      gateway.info = _info(availability: UpdateAvailability.updateAvailable);
      await service.checkOnAppOpen();
      expect(service.state.status, PlayStoreUpdateStatus.updateAvailable);
      expect(service.state.promptPending, isTrue);
      service.consumePrompt();
      expect(service.state.promptPending, isFalse);
    });

    test(
      'an update downloaded earlier prompts to install, not re-download',
      () async {
        gateway.info = _info(
          availability: UpdateAvailability.updateAvailable,
          installStatus: InstallStatus.downloaded,
        );
        await service.checkOnAppOpen();
        expect(service.state.status, PlayStoreUpdateStatus.readyToInstall);
        expect(service.state.promptPending, isTrue);
      },
    );

    test('a download in progress streams byte progress', () async {
      gateway.info = _info(
        availability: UpdateAvailability.updateAvailable,
        installStatus: InstallStatus.downloading,
      );
      await service.checkOnAppOpen();
      expect(service.state.status, PlayStoreUpdateStatus.downloading);
      expect(service.state.promptPending, isFalse);

      gateway.progressController.add(
        const PlayUpdateProgress(
          status: InstallStatus.downloading,
          bytesDownloaded: 512,
          totalBytes: 2048,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.state.progress?.fraction, 0.25);

      gateway.progressController.add(
        const PlayUpdateProgress(
          status: InstallStatus.downloaded,
          bytesDownloaded: 2048,
          totalBytes: 2048,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.state.status, PlayStoreUpdateStatus.readyToInstall);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.completes, 1, reason: 'installs without a Later step');

      // An active update is not interrupted by a new-day check.
      now = now.add(const Duration(days: 1));
      expect(await service.checkOnAppOpen(), isFalse);
    });

    test('progress events decode from the native channel map', () {
      final event = playUpdateProgressFromEvent({
        'status': 2,
        'bytesDownloaded': 10,
        'totalBytes': 40,
      });
      expect(event?.status, InstallStatus.downloading);
      expect(event?.fraction, 0.25);
      expect(playUpdateProgressFromEvent('bad'), isNull);
    });
  });
}
