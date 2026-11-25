import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  Size size = const Size(800, 1000),
  double textScale = 1,
  EdgeInsets safePadding = EdgeInsets.zero,
  FakeAuthRepository? authRepository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(
        authRepository ?? FakeAuthRepository(),
      ),
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
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: safePadding,
            viewPadding: safePadding,
          ),
          child: child!,
        ),
        home: const LoginScreen(),
      ),
    ),
  );
  await _settleFrames(tester);
  return (container, prefs);
}

Future<void> _openOfflineSheet(WidgetTester tester) async {
  final button = find.byKey(LoginScreen.offlineButtonKey);
  await tester.ensureVisible(button);
  await _settleFrames(tester);
  expect(button.hitTestable(), findsOneWidget);
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
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  testWidgets('welcome fits phones without scrolling or hiding its footer', (
    tester,
  ) async {
    const safePadding = EdgeInsets.only(top: 24, bottom: 24);
    for (final size in [
      const Size(320, 568),
      const Size(360, 780),
      const Size(430, 932),
      const Size(1024, 800),
    ]) {
      await _pumpLogin(tester, size: size, safePadding: safePadding);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(
        scroll.position.maxScrollExtent,
        closeTo(0, 0.01),
        reason: 'Welcome should fit at $size',
      );
      expect(
        scroll.position.physics.shouldAcceptUserOffset(scroll.position),
        isFalse,
      );
      final footer = tester.getRect(
        find.text('Secure • Private • Local First'),
      );
      expect(
        footer.bottom,
        lessThanOrEqualTo(size.height - safePadding.bottom),
      );
      expect(footer.top, greaterThanOrEqualTo(safePadding.top));
      expect(
        find.byKey(LoginScreen.offlineButtonKey).hitTestable(),
        findsOneWidget,
      );
      final heading = tester.getRect(find.textContaining('1Wallet.'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
      await tester.pump();
      expect(tester.getRect(find.textContaining('1Wallet.')), heading);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'standard welcome keeps full branding and balanced action placement',
    (tester) async {
      await _pumpLogin(
        tester,
        size: const Size(360, 780),
        safePadding: const EdgeInsets.only(top: 24, bottom: 24),
      );
      expect(find.text('Welcome.\n1Wallet.'), findsOneWidget);
      final ready = tester.getRect(find.text('Ready to start?'));
      expect(ready.top, greaterThan(780 * 0.25));
      expect(ready.bottom, lessThan(780 * 0.65));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short and large-text welcome keeps its entire footer reachable',
    (tester) async {
      for (final (size, scale) in [
        (const Size(320, 568), 2.0),
        (const Size(780, 360), 1.0),
      ]) {
        await _pumpLogin(
          tester,
          size: size,
          textScale: scale,
          safePadding: const EdgeInsets.only(top: 24, bottom: 24),
        );
        final footer = find.text('Secure • Private • Local First');
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        await tester.ensureVisible(footer);
        await tester.pump();
        final bounds = tester.getRect(footer);
        expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
        expect(bounds.top, greaterThanOrEqualTo(24));
        expect(
          tester.renderObject<RenderParagraph>(footer).didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'unavailable sign-in and errors keep the privacy footer reachable',
    (tester) async {
      for (final available in [false, true]) {
        final repository = FakeAuthRepository(available: available);
        final (container, _) = await _pumpLogin(
          tester,
          size: const Size(360, 780),
          safePadding: const EdgeInsets.only(top: 24, bottom: 24),
          authRepository: repository,
        );
        if (available) {
          repository.signInError = StateError(
            'Unable to connect. Please check your connection and try signing in again.',
          );
          await tester.runAsync(
            () => container
                .read(authControllerProvider.notifier)
                .signInWithGoogle(),
          );
          await _settleFrames(tester);
          expect(
            container.read(authControllerProvider).errorMessage,
            isNotNull,
          );
        }
        final footer = find.text('Secure • Private • Local First');
        await tester.ensureVisible(footer);
        await tester.pump();
        expect(tester.getRect(footer).bottom, lessThanOrEqualTo(756));
        expect(
          tester.renderObject<RenderParagraph>(footer).didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

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

  testWidgets('Google sign-in label keeps button padding', (tester) async {
    await _pumpLogin(tester, size: const Size(360, 2000), textScale: 2);
    final label = tester.getRect(find.text('Continue with Google'));
    final button = tester.getRect(
      find
          .ancestor(
            of: find.text('Continue with Google'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(label.left - button.left, greaterThanOrEqualTo(16));
    expect(button.right - label.right, greaterThanOrEqualTo(16));
  });

  testWidgets('offline action retains its full accessible name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpLogin(tester, size: const Size(360, 2000), textScale: 2);
    final button = find.byKey(LoginScreen.offlineButtonKey);
    await tester.ensureVisible(button);
    await _settleFrames(tester);
    final data = tester.getSemantics(button).getSemanticsData();
    expect(data.label, 'Use without an account (Offline)');
    semantics.dispose();
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
