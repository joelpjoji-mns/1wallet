import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';

const _offlinePrefs = <String, Object>{AppModeStore.storageKey: 'offline'};
const _permissionsDoneLocal =
    'one_wallet_flutter.permissions_setup.completed.local-user';
const _onboardingDoneLocal =
    'one_wallet_flutter.onboarding.completed.local-user';

void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> build({
    Map<String, Object> initialPrefs = const {},
    FakeAuthRepository? auth,
    LedgerState? ledger,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(
          auth ?? FakeAuthRepository(available: false),
        ),
        ledgerRepositoryProvider.overrideWithValue(
          MemoryLedgerRepository(ledger),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(startupStateProvider, (_, _) {});
    await container.read(ledgerProvider.notifier).flushPendingWrites();
    return container;
  }

  Future<StartupState> settle(ProviderContainer container) async {
    var current = container.read(startupStateProvider);
    for (var i = 0; i < 100 && current.isPending; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      current = container.read(startupStateProvider);
    }
    return current;
  }

  group('offline startup', () {
    test('opens with no Firebase at all and never routes to login', () async {
      final container = await build(initialPrefs: _offlinePrefs);

      final auth = container.read(authControllerProvider);
      expect(auth.phase, AuthPhase.localOnly);
      expect(auth.user, isNull, reason: 'no Firebase user is ever published');
      expect(auth.ownerId, localOwnerId);
      expect(auth.isAuthenticated, isFalse);
      expect(container.read(appModeProvider), AppMode.offline);

      final startup = await settle(container);
      expect(startup.isPending, isFalse);
      expect(startup.destination, StartupDestination.permissions);
    });

    test('flows permissions → onboarding → home for the local owner', () async {
      final container = await build(
        initialPrefs: {..._offlinePrefs, _permissionsDoneLocal: true},
      );
      expect(
        (await settle(container)).destination,
        StartupDestination.onboarding,
      );

      final withOnboarding = await build(
        initialPrefs: {
          ..._offlinePrefs,
          _permissionsDoneLocal: true,
          _onboardingDoneLocal: true,
        },
      );
      expect(
        (await settle(withOnboarding)).destination,
        StartupDestination.home,
      );
    });

    test('an existing local wallet opens home without cloud gating', () async {
      final container = await build(
        initialPrefs: {..._offlinePrefs, _permissionsDoneLocal: true},
        ledger: sampleLedgerState(),
      );
      final startup = await settle(container);
      expect(startup.destination, StartupDestination.home);
      expect(container.read(ledgerProvider).userId, localOwnerId);
    });

    test('existing users keep the default online flow (login)', () async {
      final container = await build();
      expect(AppModeStore(prefs).mode, AppMode.online);
      expect(container.read(authControllerProvider).isLocalOnly, isFalse);
      expect((await settle(container)).destination, StartupDestination.login);

      final withGoogle = await build(auth: FakeAuthRepository());
      expect((await settle(withGoogle)).destination, StartupDestination.login);
      expect(
        withGoogle.read(authControllerProvider).phase,
        AuthPhase.signedOut,
      );
    });

    test(
      'refuses to open a wallet owned by a Google account and keeps its data',
      () async {
        final foreign = sampleLedgerState().copyWith(userId: 'google-uid-1');
        final container = await build(
          initialPrefs: _offlinePrefs,
          auth: FakeAuthRepository(),
          ledger: foreign,
        );

        final startup = await settle(container);
        final auth = container.read(authControllerProvider);
        expect(startup.destination, StartupDestination.login);
        expect(auth.isLocalOnly, isFalse);
        expect(auth.errorMessage, contains('linked to a Google account'));
        expect(AppModeStore(prefs).mode, AppMode.online);
        final ledger = container.read(ledgerProvider);
        expect(ledger.userId, 'google-uid-1');
        expect(ledger.transactions, isNotEmpty, reason: 'nothing is deleted');
      },
    );

    test('finishes an upgrade interrupted after the wallet moved', () async {
      const user = AuthUser(
        id: 'google-uid-1',
        email: 'owner@example.com',
        provider: 'google.com',
      );
      final container = await build(
        initialPrefs: _offlinePrefs,
        auth: FakeAuthRepository(currentUser: user),
        ledger: sampleLedgerState().copyWith(userId: user.id),
      );

      await settle(container);
      final auth = container.read(authControllerProvider);
      expect(auth.phase, AuthPhase.signedIn);
      expect(auth.user?.id, user.id);
      expect(AppModeStore(prefs).mode, AppMode.online);
    });

    test(
      'keeps an abandoned upgrade session unpublished and opens offline',
      () async {
        final repository = FakeAuthRepository(
          currentUser: const AuthUser(id: 'google-uid-1', email: 'a@b.test'),
        );
        final container = await build(
          initialPrefs: {..._offlinePrefs, _permissionsDoneLocal: true},
          auth: repository,
          ledger: sampleLedgerState(),
        );

        final startup = await settle(container);
        final auth = container.read(authControllerProvider);
        expect(startup.destination, StartupDestination.home);
        expect(auth.isLocalOnly, isTrue);
        expect(auth.user, isNull);
        expect(auth.localOwnershipVerified, isTrue);
        expect(container.read(ledgerProvider).userId, localOwnerId);
        expect(AppModeStore(prefs).mode, AppMode.offline);
      },
    );
  });

  group('cloud sync in offline mode', () {
    test(
      'stays disabled with a reason and never reaches Firestore on any entry point',
      () async {
        final container = await build(
          initialPrefs: {..._offlinePrefs, _permissionsDoneLocal: true},
          auth: FakeAuthRepository(),
          ledger: sampleLedgerState(),
        );
        final sync = container.read(cloudSyncControllerProvider.notifier);
        expect(
          container.read(cloudSyncControllerProvider).disabledReason,
          offlineModeSyncDisabledReason,
        );

        // Firebase is not initialized in this test: any Firestore access from
        // these calls would throw instead of returning cleanly.
        final upload = await sync.uploadSnapshot(reason: 'manual');
        expect(upload.outcome, CloudWriteOutcome.unavailable);
        expect(upload.message, offlineModeSyncDisabledReason);
        final overwrite = await sync.overwriteCloudWithLocal();
        expect(overwrite.outcome, CloudWriteOutcome.unavailable);
        await sync.checkAndTriggerSync(fromResume: true);
        await sync.fullSync(reason: 'manual');
        await sync.useCloudCopy();
        await sync.updateSyncInterval(4);
        sync.retryBootstrap();

        final ledger = container.read(ledgerProvider.notifier);
        await ledger.setStartDayOfMonth(5);
        await sync.checkAndTriggerSync();

        final state = container.read(cloudSyncControllerProvider);
        expect(state.phase, CloudSyncPhase.disabled);
        expect(state.disabledReason, offlineModeSyncDisabledReason);
        expect(state.pendingUpload, isFalse);
        expect(state.bootstrapComplete, isFalse);
        // Local edits keep recording that they were never uploaded, so a
        // later Google upgrade uploads them.
        expect(prefs.getBool('has_unsynced_changes'), isTrue);
        expect(container.read(ledgerProvider).preferences.startDayOfMonth, 5);
      },
    );

    test('write guard blocks every cloud write while offline', () {
      expect(
        cloudWritesAllowed(localOnlyMode: true, signedInUserId: 'uid-1'),
        isFalse,
      );
      expect(
        cloudWritesAllowed(localOnlyMode: false, signedInUserId: null),
        isFalse,
      );
      expect(
        cloudWritesAllowed(localOnlyMode: false, signedInUserId: ' '),
        isFalse,
      );
      expect(
        cloudWritesAllowed(localOnlyMode: false, signedInUserId: 'uid-1'),
        isTrue,
      );
    });
  });
}
