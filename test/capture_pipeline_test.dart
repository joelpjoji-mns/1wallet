import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/capture/capture_pipeline.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

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

  test('valid test message queues, then duplicate reports a clear reason', () async {
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
  });

  test('native accepted message is queued even after Dart rules no longer match', () async {
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
  });

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
}
