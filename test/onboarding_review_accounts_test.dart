import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid_glass;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/features/launch/brand_widgets.dart';
import 'package:one_wallet_flutter/src/features/onboarding/onboarding_screen.dart';
import 'package:one_wallet_flutter/src/features/onboarding/onboarding_controller.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_controller.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'offline_mode_fakes.dart';
import 'test_harness.dart';

// OnboardingScreen (like LoginScreen) is wrapped in LaunchBackdrop, which
// runs a deliberate, continuously-repeating decorative animation
// (AnimationController.repeat(reverse: true)). That keeps a frame scheduled
// forever, so `pumpAndSettle()` — which waits for scheduling to stop — always
// times out here. This is a real backdrop-widget characteristic (owned by
// the launch/brand_widgets scope, not something to "fix"), not a bug in this
// screen, so we drive the test with a bounded number of fixed-duration pumps
// instead, which is enough for the one-shot entrance/page-transition
// animations to finish.
Future<void> _pumpBounded(
  WidgetTester tester, {
  int times = 10,
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

  testWidgets('setup cannot finish without a first account', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(
        prefs: prefs,
        ledger: emptyLedgerState(),
      ),
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await _pumpBounded(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').first);
    await _pumpBounded(tester);
    await tester.ensureVisible(find.text('Skip for now'));
    await tester.tap(find.text('Skip for now'));
    await _pumpBounded(tester);
    await tester.ensureVisible(find.text('Looks good'));
    await tester.tap(find.text('Looks good'));
    await _pumpBounded(tester);
    await tester.ensureVisible(find.text('Finish Setup'));
    await tester.tap(find.text('Finish Setup'));
    await _pumpBounded(tester);
    expect(
      find.text('Add at least one account to finish setup.'),
      findsWidgets,
    );
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(container.read(ledgerProvider).accounts, isEmpty);
    expect(container.read(onboardingControllerProvider).completed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('review-accounts flow keeps working with glass inputs and rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await _pumpBounded(tester);

    // PageView only builds pages within its cache extent, so each step's
    // "Continue" button is (re)built fresh as the previous one scrolls
    // out — using `.first` each time reliably targets the current step's
    // controls rather than assuming every step is simultaneously mounted.

    // Step 1 (Profile) -> Step 2 (Account).
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').first);
    await _pumpBounded(tester);

    // Step 2 (Account): fill in one account and save it, which advances
    // straight to the review step.
    final textFields = find.byType(AppGlassTextField);
    await tester.enterText(textFields.at(0), 'Test Wallet');
    await tester.enterText(textFields.at(1), '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
    await _pumpBounded(tester);

    // Step 4 (Review): the account must render...
    final accountName = find.text('Test Wallet');
    expect(accountName, findsOneWidget);

    expect(
      find.ancestor(
        of: accountName,
        matching: find.byType(liquid_glass.GlassCard),
      ),
      findsWidgets,
    );
  });

  testWidgets('empty and whitespace account names show actionable feedback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await _pumpBounded(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _pumpBounded(tester);

    final save = find.widgetWithText(FilledButton, 'Save account');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpBounded(tester);
    expect(find.text('Enter an account name before saving.'), findsWidgets);
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.enterText(find.byType(AppGlassTextField).first, '   ');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpBounded(tester);
    expect(find.text('Enter an account name before saving.'), findsWidgets);
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.enterText(find.byType(AppGlassTextField).first, '  Cash  ');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpBounded(tester);
    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
  });

  testWidgets('account step keeps clear spacing on compact screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const OnboardingScreen(),
          ),
        ),
      );
      await _pumpBounded(tester);
      final next = find.widgetWithText(FilledButton, 'Continue');
      final profileScroll = tester.widget<Scrollable>(
        find
            .ancestor(
              of: find.text('Welcome.\nLet\'s set you up.'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.scrollUntilVisible(
        next,
        200,
        scrollable: find.byWidget(profileScroll),
      );
      await _pumpBounded(tester);
      await tester.ensureVisible(next);
      await tester.pump();
      await tester.tap(next);
      await _pumpBounded(tester);

      final preview = find
          .ancestor(
            of: find.text('Account Name'),
            matching: find.byType(AppPanel),
          )
          .first;
      final form = find
          .ancestor(
            of: find.text('Account name'),
            matching: find.byType(BrandFrostedPanel),
          )
          .first;
      expect(
        tester.getTopLeft(form).dy - tester.getBottomLeft(preview).dy,
        greaterThanOrEqualTo(AppSpacing.md),
        reason: 'preview and form need a visible gap at $scale text scale',
      );
      expect(
        tester.getTopLeft(form).dx,
        closeTo(tester.getTopLeft(preview).dx, 0.1),
      );

      final balance = find.byWidgetPredicate(
        (widget) =>
            widget is AppGlassTextField &&
            widget.decoration.hintText == 'Current balance',
      );
      final changeSign = find.widgetWithText(TextButton, 'Change sign');
      expect(
        tester.getTopLeft(changeSign).dy - tester.getBottomLeft(balance).dy,
        greaterThanOrEqualTo(AppSpacing.xs),
      );

      final skip = find.widgetWithText(TextButton, 'Skip for now');
      final accountScroll = tester.widget<Scrollable>(
        find
            .ancestor(
              of: find.text('Add your first\naccount.'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.scrollUntilVisible(
        skip,
        200,
        scrollable: find.byWidget(accountScroll),
      );
      final save = find.widgetWithText(FilledButton, 'Save account');
      expect(
        tester.getTopLeft(skip).dy - tester.getBottomLeft(save).dy,
        greaterThanOrEqualTo(AppSpacing.xs),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('long institution names do not overflow the account preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await _pumpBounded(tester);
    final next = find.widgetWithText(FilledButton, 'Continue');
    final profileScrollable = tester.widget<Scrollable>(
      find
          .ancestor(
            of: find.text('Welcome.\nLet\'s set you up.'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.scrollUntilVisible(
      next,
      200,
      scrollable: find.byWidget(profileScrollable),
    );
    await _pumpBounded(tester);
    await tester.ensureVisible(next);
    await tester.pump();
    await tester.tap(next);
    await _pumpBounded(tester);

    final institution = find.byWidgetPredicate(
      (widget) =>
          widget is AppGlassTextField &&
          widget.decoration.hintText == 'e.g. Chase, Revolut, Cash in wallet',
    );
    final accountScroll = find
        .ancestor(
          of: find.text('Add your first\naccount.'),
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollState = tester.state<ScrollableState>(accountScroll);
    await tester.ensureVisible(institution);
    await tester.enterText(
      institution,
      'International Community Credit Union and Cooperative Financial Services',
    );
    await _pumpBounded(tester);
    scrollState.position.jumpTo(0);
    await _pumpBounded(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding saves a negative opening balance', (tester) async {
    final (container, repository) = await _pumpOfflineOnboarding(tester);
    await _addAccountAndReachFinish(tester, '-500.25');
    await tester.tap(find.widgetWithText(FilledButton, 'Finish Setup'));
    await _pumpBounded(tester);

    final account = container.read(ledgerProvider).accounts.single;
    expect(account.openingBalance.amountMinor, -50025);
    expect(
      repository.saved!.accounts.single.openingBalance.amountMinor,
      -50025,
    );
    expect(find.text('Setup complete'), findsOneWidget);
    expect(
      container.read(discoveryControllerProvider('local-user')).status,
      DiscoveryStatus.welcome,
    );
  });

  testWidgets('account colors have named, selectable 48dp targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpOfflineOnboarding(tester);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pump();
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    final profileScroll = find
        .ancestor(
          of: find.text('Welcome.\nLet\'s set you up.'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      continueButton,
      200,
      scrollable: profileScroll,
    );
    await _pumpBounded(tester);
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await _pumpBounded(tester);

    final blue = find.byTooltip('Blue account color');
    final green = find.byTooltip('Forest green account color');
    final custom = find.byTooltip('Choose custom account color');
    for (final label in [
      'Blue account color',
      'Forest green account color',
      'Choose custom account color',
    ]) {
      final target = find.byTooltip(label);
      await tester.ensureVisible(target);
      await _pumpBounded(tester);
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel(label), findsOneWidget);
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Choose custom account color'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    await tester.ensureVisible(blue);
    await _pumpBounded(tester);
    await tester.tapAt(tester.getTopLeft(blue) + const Offset(2, 2));
    await _pumpBounded(tester);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Blue account color'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    await tester.ensureVisible(green);
    await _pumpBounded(tester);
    await tester.tapAt(tester.getTopLeft(green) + const Offset(2, 2));
    await _pumpBounded(tester);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Blue account color'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Forest green account color'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    await tester.ensureVisible(custom);
    await _pumpBounded(tester);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Choose custom account color'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    await tester.tapAt(tester.getTopLeft(custom) + const Offset(2, 2));
    await _pumpBounded(tester);
    expect(find.text('Choose account color'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _pumpBounded(tester);
    semantics.dispose();
  });

  testWidgets('changing the balance sign returns focus to the amount', (
    tester,
  ) async {
    await _pumpOfflineOnboarding(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _pumpBounded(tester);
    final balance = find.byType(AppGlassTextField).at(1);
    await tester.enterText(balance, '500.25');
    await tester.tap(find.text('Change sign'));
    await tester.pump();
    final field = tester.widget<AppGlassTextField>(balance);
    expect(field.controller!.text, '-500.25');
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('setup preserves an existing wallet that appeared meanwhile', (
    tester,
  ) async {
    final (container, repository) = await _pumpOfflineOnboarding(tester);
    await _addAccountAndReachFinish(tester, '100');
    final existing = container
        .read(ledgerProvider)
        .copyWith(
          accounts: const [
            Account(
              id: 'existing',
              name: 'Existing wallet',
              type: 'bank',
              currency: 'USD',
              openingBalance: Money(amountMinor: 76543, currency: 'USD'),
            ),
          ],
          preferences: container
              .read(ledgerProvider)
              .preferences
              .copyWith(smsCaptureEnabled: false),
        );
    await container.read(ledgerProvider.notifier).restoreLedgerState(existing);
    await _pumpBounded(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Finish Setup'));
    await _pumpBounded(tester);

    expect(repository.saved!.accounts.single.id, 'existing');
    expect(repository.saved!.accounts.single.openingBalance.amountMinor, 76543);
    expect(repository.saved!.preferences.smsCaptureEnabled, isFalse);
    expect(
      find.textContaining('Your existing wallet was kept.'),
      findsOneWidget,
    );
    expect(container.read(onboardingControllerProvider).completed, isTrue);
    expect(
      container.read(discoveryControllerProvider('local-user')).status,
      DiscoveryStatus.dormant,
    );
  });

  testWidgets('invalid balances are explained instead of saved as zero', (
    tester,
  ) async {
    await _pumpOfflineOnboarding(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _pumpBounded(tester);
    final fields = find.byType(AppGlassTextField);
    await tester.enterText(fields.at(0), 'Wallet');
    await tester.enterText(fields.at(1), '-');
    final save = find.widgetWithText(FilledButton, 'Save account');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpBounded(tester);
    expect(
      find.text('Enter a valid balance within the supported range.'),
      findsOneWidget,
    );
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.enterText(fields.at(1), '99999999999999');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _pumpBounded(tester);
    expect(
      find.text('Enter a valid balance within the supported range.'),
      findsOneWidget,
    );
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('failed setup keeps both drafts and retries without duplicates', (
    tester,
  ) async {
    final repository = _PausedLedgerRepository();
    final (container, _) = await _pumpOfflineOnboarding(
      tester,
      repository: repository,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _pumpBounded(tester);
    var fields = find.byType(AppGlassTextField);
    await tester.enterText(fields.at(0), 'Checking');
    await tester.enterText(fields.at(1), '100');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
    await _pumpBounded(tester);
    await tester.tap(find.text('Add another account'));
    await _pumpBounded(tester);
    fields = find.byType(AppGlassTextField);
    expect(
      tester.widget<AppGlassTextField>(fields.at(0)).controller!.text,
      isEmpty,
    );
    await tester.enterText(fields.at(0), 'Savings');
    await tester.enterText(fields.at(1), '50');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save account'));
    await _pumpBounded(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Looks good'));
    await _pumpBounded(tester);
    await tester.tap(find.text('Auto-capture transactions'));
    await _pumpBounded(tester);
    final originalPreferences = container.read(ledgerProvider).preferences;
    repository.failNextSave = true;
    final finish = find.widgetWithText(FilledButton, 'Finish Setup');
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await _pumpBounded(tester);

    expect(find.textContaining('Could not finish setup.'), findsOneWidget);
    expect(container.read(ledgerProvider).accounts, isEmpty);
    expect(
      container.read(ledgerProvider).preferences.smsCaptureEnabled,
      originalPreferences.smsCaptureEnabled,
    );
    expect(container.read(onboardingControllerProvider).completed, isFalse);

    await tester.tap(finish);
    await _pumpBounded(tester);
    final accounts = repository.saved!.accounts;
    expect(accounts.map((account) => account.name), ['Checking', 'Savings']);
    expect(accounts.map((account) => account.id).toSet(), hasLength(2));
    expect(repository.saved!.preferences.smsCaptureEnabled, isFalse);
    expect(container.read(onboardingControllerProvider).completed, isTrue);
    expect(find.text('Setup complete'), findsOneWidget);
  });

  testWidgets('finishing setup cannot submit twice while saving', (
    tester,
  ) async {
    final repository = _PausedLedgerRepository();
    final (container, _) = await _pumpOfflineOnboarding(
      tester,
      repository: repository,
    );
    await _addAccountAndReachFinish(tester, '100');
    repository.pause();

    final finish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Finish Setup'),
    );
    finish.onPressed!();
    finish.onPressed!();
    await _pumpBounded(tester, times: 2);
    final saving = find.widgetWithText(FilledButton, 'Finishing...');
    expect(saving, findsOneWidget);
    expect(tester.widget<FilledButton>(saving).onPressed, isNull);

    repository.resume();
    await _pumpBounded(tester);
    expect(container.read(ledgerProvider).accounts, hasLength(1));
    expect(repository.saved!.accounts, hasLength(1));
    expect(find.text('Setup complete'), findsOneWidget);
  });
}

Future<(ProviderContainer, _PausedLedgerRepository)> _pumpOfflineOnboarding(
  WidgetTester tester, {
  _PausedLedgerRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({AppModeStore.storageKey: 'offline'});
  final prefs = await SharedPreferences.getInstance();
  final wallet = repository ?? _PausedLedgerRepository();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ledgerRepositoryProvider.overrideWithValue(wallet),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/permissions-setup',
        builder: (_, _) => const Scaffold(body: Text('Setup complete')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await _pumpBounded(tester);
  return (container, wallet);
}

Future<void> _addAccountAndReachFinish(
  WidgetTester tester,
  String opening,
) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await _pumpBounded(tester);
  final fields = find.byType(AppGlassTextField);
  await tester.enterText(fields.at(0), 'Credit card');
  await tester.enterText(fields.at(1), opening);
  final save = find.widgetWithText(FilledButton, 'Save account');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await _pumpBounded(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Looks good'));
  await _pumpBounded(tester);
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Finish Setup'));
}

class _PausedLedgerRepository extends MemoryLedgerRepository {
  Completer<void>? _gate;
  bool failNextSave = false;

  void pause() => _gate = Completer<void>();

  void resume() => _gate!.complete();

  @override
  Future<void> save(LedgerState state) async {
    await _gate?.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Simulated storage failure');
    }
    await super.save(state);
  }
}
