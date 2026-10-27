import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/login/login_screen.dart';
import 'package:one_wallet_flutter/src/features/login/offline_mode_sheet.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';

Future<void> _settleFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(ProviderContainer, SharedPreferences)> _pumpLogin(
  WidgetTester tester, {
  LedgerState? storedWallet,
}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ledgerRepositoryProvider.overrideWithValue(
        MemoryLedgerRepository(storedWallet),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(ledgerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    ),
  );
  await _settleFrames(tester);
  return (container, prefs);
}

Future<void> _openOfflineSheet(WidgetTester tester) async {
  final button = find.byKey(LoginScreen.offlineButtonKey);
  await tester.scrollUntilVisible(
    button,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await _settleFrames(tester);
  expect(find.text('Use 1Wallet offline'), findsOneWidget);
}

ButtonStyleButton _confirmButton(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(find.byKey(OfflineModeSheet.confirmKey));

Future<void> _tapInSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settleFrames(tester);
  // Offline entry awaits SharedPreferences/ledger futures outside fake time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await _settleFrames(tester);
}

void main() {
  testWidgets('offline mode is offered and gated behind an acknowledgement', (
    tester,
  ) async {
    final (container, prefs) = await _pumpLogin(tester);
    expect(find.text('Continue with Google'), findsOneWidget);

    await _openOfflineSheet(tester);
    expect(find.textContaining('no cloud backup'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await _tapInSheet(tester, find.byKey(OfflineModeSheet.confirmKey));
    expect(container.read(authControllerProvider).isLocalOnly, isFalse);

    await _tapInSheet(tester, find.byKey(OfflineModeSheet.acknowledgeKey));
    expect(_confirmButton(tester).onPressed, isNotNull);

    await _tapInSheet(tester, find.byKey(OfflineModeSheet.confirmKey));

    final auth = container.read(authControllerProvider);
    expect(auth.isLocalOnly, isTrue);
    expect(auth.ownerId, localOwnerId);
    expect(auth.user, isNull);
    expect(AppModeStore(prefs).mode, AppMode.offline);
    expect(container.read(ledgerProvider).userId, localOwnerId);
  });

  testWidgets('cancel keeps the device on the sign-in screen', (tester) async {
    final (container, prefs) = await _pumpLogin(tester);
    await _openOfflineSheet(tester);

    await _tapInSheet(tester, find.text('Cancel'));

    expect(find.text('Use 1Wallet offline'), findsNothing);
    expect(container.read(authControllerProvider).isLocalOnly, isFalse);
    expect(AppModeStore(prefs).mode, AppMode.online);
  });

  testWidgets('a stored Google account wallet is never opened offline', (
    tester,
  ) async {
    final (container, prefs) = await _pumpLogin(
      tester,
      storedWallet: sampleLedgerState().copyWith(userId: 'google-uid-1'),
    );
    await _openOfflineSheet(tester);

    await _tapInSheet(tester, find.byKey(OfflineModeSheet.acknowledgeKey));
    await _tapInSheet(tester, find.byKey(OfflineModeSheet.confirmKey));

    expect(find.textContaining('linked to a Google account'), findsOneWidget);
    expect(container.read(authControllerProvider).isLocalOnly, isFalse);
    expect(AppModeStore(prefs).mode, AppMode.online);
    final ledger = container.read(ledgerProvider);
    expect(ledger.userId, 'google-uid-1');
    expect(ledger.transactions, isNotEmpty);
  });
}
