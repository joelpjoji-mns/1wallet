import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_merge.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/offline_mode/offline_mode_controller.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';

const _uid = 'google-uid-1';
const _googleUser = AuthUser(
  id: _uid,
  email: 'owner@example.com',
  displayName: 'Owner',
  provider: 'google.com',
);
const _cardNumber = '4111 1111 1111 1111';
final _cardContext = SecureKeyStore.fieldContext('acc-card', 'number');
final _cloudVersion = CloudWriteState(
  cloudRevision: 7,
  updatedAt: DateTime.utc(2026, 1, 2),
  transactionCount: 1,
  accountCount: 1,
);

class _Harness {
  _Harness(this.container, this.prefs, this.auth, this.gateway, this.store);

  final ProviderContainer container;
  final SharedPreferences prefs;
  final FakeAuthRepository auth;
  final FakeUpgradeGateway gateway;
  final MemoryLedgerRepository store;

  OfflineModeController get offline =>
      container.read(offlineModeControllerProvider.notifier);
  OfflineModeState get upgrade => container.read(offlineModeControllerProvider);
  AuthState get authState => container.read(authControllerProvider);
  LedgerState get ledger => container.read(ledgerProvider);
  AppMode get persistedMode => AppModeStore(prefs).mode;
}

Future<LedgerState> _localWallet() async {
  final secret = await SecureKeyStore.encrypt(
    _cardNumber,
    userId: localOwnerId,
    context: _cardContext,
  );
  final base = sampleLedgerState();
  return base.copyWith(
    accounts: [
      for (final account in base.accounts)
        account.id == 'acc-card'
            ? account.copyWith(encryptedDetails: {'number': secret})
            : account,
    ],
  );
}

LedgerState _cloudWallet() {
  final base = emptyLedgerState(userId: _uid);
  return base.copyWith(
    accounts: const [
      Account(
        id: 'acc-cloud',
        name: 'Cloud savings',
        type: 'bank',
        currency: 'USD',
        openingBalance: Money(amountMinor: 50000, currency: 'USD'),
      ),
    ],
    transactions: [
      TransactionRecord(
        id: 'tx-cloud',
        type: 'income',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-cloud',
        amount: const Money(amountMinor: 12345, currency: 'USD'),
        baseAmount: const Money(amountMinor: 12345, currency: 'USD'),
        occurredAt: DateTime.utc(2025, 12, 1),
      ),
    ],
  );
}

Future<_Harness> _setUp({Map<String, Object> extraPrefs = const {}}) async {
  SharedPreferences.setMockInitialValues({
    AppModeStore.storageKey: AppMode.offline.name,
    'one_wallet_flutter.permissions_setup.completed.local-user': true,
    'one_wallet_flutter.onboarding.completed.local-user': true,
    ...extraPrefs,
  });
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(signInUser: _googleUser);
  final gateway = FakeUpgradeGateway();
  final store = MemoryLedgerRepository(await _localWallet());
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      ledgerRepositoryProvider.overrideWithValue(store),
      offlineUpgradeCloudGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  expect(container.read(authControllerProvider).isLocalOnly, isTrue);
  await container.read(ledgerProvider.notifier).flushPendingWrites();
  expect(container.read(ledgerProvider).userId, localOwnerId);
  return _Harness(container, prefs, auth, gateway, store);
}

Set<String> _ids(Iterable<TransactionRecord> txs) => {
  for (final tx in txs) tx.id,
};

Future<String> _readCard(LedgerState ledger, String owner) {
  final card = ledger.accounts.firstWhere((a) => a.id == 'acc-card');
  return SecureKeyStore.decrypt(
    card.encryptedDetails!['number']!,
    userId: owner,
    context: _cardContext,
  );
}

void _expectStillOffline(_Harness h, Set<String> localIds) {
  expect(h.authState.isLocalOnly, isTrue);
  expect(h.authState.user, isNull);
  expect(h.persistedMode, AppMode.offline);
  expect(h.ledger.userId, localOwnerId);
  expect(_ids(h.ledger.transactions), localIds);
}

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SecureKeyStore.clear();
  });

  test('no cloud wallet: the offline wallet moves to the account', () async {
    final h = await _setUp();
    final localIds = _ids(h.ledger.transactions);

    await h.offline.startGoogleUpgrade();

    expect(h.upgrade.stage, OfflineUpgradeStage.completed);
    expect(h.upgrade.resolvedChoice, CloudWalletChoice.keepLocal);
    expect(h.authState.phase, AuthPhase.signedIn);
    expect(h.authState.user?.id, _uid);
    expect(h.persistedMode, AppMode.online);
    expect(h.ledger.userId, _uid);
    expect(_ids(h.ledger.transactions), localIds);
    expect(h.store.saved?.userId, _uid);
    expect(await _readCard(h.ledger, _uid), _cardNumber);
    expect(h.prefs.getBool('has_unsynced_changes'), isTrue);
    expect(h.prefs.getString('last_active_user_id'), _uid);
    expect(h.gateway.primed, [(_uid, null)]);
    expect(
      h.prefs.getBool('one_wallet_flutter.permissions_setup.completed.$_uid'),
      isTrue,
    );
    expect(
      h.prefs.getBool('one_wallet_flutter.onboarding.completed.$_uid'),
      isTrue,
    );
  });

  group('existing cloud wallet', () {
    Future<(_Harness, Set<String>)> awaitingChoice() async {
      final h = await _setUp();
      h.gateway.probeResult = CloudWalletProbe(
        exists: true,
        live: _cloudVersion,
      );
      final localIds = _ids(h.ledger.transactions);
      await h.offline.startGoogleUpgrade();

      expect(h.upgrade.stage, OfflineUpgradeStage.awaitingChoice);
      expect(h.upgrade.cloudTransactionCount, 1);
      expect(h.upgrade.localTransactionCount, localIds.length);
      // Nothing changes before an explicit choice.
      _expectStillOffline(h, localIds);
      expect(h.gateway.primed, isEmpty);
      return (h, localIds);
    }

    test(
      'keep local uploads this device over the observed cloud version',
      () async {
        final (h, localIds) = await awaitingChoice();

        await h.offline.resolveCloudWalletChoice(CloudWalletChoice.keepLocal);

        expect(h.upgrade.stage, OfflineUpgradeStage.completed);
        expect(h.authState.user?.id, _uid);
        expect(h.ledger.userId, _uid);
        expect(_ids(h.ledger.transactions), localIds);
        expect(await _readCard(h.ledger, _uid), _cardNumber);
        expect(h.prefs.getBool('has_unsynced_changes'), isTrue);
        expect(h.gateway.primed.single.$1, _uid);
        expect(h.gateway.primed.single.$2?.cloudRevision, 7);
      },
    );

    test('keep cloud resets the device so the cloud wallet restores', () async {
      final (h, _) = await awaitingChoice();

      await h.offline.resolveCloudWalletChoice(CloudWalletChoice.keepCloud);

      expect(h.upgrade.stage, OfflineUpgradeStage.completed);
      expect(h.authState.user?.id, _uid);
      expect(h.persistedMode, AppMode.online);
      expect(h.ledger.userId, _uid);
      expect(h.ledger.accounts, isEmpty);
      expect(h.ledger.transactions, isEmpty);
      expect(h.ledger.hasAuthoritativeEmptyWallet, isFalse);
      expect(h.prefs.getBool('has_unsynced_changes'), isNull);
      expect(h.gateway.primed, [(_uid, null)]);
    });

    test(
      'merge keeps both wallets and supersedes the fetched version',
      () async {
        final (h, localIds) = await awaitingChoice();
        h.gateway.snapshot = CloudWalletSnapshot(
          ledger: _cloudWallet(),
          version: const CloudWriteState(cloudRevision: 8),
        );

        await h.offline.resolveCloudWalletChoice(CloudWalletChoice.merge);

        expect(h.upgrade.stage, OfflineUpgradeStage.completed);
        expect(h.ledger.userId, _uid);
        expect(_ids(h.ledger.transactions), {...localIds, 'tx-cloud'});
        expect(
          h.ledger.accounts.map((a) => a.id),
          containsAll(['acc-cloud', 'acc-bank', 'acc-card']),
        );
        expect(await _readCard(h.ledger, _uid), _cardNumber);
        expect(h.gateway.fetchCalls, 1);
        expect(h.gateway.primed.single.$2?.cloudRevision, 8);
        expect(h.prefs.getBool('has_unsynced_changes'), isTrue);
      },
    );

    test('cancel signs out of Google and keeps everything offline', () async {
      final (h, localIds) = await awaitingChoice();

      await h.offline.cancelUpgrade();

      expect(h.upgrade.stage, OfflineUpgradeStage.idle);
      expect(h.auth.signOutCalls, 1);
      _expectStillOffline(h, localIds);
      expect(h.gateway.primed, isEmpty);
    });
  });

  test(
    'an empty offline wallet adopts the cloud wallet without asking',
    () async {
      final h = await _setUp();
      await h.container.read(ledgerProvider.notifier).clearLocalWallet();
      h.gateway.probeResult = CloudWalletProbe(
        exists: true,
        live: _cloudVersion,
      );

      await h.offline.startGoogleUpgrade();

      expect(h.upgrade.stage, OfflineUpgradeStage.completed);
      expect(h.upgrade.resolvedChoice, CloudWalletChoice.keepCloud);
      expect(h.ledger.userId, _uid);
    },
  );

  test('a failed cloud check changes nothing and ends the session', () async {
    final h = await _setUp();
    final localIds = _ids(h.ledger.transactions);
    h.gateway.probeError = StateError('network unavailable');

    await h.offline.startGoogleUpgrade();

    expect(h.upgrade.stage, OfflineUpgradeStage.idle);
    expect(h.upgrade.errorMessage, contains('Nothing was changed'));
    expect(h.auth.signOutCalls, 1);
    _expectStillOffline(h, localIds);
  });

  test('a cancelled Google sign-in keeps offline mode', () async {
    final h = await _setUp();
    final localIds = _ids(h.ledger.transactions);
    h.auth.signInUser = null;

    await h.offline.startGoogleUpgrade();

    expect(h.upgrade.errorMessage, contains('cancelled'));
    expect(h.gateway.probeCalls, 0);
    _expectStillOffline(h, localIds);
  });

  test(
    'cloud sync stays inert until the upgrade publishes the account',
    () async {
      final h = await _setUp();
      final sync = h.container.read(cloudSyncControllerProvider);
      expect(sync.phase, CloudSyncPhase.disabled);
      expect(sync.disabledReason, offlineModeSyncDisabledReason);
    },
  );

  group('mergeLedgerStates', () {
    test('keeps cloud records on id clashes and appends local-only ones', () {
      final cloud = _cloudWallet();
      final local = sampleLedgerState().copyWith(
        userId: _uid,
        accounts: [
          ...sampleLedgerState().accounts,
          const Account(
            id: 'acc-cloud',
            name: 'Local copy (ignored)',
            type: 'bank',
            currency: 'EUR',
            openingBalance: Money(amountMinor: 1, currency: 'EUR'),
          ),
        ],
      );

      final merged = mergeLedgerStates(cloud: cloud, local: local);

      expect(merged.userId, _uid);
      expect(
        merged.accounts.firstWhere((a) => a.id == 'acc-cloud').name,
        'Cloud savings',
      );
      expect(merged.accounts.where((a) => a.id == 'acc-cloud'), hasLength(1));
      expect(_ids(merged.transactions), {
        ..._ids(local.transactions),
        'tx-cloud',
      });
      expect(merged.preferences.enabledCurrencies, contains('USD'));
      for (final account in merged.accounts) {
        expect(
          merged.preferences.enabledCurrencies,
          contains(account.currency.toUpperCase()),
        );
      }
    });

    test('refuses to merge wallets of different owners', () {
      expect(
        () => mergeLedgerStates(
          cloud: _cloudWallet(),
          local: sampleLedgerState(),
        ),
        throwsArgumentError,
      );
    });
  });
}
