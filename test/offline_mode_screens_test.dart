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
import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_controller.dart';
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
    expect(find.byKey(const Key('offline-sign-out')), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);

    router.go('/sync');
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(OfflineModeCard.upgradeKey), findsOneWidget);
    expect(find.text('Not syncing'), findsOneWidget);
    expect(find.text(offlineModeSyncDisabledReason), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });

  testWidgets('signing out of offline mode erases the wallet and opens login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await initializeDateFormatting('en_IN');
    SharedPreferences.setMockInitialValues({
      AppModeStore.storageKey: AppMode.offline.name,
      AppModeStore.localDisplayNameKey: 'Joel',
      'one_wallet_flutter.permissions_setup.completed.local-user': true,
      'one_wallet_flutter.onboarding.completed.local-user': true,
      'has_unsynced_changes': true,
      'last_local_modified_at': '2026-01-01T00:00:00.000Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final ledgerRepository = MemoryLedgerRepository(sampleLedgerState());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ledgerRepositoryProvider.overrideWithValue(ledgerRepository),
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
    router.push('/settings');
    await _frames(tester);

    await container
        .read(discoveryControllerProvider(localOwnerId).notifier)
        .prepareWelcome();
    final signOut = find.byKey(const Key('offline-sign-out'));
    await tester.ensureVisible(signOut);
    await _frames(tester);
    await tester.tap(signOut);
    await _frames(tester);
    expect(find.text('Sign out of offline wallet?'), findsOneWidget);

    await tester.tap(find.text('Erase & sign out'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _frames(tester);

    expect(
      find.text('Could not sign out. Your offline wallet was not changed.'),
      findsNothing,
    );

    expect(tester.takeException(), isNull);
    final auth = container.read(authControllerProvider);
    expect(auth.isLocalOnly, isFalse);
    expect(auth.phase, AuthPhase.signedOut);
    expect(prefs.getString(AppModeStore.storageKey), AppMode.online.name);
    expect(prefs.getString(AppModeStore.localDisplayNameKey), isNull);
    expect(
      prefs.getString('one_wallet_flutter.discovery.v1.local-user'),
      isNull,
    );
    expect(ledgerRepository.saved, isNull);
    expect(container.read(ledgerProvider).accounts, isEmpty);
    // A stale flag would make the next Google sign-in refuse its cloud restore.
    expect(prefs.getBool('has_unsynced_changes'), isNull);
    expect(prefs.getString('last_local_modified_at'), isNull);
    expect(
      container.read(startupStateProvider).destination,
      StartupDestination.login,
    );
    expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
  });

  testWidgets('startup recovery screen offers a working sign out', (
    tester,
  ) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RecoveryState(
          title: 'Cloud wallet found',
          body: 'Not yet synced.',
          actionLabel: 'Try again',
          onAction: () {},
          onSignOut: () => signOuts++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('recovery-sign-out')));
    expect(signOuts, 1);
    expect(tester.takeException(), isNull);
  });
}
