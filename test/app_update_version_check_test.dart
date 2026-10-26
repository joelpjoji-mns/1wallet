import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';

void main() {
  group('AppUpdateProvider.isReleaseNewer', () {
    test('returns false when version names are identical', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2000146,
          latestVersionName: '2.1.146',
          currentVersionCode: 2002146,
          currentVersionName: '2.1.146',
        ),
        isFalse,
      );
    });

    test('returns false when version names match with v prefix', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2000146,
          latestVersionName: 'v2.1.146',
          currentVersionCode: 2002146,
          currentVersionName: '2.1.146',
        ),
        isFalse,
      );
    });

    test('returns true when latest semantic version is higher', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2000147,
          latestVersionName: '2.1.147',
          currentVersionCode: 2002146,
          currentVersionName: '2.1.146',
        ),
        isTrue,
      );
    });

    test('returns false when latest semantic version is lower', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2000140,
          latestVersionName: '2.1.140',
          currentVersionCode: 2002146,
          currentVersionName: '2.1.146',
        ),
        isFalse,
      );
    });

    test('handles ABI split offset correctly (arm64 +2000)', () {
      // Installed arm64 APK has 2000000 + 2000 + 146 = 2002146
      // Firestore has base 2000000 + 146 = 2000146
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2000146,
          latestVersionName: '',
          currentVersionCode: 2002146,
          currentVersionName: '',
        ),
        isFalse,
      );

      // Newer update 147 published
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2000147,
          latestVersionName: '',
          currentVersionCode: 2002146,
          currentVersionName: '',
        ),
        isTrue,
      );
    });

    test('seamlessly transitions from 200xxxx to 210xxxx versions', () {
      // Installed: 2.1.146 with versionCode 2002146
      // Latest: 2.1.147 with versionCode 2100147
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100147,
          latestVersionName: '2.1.147',
          currentVersionCode: 2002146,
          currentVersionName: '2.1.146',
        ),
        isTrue,
      );

      // Once 2.1.147 is installed (arm64 split adds 2000 -> 2102147):
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100147,
          latestVersionName: '2.1.147',
          currentVersionCode: 2102147,
          currentVersionName: '2.1.147',
        ),
        isFalse,
      );
    });

    test('handles padded two-digit patch versions (e.g. 2.1.01 vs 2.1.00)', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100001,
          latestVersionName: '2.1.01',
          currentVersionCode: 2100000,
          currentVersionName: '2.1.00',
        ),
        isTrue,
      );

      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100001,
          latestVersionName: '2.1.01',
          currentVersionCode: 2102001,
          currentVersionName: '2.1.01',
        ),
        isFalse,
      );
    });
  });
}
