import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_queue.dart';
import 'package:one_wallet_flutter/src/features/settings/account_deletion_api.dart';
import 'package:one_wallet_flutter/src/features/settings/account_deletion_controller.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

class _Repository extends LedgerRepository {
  bool failClear = false;
  bool cleared = false;
  @override
  Future<LedgerState?> load() async => null;
  @override
  Future<void> save(LedgerState state) async {}
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('injected purge failure');
    cleared = true;
  }
}

class _Auth extends StateNotifier<AuthState> implements AuthController {
  _Auth()
    : super(
        const AuthState(
          phase: AuthPhase.signedIn,
          googleSignInAvailable: true,
          user: AuthUser(id: 'owner-a', email: 'synthetic@example.test'),
        ),
      );
  int signOutCalls = 0;
  @override
  Future<String> reauthenticateForDeletion() async => 'synthetic-id-token';
  @override
  Future<void> signOut({bool rethrowOnError = false}) async {
    signOutCalls++;
    state = state.copyWith(phase: AuthPhase.signedOut, user: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cloud extends StateNotifier<CloudSyncState>
    implements CloudSyncController {
  _Cloud() : super(const CloudSyncState());
  @override
  Future<void> handleSignOut() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements AccountDeletionApi {
  bool failRequest = false;
  int requests = 0;
  @override
  Future<void> request(String receipt, String idToken) async {
    requests++;
    expect(await DeletionOperation.load(), isNotNull);
    if (failRequest) throw StateError('injected backend failure');
  }

  @override
  Future<bool> isRemoteComplete(String receipt) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SecureKeyStore.clear();
    CaptureQueue.client = MemoryCaptureQueue();
    LedgerProvidersConfig.disableAutoBackup = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => null,
        );
  });

  Future<(ProviderContainer, _Repository, _Auth, _Api)> setup({
    bool apiUnavailable = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = _Repository();
    final ledger = LedgerController(
      repository,
      initialState: emptyLedgerState(userId: 'owner-a'),
      initialUser: const LedgerUserIdentity(userId: 'owner-a'),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final auth = _Auth();
    final api = _Api();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith((ref) => auth),
        ledgerProvider.overrideWith((ref) => ledger),
        cloudSyncControllerProvider.overrideWith((ref) => _Cloud()),
        accountDeletionApiProvider.overrideWith((ref) {
          if (apiUnavailable) {
            throw StateError(
              'The HTTP API must not be used for a verified observation.',
            );
          }
          return api;
        }),
      ],
    );
    addTearDown(container.dispose);
    return (container, repository, auth, api);
  }

  test('success requires remote confirmation and strict local purge', () async {
    final (container, repository, auth, api) = await setup();
    final controller = container.read(
      accountDeletionControllerProvider.notifier,
    );
    expect(await controller.deleteAccountAndAllData(), isTrue);
    final state = container.read(accountDeletionControllerProvider);
    expect(state.stage, AccountDeletionStage.success);
    expect(state.remoteComplete && state.localComplete, isTrue);
    expect(repository.cleared, isTrue);
    expect(api.requests, 1);
    expect(auth.signOutCalls, 1);
    expect(await DeletionOperation.load(), isNull);
  });
  test(
    'backend request failure retains receipt and cannot report erasure',
    () async {
      final (container, repository, auth, api) = await setup();
      api.failRequest = true;
      final controller = container.read(
        accountDeletionControllerProvider.notifier,
      );
      expect(await controller.deleteAccountAndAllData(), isFalse);
      expect(
        container.read(accountDeletionControllerProvider).stage,
        AccountDeletionStage.error,
      );
      expect(repository.cleared, isFalse);
      expect(auth.signOutCalls, 0);
      expect(await DeletionOperation.load(), isNotNull);
    },
  );
  test(
    'local purge failure remains retryable after remote completion',
    () async {
      final (container, repository, auth, _) = await setup();
      repository.failClear = true;
      final controller = container.read(
        accountDeletionControllerProvider.notifier,
      );
      expect(await controller.deleteAccountAndAllData(), isFalse);
      expect(
        container.read(accountDeletionControllerProvider).operationPending,
        isTrue,
      );
      expect(await DeletionOperation.load(), isNotNull);
      expect(auth.signOutCalls, 0);
      repository.failClear = false;
      expect(await controller.deleteAccountAndAllData(), isTrue);
    },
  );

  test(
    'a server-confirmed observation can finish local cleanup after auth deletion',
    () async {
      final (container, repository, auth, api) = await setup(
        apiUnavailable: true,
      );
      final controller = container.read(
        accountDeletionControllerProvider.notifier,
      );
      await controller.observeCompletedDeletion(
        const LedgerUserIdentity(userId: 'owner-a'),
      );
      expect(
        container.read(accountDeletionControllerProvider).stage,
        AccountDeletionStage.success,
      );
      expect(repository.cleared, isTrue);
      expect(api.requests, 0);
      expect(auth.signOutCalls, 1);
      expect(await DeletionOperation.load(), isNull);
    },
  );

  test('cleanup of a previous owner cannot erase the current wallet', () async {
    final (container, repository, auth, _) = await setup(apiUnavailable: true);
    auth.state = auth.state.copyWith(
      user: const AuthUser(id: 'owner-b', email: 'b@example.test'),
    );
    final ledger = container.read(ledgerProvider.notifier);
    await ledger.setActiveUser(const LedgerUserIdentity(userId: 'owner-b'));
    await ledger.upsertAccount(id: 'bank-b', name: 'B', type: 'bank');
    repository.cleared = false;
    await const DeletionOperation(
      owner: LedgerUserIdentity(userId: 'owner-a'),
      receipt: '',
      remoteConfirmed: true,
    ).persist();
    final controller = container.read(
      accountDeletionControllerProvider.notifier,
    );
    expect(await controller.deleteAccountAndAllData(), isFalse);
    expect(repository.cleared, isFalse);
    expect(await controller.resumePendingDeletion(), isTrue);
    expect(ledger.state.userId, 'owner-b');
    expect(ledger.state.accounts.single.id, 'bank-b');
    expect(repository.cleared, isFalse);
    expect(auth.state.user?.id, 'owner-b');
  });

  test(
    'missing recovery receipts stay pending instead of reporting completion',
    () async {
      final (container, repository, _, _) = await setup(apiUnavailable: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onewallet.deletion.pending.v1', true);
      container.read(accountDeletionControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final state = container.read(accountDeletionControllerProvider);
      expect(state.stage, AccountDeletionStage.error);
      expect(state.operationPending, isTrue);
      expect(state.errorMessage, contains('receipt'));
      expect(repository.cleared, isFalse);
    },
  );
}
