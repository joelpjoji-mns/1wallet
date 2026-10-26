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
  });
}
