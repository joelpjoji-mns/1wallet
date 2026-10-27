import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/capture/capture_pipeline.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_diagnostics.dart';
import 'package:one_wallet_flutter/src/features/capture/sms_inbox_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LedgerProvidersConfig.disableAutoBackup = true;
  });

  tearDown(() {
    LedgerProvidersConfig.disableAutoBackup = false;
  });

  Future<LedgerController> controllerWithAccount() async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    await Future<void>.delayed(Duration.zero);
    await controller.upsertAccount(
      id: 'acc-main',
      name: 'Main bank',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 0,
      institution: 'HDFC',
    );
    return controller;
  }

  test(
    'valid test message queues, then duplicate reports a clear reason',
    () async {
      final controller = await controllerWithAccount();
      addTearDown(controller.dispose);

      const sms =
          'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on 08-Jun.';
      final result = await controller.importSmsMessageDetailed(
        sms,
        stage: 'test-message',
      );

      expect(result.status, CaptureImportStatus.queued);
      expect(result.candidate?.merchant, 'SWIGGY');
      expect(controller.state.captureCandidates, hasLength(1));

      final duplicatePreview = controller.previewSmsMessage(sms);
      expect(duplicatePreview.status, CaptureImportStatus.duplicate);
      expect(duplicatePreview.reason, CaptureBlockReason.duplicatePending);

      final duplicateAdd = await controller.importSmsMessageDetailed(
        sms,
        stage: 'test-message',
      );
      expect(duplicateAdd.status, CaptureImportStatus.duplicate);
      expect(duplicateAdd.userMessage, contains('review queue'));
      expect(controller.state.captureCandidates, hasLength(1));
    },
  );

  test(
    'native accepted message is queued even after Dart rules no longer match',
    () async {
      final controller = await controllerWithAccount();
      addTearDown(controller.dispose);

      const sms = 'INR 125.00 moved at Corner Store on 08-Jun.';
      final preview = controller.previewSmsMessage(sms);
      expect(preview.status, CaptureImportStatus.ignored);
      expect(preview.reason, CaptureBlockReason.missingTrigger);

      final forced = await controller.importSmsMessageDetailed(
        sms,
        stage: 'spool-sms',
        nativeAccepted: true,
        notificationShown: true,
        forceQueue: true,
      );

      expect(forced.status, CaptureImportStatus.queued);
      expect(forced.notificationShown, isTrue);
      expect(forced.nativeAccepted, isTrue);
      expect(controller.state.captureCandidates, hasLength(1));
    },
  );

  test('market and supermarket seller text suggests groceries', () async {
    final controller = await controllerWithAccount();
    addTearDown(controller.dispose);

    final result = await controller.importSmsMessageDetailed(
      'HDFC Bank: INR 450.00 debited at Supermarket groceries on 08-Jun.',
      stage: 'test-message',
    );

    expect(result.status, CaptureImportStatus.queued);
    expect(result.candidate?.suggestedCategoryId, 'cat-grocery');
    expect(result.candidate?.suggestedCategoryReason, contains('Grocery'));
  });

  test('learned merchant category overrides keyword guess next time', () async {
    final controller = await controllerWithAccount();
    addTearDown(controller.dispose);

    await controller.rememberMerchantCategory(
      merchant: 'Daily Market',
      categoryId: 'cat-dining',
    );
    final result = await controller.importSmsMessageDetailed(
      'HDFC Bank: INR 300.00 debited at Daily Market on 08-Jun.',
      stage: 'test-message',
    );

    expect(result.status, CaptureImportStatus.queued);
    expect(result.candidate?.suggestedCategoryId, 'cat-dining');
    expect(result.candidate?.suggestedCategoryReason, contains('Learned'));
  });

  test(
    'matches already posted transaction as duplicate and populates duplicateOfId',
    () async {
      final controller = await controllerWithAccount();
      addTearDown(controller.dispose);

      // Add a manual or posted transaction
      final tx = await controller.upsertTransaction(
        id: 'tx-existing-1',
        type: 'expense',
        accountId: 'acc-main',
        amountMinor: 89000, // INR 890.00
        name: 'SWIGGY',
        occurredAt: DateTime.now(),
      );

      const sms =
          'HDFC Bank: INR 890.00 debited from card XX1234 at SWIGGY on today.';
      final preview = controller.previewSmsMessage(sms);

      expect(preview.status, CaptureImportStatus.duplicate);
      expect(preview.reason, CaptureBlockReason.duplicatePosted);
      expect(preview.duplicateOfId, tx.id);
      expect(preview.duplicateOfType, 'transaction');
    },
  );

  test(
    'importNotificationsBatchDetailed scans multiple notifications and queues valid ones with source notification',
    () async {
      final controller = await controllerWithAccount();
      addTearDown(controller.dispose);

      final now = DateTime.now();
      final batch = [
        (
          text: 'Google Pay: Paid INR 250.00 to Starbucks on UPI',
          receivedAt: now,
          sender: 'Google Pay',
        ),
        (
          text: 'Daily horoscope: today will be a bright and sunny day',
          receivedAt: now,
          sender: 'Daily News',
        ),
        (
          text: 'Google Pay: Paid INR 250.00 to Starbucks on UPI',
          receivedAt: now,
          sender: 'Google Pay',
        ),
      ];

      final results = await controller.importNotificationsBatchDetailed(batch);
      expect(results, hasLength(3));

      // 1st is queued
      expect(results[0].queued, isTrue);
      expect(results[0].status, CaptureImportStatus.queued);
      expect(results[0].source, 'notification');
      expect(results[0].candidate?.merchant, contains('Starbucks'));

      // 2nd is ignored
      expect(results[1].ignored, isTrue);
      expect(results[1].status, CaptureImportStatus.ignored);

      // 3rd is duplicate of the queued candidate
      expect(results[2].duplicate, isTrue);
      expect(results[2].status, CaptureImportStatus.duplicate);

      // Verify only 1 candidate was added to state with source notification
      expect(controller.state.captureCandidates, hasLength(1));
      expect(controller.state.captureCandidates.first.source, 'notification');

      // Verify diagnostics recorded
      final events = await CaptureDiagnostics.recentEvents(
        ownerId: controller.state.userId,
      );
      final scanEvents = events
          .where((e) => e.stage == 'scan-notification')
          .toList();
      expect(scanEvents, hasLength(3));
    },
  );

  test(
    'readActiveAndroidNotifications invokes method channel and parses notifications',
    () async {
      const channel = MethodChannel('com.joelpjoji.one.wallet/sms');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'readActiveNotifications') {
          return jsonEncode([
            {
              'id': 'sbn_1',
              'packageName': 'com.google.android.apps.nbu.paisa.user',
              'appName': 'Google Pay',
              'title': 'Paid to Starbucks',
              'text': 'INR 250.00 debited from bank account',
              'bigText': 'Ref no 123456789',
              'body': 'Paid to Starbucks INR 250.00 debited from bank account',
              'date': 1700000000000,
            },
            {
              'id': 'sbn_2',
              'packageName': 'com.whatsapp',
              'appName': 'WhatsApp',
              'title': 'Alice',
              'text': 'See you at 5pm!',
              'bigText': '',
              'body': 'Alice See you at 5pm!',
              'date': 1700000010000,
            },
          ]);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final notifications = await readActiveAndroidNotifications();
      expect(notifications, hasLength(2));
      expect(notifications[0].id, 'sbn_1');
      expect(notifications[0].appName, 'Google Pay');
      expect(
        notifications[0].packageName,
        'com.google.android.apps.nbu.paisa.user',
      );
      expect(
        notifications[0].body,
        'Paid to Starbucks INR 250.00 debited from bank account',
      );
      expect(notifications[1].appName, 'WhatsApp');
    },
  );

  test(
    'approveCaptureCandidate captures the full SMS or notification body in transaction notes',
    () async {
      final controller = await controllerWithAccount();
      addTearDown(controller.dispose);

      const fullMessage =
          'HDFC Bank: Rs 550.00 debited from a/c **1234 on 26-Oct at Starbucks Coffee Pvt Ltd. Ref: 987654321.';
      final result = await controller.importSmsMessageDetailed(
        fullMessage,
        stage: 'test-notes',
      );

      expect(result.status, CaptureImportStatus.queued);
      final candidateId = result.candidate!.id;

      final tx = await controller.approveCaptureCandidate(candidateId);
      expect(tx.notes, fullMessage);
    },
  );
}
