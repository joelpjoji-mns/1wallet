import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_metadata.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_queue.dart';
import 'package:one_wallet_flutter/src/security/app_lock.dart';
import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';
import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

class _Repository extends LedgerRepository {
  @override
  Future<LedgerState?> load() async => null;
  @override
  Future<void> save(LedgerState state) async {}
  @override
  Future<void> clear() async {}
}

class _Queue extends MemoryCaptureQueue {
  bool failAcknowledgment = false;
  Map<String, Object?>? settings;
  @override
  Future<void> configure(
    String? owner, {
    Map<String, Object?>? settings,
  }) async {
    this.settings = settings;
    await super.configure(owner, settings: settings);
  }

  @override
  Future<void> acknowledge(String owner, List<String> ids) async {
    if (failAcknowledgment) {
      failAcknowledgment = false;
      throw StateError('injected acknowledgment failure');
    }
    await super.acknowledge(owner, ids);
  }
}

class _Authenticator implements AppAuthenticator {
  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<bool> authenticate() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CaptureQueue.client = _Queue();
    LedgerProvidersConfig.disableAutoBackup = true;
  });
  Future<LedgerController> ledger() async {
    final controller = LedgerController(
      _Repository(),
      initialState: emptyLedgerState(userId: 'owner-a'),
      initialUser: const LedgerUserIdentity(userId: 'owner-a'),
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    await controller.flushPendingWrites();
    return controller;
  }

  test(
    'obsolete sync bookkeeping is ignored without losing the conflict baseline',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final retired = {
        'lastLocalChecksum': 17,
        'lastSnapshotChecksum': true,
        'lastSnapshotPath': ['unused'],
        'lastRestoreBackupUri': {},
        'syncedAccountIds': false,
        'syncedCategoryIds': 1,
        'syncedTransactionIds': {},
        'syncedCaptureCandidateIds': true,
        'syncedImportBatchIds': 'obsolete',
        'syncedDocumentHashes': 42,
      };
      await prefs.setString(
        'one_wallet_flutter.cloud_sync.v1',
        jsonEncode({
          'version': 1,
          'deviceId': 'existing-device',
          'userId': 'owner-a',
          'lastCloudRevision': 27,
          'lastObservedCloudUpdatedAt': '2026-10-27T18:00:00Z',
          'lastPushedAt': '2026-10-27T18:00:00Z',
          'syncIntervalHours': 6,
          ...retired,
        }),
      );
      final metadata = await CloudSyncMetadata.load();
      expect(metadata.deviceId, 'existing-device');
      expect(metadata.userId, 'owner-a');
      expect(metadata.lastCloudRevision, 27);
      expect(metadata.lastObservedCloudUpdatedAt, '2026-10-27T18:00:00Z');
      expect(metadata.syncIntervalHours, 6);
      await metadata.save();
      final stored =
          jsonDecode(prefs.getString('one_wallet_flutter.cloud_sync.v1')!)
              as Map;
      expect(stored.keys.where(retired.containsKey), isEmpty);
      final cleared = metadata.copyWith(
        lastCloudRevision: null,
        lastObservedCloudUpdatedAt: null,
        syncIntervalHours: null,
      );
      expect(cleared.lastCloudRevision, isNull);
      expect(cleared.lastObservedCloudUpdatedAt, isNull);
      expect(cleared.syncIntervalHours, isNull);
    },
  );

  test(
    'old inactive preference fields do not affect restored money or device app lock',
    () async {
      final source = sampleLedgerState();
      final data =
          jsonDecode(encodeLedgerState(source)) as Map<String, dynamic>;
      final preferences = data['preferences'] as Map<String, dynamic>;
      preferences['quietHoursEnabled'] = true;
      preferences['biometricLockEnabled'] = false;
      final restored = decodeLedgerState(jsonEncode(data));
      expect(
        restored.accounts.map((account) => account.id),
        source.accounts.map((account) => account.id),
      );
      expect(
        restored.transactions.map(
          (transaction) => transaction.amount.amountMinor,
        ),
        source.transactions.map(
          (transaction) => transaction.amount.amountMinor,
        ),
      );
      final roundTrip = jsonDecode(encodeLedgerState(restored)) as Map;
      expect(
        (roundTrip['preferences'] as Map).containsKey('quietHoursEnabled'),
        isFalse,
      );
      expect(
        (roundTrip['preferences'] as Map).containsKey('biometricLockEnabled'),
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('one_wallet.device.app_lock.enabled.v1', true);
      final lock = AppLockController(prefs, _Authenticator());
      addTearDown(lock.dispose);
      expect(lock.state.enabled, isTrue);
      expect(lock.state.locked, isTrue);
    },
  );

  test(
    'capture configuration uses the owned queue without legacy preference mirrors',
    () async {
      final controller = await ledger();
      await controller.updatePreferencesWith(
        (current) => current.copyWith(
          smsCaptureEnabled: false,
          notificationCaptureEnabled: false,
          notificationTargetPackages: ['com.synthetic.bank'],
        ),
      );
      final queue = CaptureQueue.client as _Queue;
      expect(queue.owner, 'owner-a');
      expect(queue.settings?['smsCaptureEnabled'], isFalse);
      expect(queue.settings?['notificationCaptureEnabled'], isFalse);
      expect(queue.settings?['notificationTargetPackages'], [
        'com.synthetic.bank',
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where(
          (key) => RegExp(
            r'one_wallet_flutter\.(sms|notification)_(trigger_words|ignore_words|capture_enabled|target_packages)$',
          ).hasMatch(key),
        ),
        isEmpty,
      );
    },
  );

  for (final source in ['sms', 'notification']) {
    test(
      '$source queue preserves quarantine and durable acknowledgment retries',
      () async {
        final controller = await ledger();
        final queue = CaptureQueue.client as _Queue;
        await queue.append('owner-a', source, {'body': 42});
        await queue.append('owner-a', source, {
          'body': 'INR 100 debited from account XX1234 at SYNTHETIC SHOP.',
          'timestamp': '2026-10-27T18:00:00Z',
          'nativeAccepted': true,
        });
        queue.failAcknowledgment = true;
        final process = source == 'sms'
            ? controller.processSpooledSms
            : controller.processSpooledNotifications;
        await expectLater(process(), throwsStateError);
        expect(queue.quarantined, hasLength(1));
        expect(controller.state.captureCandidates, hasLength(1));
        expect(controller.state.captureCandidates.single.source, source);
        expect(controller.state.ingressReceipts, hasLength(1));
        await process();
        expect(controller.state.captureCandidates, hasLength(1));
        expect(controller.state.ingressReceipts, isEmpty);
        expect(await queue.pending('owner-a', source), isEmpty);
      },
    );
  }

  testWidgets(
    'settings retain scheduled reminders without an inactive quiet-hours toggle',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(prefs: prefs),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quiet hours'), findsNothing);
      expect(find.text('Device notifications'), findsOneWidget);
      expect(find.text('Scheduled records'), findsOneWidget);
    },
  );
}
