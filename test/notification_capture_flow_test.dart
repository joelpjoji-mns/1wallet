import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/notification_capture_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.joelpjoji.one.wallet/sms');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LedgerProvidersConfig.disableAutoBackup = true;
  });

  tearDown(() {
    LedgerProvidersConfig.disableAutoBackup = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('NotificationCaptureScreen renders scan card and performs scan', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkNotificationPermission':
          return true;
        case 'readActiveNotifications':
          return jsonEncode([
            {
              'id': 'notif_1',
              'packageName': 'com.google.android.apps.nbu.paisa.user',
              'appName': 'Google Pay',
              'title': 'Paid to Starbucks',
              'text': 'INR 350.00 debited from account',
              'bigText': 'UPI Ref 987654321',
              'body': 'Paid to Starbucks INR 350.00 debited from account',
              'date': DateTime.now().millisecondsSinceEpoch,
            },
            {
              'id': 'notif_2',
              'packageName': 'com.android.systemui',
              'appName': 'Android System',
              'title': 'System update',
              'text': 'Your phone is up to date',
              'bigText': '',
              'body': 'System update Your phone is up to date',
              'date': DateTime.now().millisecondsSinceEpoch,
            },
          ]);
        default:
          return null;
      }
    });

    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const NotificationCaptureScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify "Scan active notifications" is rendered
    expect(find.text('Scan active notifications'), findsWidgets);
    expect(
      find.text(
        'Find transactions in notifications currently waiting in your status bar or notification shade.',
      ),
      findsOneWidget,
    );

    // Tap "Scan active notifications" button
    final scanButton = find.widgetWithText(
      FilledButton,
      'Scan active notifications',
    );
    expect(scanButton, findsOneWidget);
    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    // Verify scan results bottom sheet shows up with summary
    expect(find.text('Scan results'), findsOneWidget);
    expect(
      find.text('Scanned 2 notifications · 1 queued · 0 duplicates'),
      findsOneWidget,
    );
    expect(find.text('Open review queue (1 queued)'), findsOneWidget);

    // Verify the candidate was queued in ledger state
    final candidates = container.read(ledgerProvider).captureCandidates;
    expect(candidates, isNotEmpty);
    expect(candidates.first.source, 'notification');
    expect(candidates.first.parsedAmount?.amountMinor, 35000);
  });
}
