import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/offline_mode_section.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';

const _nativeCaptureChannel = MethodChannel('com.joelpjoji.one.wallet/sms');

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, null);
  });

  testWidgets('offline settings and sync screens render the offline state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await initializeDateFormatting('en_IN');
    SharedPreferences.setMockInitialValues({
      AppModeStore.storageKey: AppMode.offline.name,
      'one_wallet_flutter.permissions_setup.completed.local-user': true,
      'one_wallet_flutter.onboarding.completed.local-user': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ledgerRepositoryProvider.overrideWithValue(
          MemoryLedgerRepository(sampleLedgerState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _frames(tester);

    expect(container.read(authControllerProvider).isLocalOnly, isTrue);
    expect(
      container.read(startupStateProvider).destination,
      StartupDestination.home,
    );
    expect(container.read(ledgerProvider).userId, localOwnerId);

    router.push('/settings');
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Offline mode'), findsWidgets);
    expect(find.byKey(OfflineModeCard.upgradeKey), findsOneWidget);
    expect(find.text('Export encrypted backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Sync with Google'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Delete account'), findsNothing);

    router.go('/sync');
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(OfflineModeCard.upgradeKey), findsOneWidget);
    expect(find.text('Not syncing'), findsOneWidget);
    expect(find.text(offlineModeSyncDisabledReason), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });
}
