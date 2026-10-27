import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/account_deletion_controller.dart';
import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  setUp(() {
    LedgerProvidersConfig.disableAutoBackup = true;
    SharedPreferences.setMockInitialValues({
      'has_unsynced_changes': true,
      'one_wallet_flutter.theme.preference.v1': 'amoled',
    });
  });

  Future<ProviderContainer> pumpSettingsScreen(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(
        ledger: sampleLedgerState(),
        prefs: prefs,
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: const SettingsScreen(),
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Settings screen displays Danger zone and Delete account option',
    (tester) async {
      await pumpSettingsScreen(tester);

      // Scroll to the bottom to reveal the Danger zone
      await tester.scrollUntilVisible(
        find.text('Delete account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Danger zone'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(
        find.text(
          'Delete this account\'s cloud data and its wallet on this device.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Delete account dialog enforces typing DELETE to enable confirmation',
    (tester) async {
      await pumpSettingsScreen(tester);

      await tester.scrollUntilVisible(
        find.text('Delete account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Tap Delete account
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      // Dialog appears with warnings
      expect(find.text('Delete account & data?'), findsOneWidget);
      expect(
        find.text('• All cloud backups and synced data in Firebase'),
        findsOneWidget,
      );
      expect(
        find.text('• This account\'s device backups and encryption keys'),
        findsOneWidget,
      );

      // The Delete everything button is initially disabled
      final deleteButtonFinder = find.widgetWithText(
        FilledButton,
        'Delete everything',
      );
      expect(deleteButtonFinder, findsOneWidget);
      final deleteButton = tester.widget<FilledButton>(deleteButtonFinder);
      expect(deleteButton.onPressed, isNull);

      // Type something other than DELETE
      final inputFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputFinder, 'NO');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(deleteButtonFinder).onPressed, isNull);

      // Type DELETE
      await tester.enterText(inputFinder, 'DELETE');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(deleteButtonFinder).onPressed,
        isNotNull,
      );

      // Cancel dismisses the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account & data?'), findsNothing);
    },
  );

  test(
    'unavailable deletion cannot claim erasure or clear unrelated preferences',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('some_key', 'some_value');

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        accountDeletionControllerProvider.notifier,
      );
      final success = await controller.deleteAccountAndAllData();

      expect(success, isFalse);
      expect(
        container.read(accountDeletionControllerProvider).stage,
        AccountDeletionStage.error,
      );

      expect(prefs.getString('some_key'), 'some_value');
      expect(prefs.getBool('has_unsynced_changes'), isTrue);
    },
  );
}
