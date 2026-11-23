import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';
import 'package:one_wallet_flutter/src/features/updates/play_store_update_service.dart';
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

    test('checkForUpdate sets notSupported on non-Android test environment', () async {
      final service = PlayStoreUpdateService();
      final result = await service.checkForUpdate();
      expect(result, isNull);
      expect(service.state.status, PlayStoreUpdateStatus.notSupported);
    });

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

  group('Settings Screen Updates & Version Section Widget Tests', () {
    testWidgets('renders App updates & version section and opens Whats New sheet', (
      tester,
    ) async {
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
    });
  });
}
