import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

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

  for (final scale in [1.0, 2.0]) {
    testWidgets('compact Settings profile remains readable at ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var edits = 0;
      var signOuts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: SettingsProfileSection(
                user: null,
                onEditName: () => edits++,
                onSignOut: () => signOuts++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['1wallet account', 'Not signed in']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
          reason: label,
        );
      }
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.tap(find.text('Sign out'));
      expect(edits, 1);
      expect(signOuts, 1);
    });
  }
}
