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

    test('seamlessly transitions from legacy 2.1.146 (code 2002146) to new schema 2.1.51 (code 2100151)', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100151,
          latestVersionName: '2.1.51',
          currentVersionCode: 2002146,
          currentVersionName: '2.1.146',
        ),
        isTrue,
      );

      // Once 2.1.51 is installed (arm64 split adds 2000 -> 2102151):
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100151,
          latestVersionName: '2.1.51',
          currentVersionCode: 2102151,
          currentVersionName: '2.1.51',
        ),
        isFalse,
      );
    });

    test('handles patch rollover (e.g. 2.1.99 to 2.2.00)', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2100200,
          latestVersionName: '2.2.00',
          currentVersionCode: 2102199,
          currentVersionName: '2.1.99',
        ),
        isTrue,
      );
    });

    test('handles minor rollover (e.g. 2.9.99 to 3.0.00)', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2101000,
          latestVersionName: '3.0.00',
          currentVersionCode: 2102999,
          currentVersionName: '2.9.99',
        ),
        isTrue,
      );
    });

    test('handles major rollover (e.g. 9.9.99 to 10.0.00)', () {
      expect(
        AppUpdateProvider.isReleaseNewer(
          latestVersionCode: 2108000,
          latestVersionName: '10.0.00',
          currentVersionCode: 2109999,
          currentVersionName: '9.9.99',
        ),
        isTrue,
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
