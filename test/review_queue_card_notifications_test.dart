import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_queue.dart';
import 'package:one_wallet_flutter/src/features/capture/review_queue_screen.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_controller.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'offline_mode_fakes.dart';
import 'test_harness.dart';

Future<void> _pumpBounded(
  WidgetTester tester, {
  int times = 5,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('review stays quiet until a guide is requested', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final oldQueue = CaptureQueue.client;
    CaptureQueue.client = MemoryCaptureQueue();
    addTearDown(() => CaptureQueue.client = oldQueue);
    final prefs = await SharedPreferences.getInstance();
    const user = AuthUser(id: 'review-user', email: 'review@example.test');
    final container = ProviderContainer(
      overrides: [
        ...authenticatedSampleOverrides(
          ledger: emptyLedgerState(userId: user.id),
          prefs: prefs,
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(currentUser: user),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(discoveryControllerProvider(user.id).notifier)
        .finish();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReviewQueueScreen(),
        ),
      ),
    );
    await _pumpBounded(tester);
    expect(find.text('Review your alerts'), findsNothing);
    expect(find.byTooltip('Close guide'), findsNothing);
    expect(find.text('All caught up'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await container
        .read(discoveryControllerProvider(user.id).notifier)
        .replayHint('review-inbox');
    await _pumpBounded(tester);
    expect(find.text('Message to account'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Close guide'));
    await _pumpBounded(tester);
    await tester.tap(find.byTooltip('Close guide'));
    await _pumpBounded(tester);
    expect(find.text('Message to account'), findsNothing);
    expect(
      container.read(discoveryControllerProvider(user.id)).requestedHint,
      isNull,
    );
    final restored = DiscoveryController(prefs, user.id);
    expect(restored.state.introduced, contains('review-inbox'));
    restored.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'ReviewQueueScreen renders credit card notification with Confirm Paid and Dismiss actions',
    (tester) async {
      final now = DateTime.now();
      final cardAccount = Account(
        id: 'cc-test-1',
        name: 'Freedom Unlimited',
        institution: 'Chase Bank',
        type: 'credit_card',
        currency: 'USD',
        openingBalance: const Money(amountMinor: -45000, currency: 'USD'),
        creditLimit: const Money(amountMinor: 1000000, currency: 'USD'),
        statementDay: 1,
        dueDay: now.day,
        notifyDaysBeforeDue: 3,
      );

      final seedState = LedgerState(
        version: 1,
        userId: 'test-user',
        accounts: [cardAccount],
        transactions: const [],
        categories: const [],
        captureCandidates: const [],
        preferences: const LedgerPreferences(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
          notificationInboxEnabled: true,
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(
          ledger: seedState,
          prefs: prefs,
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(seedState);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            home: const ReviewQueueScreen(),
          ),
        ),
      );
      await _pumpBounded(tester);

      // Verify card notification title and card name appear
      expect(find.text('Freedom Unlimited'), findsOneWidget);
      expect(find.text('Confirm Paid'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      // Tap Confirm Paid
      await tester.tap(find.text('Confirm Paid'));
      await _pumpBounded(tester);

      // Verify account was marked paid in state
      final updatedAccount = container
          .read(ledgerProvider)
          .accounts
          .firstWhere((a) => a.id == 'cc-test-1');
      expect(updatedAccount.lastPaidBillMonth, isNotNull);
    },
  );
}
