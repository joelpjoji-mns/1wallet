import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/data/backup_codec.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/data/local_ledger_snapshot.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_queue.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_diagnostics.dart';
import 'package:one_wallet_flutter/src/security/app_lock.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

class _Repository extends LedgerRepository {
  LedgerState? saved;
  @override
  Future<LedgerState?> load() async => null;
  @override
  Future<void> save(LedgerState state) async {
    saved = state;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}

class _FailingAcknowledgment extends MemoryCaptureQueue {
  bool fail = true;
  @override
  Future<void> acknowledge(String owner, List<String> ids) async {
    if (fail) {
      fail = false;
      throw StateError('injected acknowledgment failure');
    }
    return super.acknowledge(owner, ids);
  }
}

class _Authenticator implements AppAuthenticator {
  int calls = 0;
  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<bool> authenticate() async {
    calls++;
    return true;
  }
}

class _DelayedAuthenticator implements AppAuthenticator {
  final answers = [Completer<bool>(), Completer<bool>()];
  int calls = 0;
  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<bool> authenticate() => answers[calls++].future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SecureKeyStore.clear();
    CaptureQueue.client = MemoryCaptureQueue();
    LedgerProvidersConfig.disableAutoBackup = true;
  });
  test('backup size checks enforce the same exact encode/decode boundary', () {
    expect(
      () => ensureSupportedBackupSize(maximumBackupEnvelopeCharacters),
      returnsNormally,
    );
    expect(
      () => ensureSupportedBackupSize(maximumBackupEnvelopeCharacters + 1),
      throwsFormatException,
    );
    expect(() => ensureSupportedBackupSize(-1), throwsFormatException);
  });
  test(
    'empty uploads require an owned initialized revision and cloud baseline',
    () {
      expect(
        canUploadEmptyCloudSnapshot(
          bootstrappedForUser: true,
          hasCloudBaseline: true,
          localRevision: 1,
          hasAuthoritativeEmptyWallet: true,
        ),
        isTrue,
      );
      expect(
        canUploadEmptyCloudSnapshot(
          bootstrappedForUser: true,
          hasCloudBaseline: true,
          localRevision: 0,
          hasAuthoritativeEmptyWallet: true,
        ),
        isFalse,
      );
      expect(
        canUploadEmptyCloudSnapshot(
          bootstrappedForUser: false,
          hasCloudBaseline: true,
          localRevision: 1,
          hasAuthoritativeEmptyWallet: true,
        ),
        isFalse,
      );
      expect(
        canUploadEmptyCloudSnapshot(
          bootstrappedForUser: true,
          hasCloudBaseline: false,
          localRevision: 1,
          hasAuthoritativeEmptyWallet: true,
        ),
        isFalse,
      );
      expect(
        canUploadEmptyCloudSnapshot(
          bootstrappedForUser: true,
          hasCloudBaseline: true,
          localRevision: 1,
          hasAuthoritativeEmptyWallet: false,
        ),
        isFalse,
      );
    },
  );
  test(
    'a valid empty primary cannot resurrect an older populated file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'onewallet-empty-ledger-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}ledger.json',
      );
      addTearDown(() async {
        if (await file.exists()) await file.delete();
        await directory.delete();
      });
      final repository = LedgerRepository(localFile: () async => file);
      final populated = emptyLedgerState(userId: 'owner-a').copyWith(
        localRevision: 1,
        accounts: [
          const Account(
            id: 'old',
            name: 'Deleted',
            type: 'bank',
            currency: 'USD',
            openingBalance: Money(amountMinor: 0, currency: 'USD'),
          ),
        ],
      );
      await repository.save(populated.copyWith(accounts: [], localRevision: 2));
      await file.writeAsString(encodeLocalLedgerSnapshot(populated));
      final restored = await repository.load();
      expect(restored!.accounts, isEmpty);
      expect(restored.localRevision, 2);
    },
  );

  Future<LedgerController> ledger(String owner) async {
    final controller = LedgerController(
      _Repository(),
      initialUser: LedgerUserIdentity(userId: owner),
      initialState: emptyLedgerState(userId: owner),
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await controller.flushPendingWrites();
    return controller;
  }

  test(
    'restores return their own revision even when a following edit is queued',
    () async {
      final controller = await ledger('owner-a');
      final baseline = controller.changeVersion;
      await controller.prepareCloudReplacement(baseline, 'owner-a');
      final restoring = controller.restoreLedgerState(
        emptyLedgerState(userId: 'owner-a'),
        expectedUserId: 'owner-a',
        expectedLocalRevision: baseline,
      );
      final edit = controller.setLocale('fr_FR');
      final restoredRevision = await restoring;
      await edit;
      expect(restoredRevision, lessThan(controller.changeVersion));
      expect(
        await controller.acknowledgeUploadedVersion(restoredRevision),
        isFalse,
      );
      await expectLater(
        controller.prepareCloudReplacement(baseline, 'owner-a'),
        throwsStateError,
      );
    },
  );

  test(
    'diagnostic histories and cleanup are scoped to the wallet owner',
    () async {
      final event = CaptureDiagnosticEvent(
        id: 'a',
        timestamp: DateTime.utc(2026, 1, 1),
        source: 'sms',
        stage: 'test',
        decision: 'queued',
        rawText: 'synthetic owner alert',
      );
      await CaptureDiagnostics.recordEvent(event, ownerId: 'owner-a');
      expect(
        await CaptureDiagnostics.recentEvents(ownerId: 'owner-b'),
        isEmpty,
      );
      await CaptureDiagnostics.recordEvent(event, ownerId: 'owner-b');
      await CaptureDiagnostics.clear(ownerId: 'owner-a');
      expect(
        await CaptureDiagnostics.recentEvents(ownerId: 'owner-a'),
        isEmpty,
      );
      expect(
        await CaptureDiagnostics.recentEvents(ownerId: 'owner-b'),
        hasLength(1),
      );
    },
  );

  test(
    'a backgrounded authentication cannot unlock without a fresh attempt',
    () async {
      SharedPreferences.setMockInitialValues({
        'one_wallet.device.app_lock.enabled.v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final authenticator = _DelayedAuthenticator();
      final lock = AppLockController(prefs, authenticator);
      addTearDown(lock.dispose);
      final first = lock.unlockAtLaunch();
      lock.lockForBackground();
      await lock.resume();
      authenticator.answers[0].complete(true);
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(authenticator.calls, 2);
      expect(lock.state.locked, isTrue);
      authenticator.answers[1].complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(lock.state.locked, isTrue);
      expect(lock.state.busy, isFalse);
    },
  );

  test(
    'an upload acknowledgment cannot clear an edit newer than its snapshot',
    () async {
      final controller = await ledger('owner-a');
      await controller.upsertAccount(id: 'a', name: 'A', type: 'bank');
      final uploaded = controller.changeVersion;
      await controller.upsertAccount(id: 'b', name: 'B', type: 'bank');
      expect(await controller.acknowledgeUploadedVersion(uploaded), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_unsynced_changes'), isTrue);
      expect(
        await controller.acknowledgeUploadedVersion(controller.changeVersion),
        isTrue,
      );
      expect(prefs.getBool('has_unsynced_changes'), isFalse);
    },
  );

  test(
    'local revision and pending capture receipts survive the local envelope',
    () {
      final input = emptyLedgerState(
        userId: 'owner-a',
      ).copyWith(localRevision: 42, ingressReceipts: {'queued-1'});
      final output = decodeLocalLedgerSnapshot(
        encodeLocalLedgerSnapshot(input),
      );
      expect(output.localRevision, 42);
      expect(output.ingressReceipts, {'queued-1'});
      final sharedJson = jsonDecode(encodeLedgerState(input)) as Map;
      expect(sharedJson.containsKey('ingressReceipts'), isFalse);
    },
  );

  test(
    'malformed capture is quarantined without losing the following valid capture',
    () async {
      final controller = await ledger('owner-a');
      final queue = CaptureQueue.client as MemoryCaptureQueue;
      await queue.append('owner-a', 'sms', {'body': 42});
      await queue.append('owner-a', 'sms', {
        'body': 'INR 100 debited from account XX1234 at SHOP.',
        'timestamp': '2026-03-01T10:00:00Z',
        'nativeAccepted': true,
      });
      await controller.processSpooledSms();
      expect(queue.quarantined, hasLength(1));
      expect(controller.state.captureCandidates, hasLength(1));
      expect(await queue.pending('owner-a', 'sms'), isEmpty);
    },
  );

  test(
    'a crash after ledger commit but before acknowledgment does not duplicate captures',
    () async {
      final queue = _FailingAcknowledgment();
      CaptureQueue.client = queue;
      final controller = await ledger('owner-a');
      await queue.append('owner-a', 'sms', {
        'body': 'INR 100 debited from account XX1234 at SHOP.',
        'timestamp': '2026-03-01T10:00:00Z',
        'nativeAccepted': true,
      });
      await expectLater(controller.processSpooledSms(), throwsStateError);
      expect(controller.state.captureCandidates, hasLength(1));
      expect(controller.state.ingressReceipts, hasLength(1));
      await controller.processSpooledSms();
      expect(controller.state.captureCandidates, hasLength(1));
      expect(controller.state.ingressReceipts, isEmpty);
      expect(await queue.pending('owner-a', 'sms'), isEmpty);
    },
  );

  test(
    'money rejects malformed and floating minor units while supporting integer strings',
    () {
      Map<String, dynamic> transaction(Object minor) => {
        'id': 'tx',
        'accountId': 'a',
        'type': 'expense',
        'status': 'cleared',
        'amount': {'amountMinor': minor, 'currency': 'USD'},
        'occurredAt': '2026-03-01T10:00:00Z',
      };
      expect(
        () => transactionFromJson(transaction('bad')),
        throwsFormatException,
      );
      expect(
        () => transactionFromJson(transaction(1.5)),
        throwsFormatException,
      );
      expect(transactionFromJson(transaction('123')).amount.amountMinor, 123);
    },
  );

  test('GCM rejects modified ciphertext and purpose headers', () async {
    final encrypted = await SecureKeyStore.encrypt(
      'synthetic-secret',
      userId: 'owner-a',
      context: 'account/number',
    );
    final data =
        jsonDecode(utf8.decode(base64Decode(encrypted.substring(3))))
            as Map<String, dynamic>;
    final cipher = base64Decode(data['data'] as String);
    cipher[0] ^= 1;
    data['data'] = base64Encode(cipher);
    final tampered = 'v2:${base64Encode(utf8.encode(jsonEncode(data)))}';
    await expectLater(SecureKeyStore.decrypt(tampered), throwsA(anything));
    await expectLater(
      SecureKeyStore.decrypt(encrypted, purpose: 'backup'),
      throwsFormatException,
    );
    expect(
      await SecureKeyStore.decrypt(
        encrypted,
        userId: 'owner-a',
        context: 'account/number',
      ),
      'synthetic-secret',
    );
  });

  test(
    'private auto-backup bytes are encrypted and authenticate before parsing',
    () async {
      final original = emptyLedgerState(userId: 'SyntheticPrivateOwner');
      final encrypted = await encodeDeviceBackup(original);
      expect(encrypted, isNot(contains('SyntheticPrivateOwner')));
      final decoded = await decodeBackup(
        encrypted,
        targetUserId: original.userId,
      );
      expect(decoded.userId, original.userId);
    },
  );

  test(
    'portable backups recover secure fields without the source device key',
    () async {
      final secret = await SecureKeyStore.encrypt(
        'synthetic-account-number',
        userId: 'owner-a',
        context: SecureKeyStore.fieldContext('account-a', 'number'),
      );
      final source = emptyLedgerState(userId: 'owner-a').copyWith(
        accounts: [
          Account(
            id: 'account-a',
            name: 'Portable test',
            type: 'card',
            currency: 'USD',
            openingBalance: const Money(amountMinor: 0, currency: 'USD'),
            encryptedDetails: {'number': secret},
          ),
        ],
      );
      final exported = await encodePortableBackup(
        source,
        'correct test passphrase',
      );
      expect(exported, isNot(contains('Portable test')));
      expect(exported, isNot(contains('synthetic-account-number')));
      await SecureKeyStore.clear(userId: 'owner-a');
      final destination = await ledger('owner-b');
      await destination.importArchive(
        exported,
        force: true,
        passphrase: 'correct test passphrase',
      );
      final restored =
          destination.state.accounts.single.encryptedDetails!['number']!;
      expect(
        await SecureKeyStore.decrypt(
          restored,
          userId: 'owner-b',
          context: SecureKeyStore.fieldContext('account-a', 'number'),
        ),
        'synthetic-account-number',
      );
      final before = destination.state;
      await expectLater(
        destination.importArchive(
          exported,
          force: true,
          passphrase: 'wrong passphrase',
        ),
        throwsA(anything),
      );
      expect(identical(destination.state, before), isTrue);
    },
  );

  testWidgets(
    'inactive hides content and actual backgrounding requires another unlock',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'one_wallet.device.app_lock.enabled.v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final authenticator = _Authenticator();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appAuthenticatorProvider.overrideWithValue(authenticator),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AppLockGate(child: Text('Private balance')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private balance'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Private balance'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(container.read(appLockProvider).locked, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(authenticator.calls, 2);
      expect(find.text('Private balance'), findsOneWidget);
    },
  );
}
