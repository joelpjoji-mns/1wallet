import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/settings_components.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/widgets/user_identity_widgets.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';

const _nativeCaptureChannel = MethodChannel('com.joelpjoji.one.wallet/sms');

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('AuthUser.initials', () {
    test('offline local user with name returns first letter uppercase', () {
      final user = AuthUser.local(displayName: 'Joel');
      expect(user.initials, 'J');

      final userLowercase = AuthUser.local(displayName: 'joel');
      expect(userLowercase.initials, 'J');

      final userMultiWord = AuthUser.local(displayName: 'Joel P Joji');
      expect(userMultiWord.initials, 'J');
    });

    test('offline local user without name falls back to 1W', () {
      final userNull = AuthUser.local(displayName: null);
      expect(userNull.initials, '1W');

      final userEmpty = AuthUser.local(displayName: '   ');
      expect(userEmpty.initials, '1W');
    });

    test('online/Firebase user uses standard 2-character initials', () {
      const userMultiWord = AuthUser(
        id: 'user-1',
        email: 'joel@example.com',
        displayName: 'Joel Joji',
        provider: 'google.com',
      );
      expect(userMultiWord.initials, 'JJ');

      const userSingleWord = AuthUser(
        id: 'user-2',
        email: 'joel@example.com',
        displayName: 'Joel',
        provider: 'google.com',
      );
      expect(userSingleWord.initials, 'J');
    });
  });

  group('Offline avatar in UI', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _nativeCaptureChannel,
            (call) async => null,
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_nativeCaptureChannel, null);
    });

    testWidgets(
      'displays first letter of name in offline mode and allows editing in settings',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await initializeDateFormatting('en_IN');

        SharedPreferences.setMockInitialValues({
          AppModeStore.storageKey: AppMode.offline.name,
          AppModeStore.localDisplayNameKey: 'Joel',
          'one_wallet_flutter.permissions_setup.completed.local-user': true,
          'one_wallet_flutter.onboarding.completed.local-user': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            ledgerRepositoryProvider.overrideWithValue(
              MemoryLedgerRepository(sampleLedgerState()),
            ),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(appRouterProvider);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light(),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await _frames(tester);

        expect(container.read(authControllerProvider).isLocalOnly, isTrue);

        // On HomeScreen, verify the profile action button displays "J" rather than "1W"
        final homeActionButton = find.byType(AuthUserActionButton);
        expect(homeActionButton, findsOneWidget);
        expect(
          find.descendant(of: homeActionButton, matching: find.text('J')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: homeActionButton, matching: find.text('1W')),
          findsNothing,
        );

        // Navigate to settings
        router.push('/settings');
        await _frames(tester);

        // Verify the settings profile section displays "Joel" and avatar "J"
        final settingsProfile = find.byType(SettingsProfileSection);
        expect(settingsProfile, findsOneWidget);
        expect(
          find.descendant(of: settingsProfile, matching: find.text('Joel')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: settingsProfile, matching: find.text('J')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

        // Tap the edit icon to change name
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await _frames(tester);

        expect(find.text('Your name'), findsWidgets);
        final nameField = find.widgetWithText(TextField, 'Enter your name');
        expect(nameField, findsOneWidget);

        await tester.enterText(nameField, 'Alex');
        await tester.tap(find.text('Save'));
        await _frames(tester);

        // Verify name changed to Alex and avatar updated to A
        expect(
          find.descendant(of: settingsProfile, matching: find.text('Alex')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: settingsProfile, matching: find.text('A')),
          findsOneWidget,
        );
      },
    );
  });
}
