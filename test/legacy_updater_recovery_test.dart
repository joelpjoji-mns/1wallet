import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';
import 'package:one_wallet_flutter/src/features/updates/updates_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/legacy_update_client_2_2_01.dart' as shipped;

const installedCode = 2104201;
const baseCode = 2102206;
const apkCode = 2104206;

Map<String, dynamic> channel(int code) => {
  'channel': 'stable',
  'latestVersionCode': code,
  'latestReleaseId': 'stable-$code',
  'versionName': '2.2.06',
  'latestVersionName': '2.2.06',
};

Map<String, dynamic> release(int code, List<int> bytes) => {
  'platform': 'android',
  'channel': 'stable',
  'status': 'published',
  'versionName': '2.2.06',
  'versionCode': code,
  'runtimeVersion': '2.2.06',
  'releaseType': 'patch',
  'requirement': 'optional',
  'mandatory': false,
  'minimumSupportedVersionCode': 0,
  'publishedAt': '2026-10-27T18:00:00Z',
  'changelog': {
    'newFeatures': [],
    'bugFixes': ['Recover installed updater'],
    'notes': [],
  },
  'apk': {
    'fileName': 'update.apk',
    'downloadUrl': 'https://example.test/update.apk',
    'sizeBytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'architecture': 'arm64-v8a',
  },
};

Future<void> nativeWorkerRecordsDelivery(int publishedCode) async {
  // These are the shipped native worker's raw version comparisons. The JVM
  // regression exercises the same production handler with real Android prefs.
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.getInt('lastNotifiedVersionCode.stable') ?? 0;
  if (publishedCode > installedCode && publishedCode > last) {
    final success = await SharedPreferencesStorePlatform.instance.setValue(
      'Int',
      'flutter.lastNotifiedVersionCode.stable',
      publishedCode,
    );
    if (!success) {
      throw StateError('Could not retain native notification delivery.');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: '1Wallet',
      packageName: 'com.joelpjoji.one.wallet',
      version: '2.2.01',
      buildNumber: '$installedCode',
      buildSignature: 'synthetic',
    );
    shipped.NotificationService.attempts = 0;
  });

  Future<shipped.LegacyShippedUpdateClient> client(
    int code, {
    bool corrupt = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'legacy-updater-check-',
    );
    final payload = utf8.encode('synthetic verified APK payload');
    final provider = shipped.LegacyShippedUpdateClient(
      channel: channel(code),
      release: release(code, payload),
      downloadDirectory: directory,
      apkBytes: corrupt ? utf8.encode('changed payload') : payload,
    );
    addTearDown(() async {
      if (provider.mounted) provider.dispose();
      final file = File('${directory.path}${Platform.pathSeparator}update.apk');
      if (await file.exists()) await file.delete();
      await directory.delete();
    });
    await Future<void>.delayed(Duration.zero);
    return provider;
  }

  test(
    'the shipped 2.2.01 methods reproduce the screenshot with base-code metadata',
    () async {
      final provider = await client(baseCode);
      await nativeWorkerRecordsDelivery(baseCode);
      final prefs = await SharedPreferences.getInstance();
      await shipped.LegacySmsSpooler.popSpooledMessages();
      expect(prefs.getInt('lastNotifiedVersionCode.stable'), isNull);
      await provider.checkForUpdates(force: true);
      expect(provider.state.status, UpdateStatus.error);
      expect(provider.state.errorMessage, contains('invalid_icon'));
      expect(provider.state.latestRelease?.versionName, '2.2.06');
      expect(shipped.NotificationService.attempts, 1);
    },
  );

  test(
    'actual APK metadata recovers the unmodified shipped check and verified in-app install',
    () async {
      final provider = await client(apkCode);
      final prefs = await SharedPreferences.getInstance();
      await nativeWorkerRecordsDelivery(apkCode);
      expect(
        prefs.getInt('lastNotifiedVersionCode.stable'),
        isNull,
        reason:
            'Dart caches must reload native writes, as the shipped spool reader does.',
      );
      await shipped.LegacySmsSpooler.popSpooledMessages();
      await provider.checkForUpdates(force: true);
      expect(provider.state.currentVersionName, '2.2.01');
      expect(provider.state.currentVersionCode, installedCode);
      expect(provider.state.status, UpdateStatus.idle);
      expect(provider.state.errorMessage, isNull);
      expect(provider.state.latestRelease?.versionCode, apkCode);
      expect(
        shipped.NotificationService.attempts,
        0,
        reason:
            'The old Flutter notification path is bypassed by its existing shared delivery marker.',
      );
      await provider.downloadUpdate();
      expect(provider.installerOpened, isTrue);
      expect(provider.installerPath, isNotNull);
      expect(provider.state.status, UpdateStatus.downloaded);
    },
  );

  test(
    'legacy recovery does not bypass downloaded APK checksum rejection',
    () async {
      final provider = await client(apkCode, corrupt: true);
      await nativeWorkerRecordsDelivery(apkCode);
      await shipped.LegacySmsSpooler.popSpooledMessages();
      await provider.checkForUpdates(force: true);
      await provider.downloadUpdate();
      expect(provider.installerOpened, isFalse);
      expect(provider.state.status, UpdateStatus.error);
      expect(provider.state.errorMessage, contains('integrity check failed'));
    },
  );

  testWidgets(
    'a recovered 2.2.01 client exposes the normal in-app install action',
    (tester) async {
      late shipped.LegacyShippedUpdateClient provider;
      await tester.runAsync(() async {
        provider = await client(apkCode);
        await nativeWorkerRecordsDelivery(apkCode);
        await shipped.LegacySmsSpooler.popSpooledMessages();
        await provider.checkForUpdates(force: true);
      });
      final container = ProviderContainer(
        overrides: [appUpdateProvider.overrideWith((ref) => provider)],
      );
      // The test owns provider disposal through client(); avoid a second dispose.
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
      expect(find.textContaining('Install Update ('), findsOneWidget);
      await tester.runAsync(() => provider.downloadUpdate());
      expect(provider.installerOpened, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
}
