import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';
import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/calendar/calendar_screen.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_controller.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_cloud_store.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_overlay.dart';
import 'package:one_wallet_flutter/src/features/onboarding/onboarding_screen.dart';
import 'package:one_wallet_flutter/src/features/onboarding/discovery_coach_mark.dart';
import 'package:one_wallet_flutter/src/features/onboarding/feature_discovery_guide.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'offline_mode_fakes.dart';
import 'test_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    LedgerProvidersConfig.disableAutoBackup = true;
  });
  tearDown(() {
    binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
    LedgerProvidersConfig.disableAutoBackup = false;
  });

  test(
    'workflow journey skips device capture on unsupported platforms',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final prefs = await SharedPreferences.getInstance();
      final guide = DiscoveryController(prefs, 'platform-user');
      addTearDown(guide.dispose);
      await guide.startWorkflowTour();
      for (final feature in [
        'planned-payments',
        'loans',
        'loan-forecast',
        'account-details',
      ]) {
        await guide.completeFeatureGuide(feature);
      }
      expect(await guide.completeFeatureGuide('review-inbox'), 'calendar-days');
    },
  );

  test(
    'workflow guide position survives restart without automatically reopening',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final guide = DiscoveryController(prefs, 'first');
      await guide.startWorkflowTour();
      await guide.setGuideStep(1);
      final restored = DiscoveryController(prefs, 'first');
      final other = DiscoveryController(prefs, 'other');
      expect(restored.state.requestedHint, 'planned-payments');
      expect(restored.state.guideStep, 1);
      expect(restored.state.guideActive, isFalse);
      expect(other.state.requestedHint, isNull);
      await restored.resumeFeatureGuide();
      expect(restored.state.guideActive, isTrue);
      expect(await restored.completeFeatureGuide('planned-payments'), 'loans');
      expect(restored.state.guideStep, 0);
      guide.dispose();
      restored.dispose();
      other.dispose();
    },
  );

  testWidgets(
    'workflow samples use real matching without changing the wallet',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const user = AuthUser(id: 'sample-user', email: 'sample@example.test');
      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(prefs: prefs),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(currentUser: user),
          ),
        ],
      );
      addTearDown(container.dispose);
      final guide = container.read(
        discoveryControllerProvider(user.id).notifier,
      );
      await guide.replayHint('review-inbox');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OneWalletApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/review');
      await tester.pumpAndSettle();
      final before = container.read(ledgerProvider);
      await tester.tap(find.text('Show account match'));
      await tester.pumpAndSettle();
      expect(find.text('Suffix 4242 → Sample Everyday'), findsOneWidget);
      expect(container.read(ledgerProvider), same(before));
      await guide.replayHint('notification-capture');
      await tester.pumpAndSettle();
      expect(find.text('Match, then review'), findsOneWidget);
      expect(find.text('Suffix 4242 → Sample Everyday'), findsOneWidget);
      expect(container.read(ledgerProvider), same(before));
      await tester.tap(find.byTooltip('Close guide'));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryCoachMark), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('plan guide opens the real editor and leaves its draft unsaved', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    const user = AuthUser(id: 'plan-guide-user', email: 'plan@example.test');
    final container = ProviderContainer(
      overrides: [
        ...authenticatedSampleOverrides(prefs: prefs),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(currentUser: user),
        ),
      ],
    );
    addTearDown(container.dispose);
    final guide = container.read(discoveryControllerProvider(user.id).notifier);
    await guide.startWorkflowTour();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/recurring');
    await tester.pumpAndSettle();
    final before = container.read(ledgerProvider);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .last
          .matchedLocation,
      '/recurring/new',
    );
    expect(find.text('Set the loan terms'), findsNothing);
    expect(find.text('Build a real plan'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave draft'));
    await tester.pumpAndSettle();
    expect(find.text('Track what you owe'), findsOneWidget);
    expect(container.read(ledgerProvider), same(before));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('calendar guide follows the real day into its sheet', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    const user = AuthUser(
      id: 'calendar-guide-user',
      email: 'calendar@example.test',
    );
    final container = ProviderContainer(
      overrides: [
        ...authenticatedSampleOverrides(prefs: prefs),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(currentUser: user),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(discoveryControllerProvider(user.id).notifier)
        .replayHint('calendar-days');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/?tab=2');
    await tester.pumpAndSettle();
    final date = find.byWidgetPredicate(
      (widget) => widget is DiscoveryGuideAnchor && widget.id == 'calendar-day',
    );
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    expect(find.text('End-of-day balance'), findsOneWidget);
    expect(find.text('A day in detail'), findsOneWidget);
    await tester.tap(find.text('Finish guide'));
    await tester.pumpAndSettle();
    expect(find.text('End-of-day balance'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an existing wallet gets no unsolicited hints on feature screens',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const user = AuthUser(
        id: 'existing-user',
        email: 'existing@example.test',
      );
      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(prefs: prefs),
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
          child: const OneWalletApp(),
        ),
      );
      await tester.pumpAndSettle();
      for (final route in ['/review', '/recurring', '/settings']) {
        container.read(appRouterProvider).go(route);
        await tester.pumpAndSettle();
        expect(find.byType(DiscoveryCoachMark), findsNothing);
        expect(find.text('SAMPLE · NOT SAVED'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('progress survives interruption and is isolated by owner', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = DiscoveryController(prefs, 'first');
    final second = DiscoveryController(prefs, 'second');
    await first.prepareWelcome();
    await first.start();
    await first.advance();
    await first.advance(skipped: true);

    final restored = DiscoveryController(prefs, 'first');
    expect(restored.state.status, DiscoveryStatus.paused);
    expect(restored.state.step, 2);
    expect(restored.state.completed, {0});
    expect(restored.state.skipped, {1});
    expect(restored.state.completedChapters, {'Home'});
    expect(second.state.status, DiscoveryStatus.dormant);

    await restored.replay();
    expect(restored.state.step, 0);
    expect(restored.state.completed, isEmpty);
    expect(restored.state.skipped, isEmpty);
    expect(
      DiscoveryController(prefs, 'second').state.status,
      DiscoveryStatus.dormant,
    );
    await restored.replay(startStep: 3, endStep: 3);
    expect(restored.state.step, 3);
    await restored.advance();
    expect(restored.state.status, DiscoveryStatus.completion);
    expect(restored.state.step, 3);
    first.dispose();
    second.dispose();
    restored.dispose();
  });

  test('clearing one owner removes only that owner’s guide progress', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = DiscoveryController(prefs, 'first');
    final second = DiscoveryController(prefs, 'second');
    await first.prepareWelcome();
    await second.prepareWelcome();
    await first.clearLocal();
    final restoredFirst = DiscoveryController(prefs, 'first');
    final restoredSecond = DiscoveryController(prefs, 'second');
    expect(restoredFirst.state.status, DiscoveryStatus.dormant);
    expect(restoredSecond.state.status, DiscoveryStatus.paused);
    first.dispose();
    second.dispose();
    restoredFirst.dispose();
    restoredSecond.dispose();
  });

  test('feature replay preserves other steps and dismissed hints', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = DiscoveryController(prefs, 'first');
    await controller.replay();
    await controller.advance();
    await controller.advance(skipped: true);
    await controller.dismissHint('settings');
    await controller.replay(startStep: 3, endStep: 3);
    expect(controller.state.completed, {0});
    expect(controller.state.skipped, {1});
    expect(controller.state.introduced, {'settings'});
    final restored = DiscoveryController(prefs, 'first');
    final other = DiscoveryController(prefs, 'second');
    expect(restored.state.introduced, {'settings'});
    expect(other.state.introduced, isEmpty);
    controller.dispose();
    restored.dispose();
    other.dispose();
  });

  test('replaying a feature hint preserves a paused introduction', () async {
    final prefs = await SharedPreferences.getInstance();
    final guide = DiscoveryController(prefs, 'first');
    await guide.prepareWelcome();
    await guide.start();
    await guide.advance();
    await guide.pause();
    await guide.dismissHint('review-inbox');
    await guide.replayHint('review-inbox');
    final restored = DiscoveryController(prefs, 'first');
    expect(restored.state.requestedHint, 'review-inbox');
    expect(restored.state.status, DiscoveryStatus.paused);
    expect(restored.state.step, 1);
    await restored.dismissHint('review-inbox');
    expect(restored.state.requestedHint, isNull);
    expect(restored.state.completed, {0});
    guide.dispose();
    restored.dispose();
  });

  test(
    'feature replay restores an interrupted introduction after restart',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = DiscoveryController(prefs, 'first');
      await controller.prepareWelcome();
      await controller.start();
      await controller.advance();
      await controller.advance(skipped: true);
      await controller.replay(startStep: 3, endStep: 3);
      controller.dispose();

      final restored = DiscoveryController(prefs, 'first');
      expect(restored.state.status, DiscoveryStatus.paused);
      await restored.start();
      await restored.advance();
      await restored.finish();
      expect(restored.state.status, DiscoveryStatus.paused);
      expect(restored.state.step, 2);
      expect(restored.state.completed, {0});
      expect(restored.state.skipped, {1});
      restored.dispose();
    },
  );

  test(
    'cloud completion restores on a new device without a wallet write',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = _FakeCompletionStore()..finished = true;
      final controller = DiscoveryController(
        prefs,
        'cloud-user',
        completionStore: store,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, DiscoveryStatus.finished);
      expect(controller.state.introFinished, isTrue);
      expect(controller.state.isRestoring, isFalse);
      expect(store.writes, 0);
      controller.dispose();
    },
  );

  test('cloud restores an interrupted tour and dismissed hints', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FakeCompletionStore()
      ..progress = const DiscoveryCloudProgress(
        welcomeSeen: true,
        started: true,
        step: 2,
        completed: {0},
        skipped: {1},
        introduced: {'settings'},
      );
    final controller = DiscoveryController(
      prefs,
      'cloud-user',
      completionStore: store,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, DiscoveryStatus.paused);
    expect(controller.state.step, 2);
    expect(controller.state.completed, {0});
    expect(controller.state.skipped, {1});
    expect(controller.state.introduced, {'settings'});
    controller.dispose();
  });

  test(
    'cloud progress merge preserves completion and resolves skipped steps',
    () {
      const first = DiscoveryCloudProgress(
        started: true,
        step: 3,
        skipped: {1},
        introduced: {'settings'},
      );
      const second = DiscoveryCloudProgress(
        finished: true,
        step: 2,
        completed: {1},
        introduced: {'statement-import'},
      );
      final merged = first.merge(second);
      expect(merged.finished, isTrue);
      expect(merged.step, 3);
      expect(merged.completed, {1});
      expect(merged.skipped, isEmpty);
      expect(merged.introduced, {'settings', 'statement-import'});
    },
  );

  test(
    'completion during an in-flight cloud read is eventually saved',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = _FakeCompletionStore()..pendingRead = Completer<bool>();
      final controller = DiscoveryController(
        prefs,
        'cloud-user',
        completionStore: store,
      );
      await controller.finish();
      store.pendingRead!.complete(false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1);
      expect(controller.state.status, DiscoveryStatus.finished);
      controller.dispose();
    },
  );

  test('changes during a cloud write are merged on retry', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FakeCompletionStore();
    final controller = DiscoveryController(
      prefs,
      'cloud-user',
      completionStore: store,
    );
    await Future<void>.delayed(Duration.zero);
    store.pendingWrite = Completer<void>();
    await controller.prepareWelcome();
    await controller.start();
    await controller.advance();
    await controller.advance(skipped: true);
    await controller.dismissHint('settings');
    store.pendingWrite!.complete();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(store.progress?.step, 2);
    expect(store.progress?.completed, {0});
    expect(store.progress?.skipped, {1});
    expect(store.progress?.introduced, {'settings'});
    controller.dispose();
  });

  test('cloud failure keeps local progress and retries completion', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FakeCompletionStore()..failRead = true;
    final controller = DiscoveryController(
      prefs,
      'cloud-user',
      completionStore: store,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.syncError, isNotNull);
    await controller.finish();
    await Future<void>.delayed(Duration.zero);
    expect(store.finished, isTrue);
    expect(controller.state.syncError, isNull);
    final restored = DiscoveryController(prefs, 'cloud-user');
    expect(restored.state.status, DiscoveryStatus.finished);
    restored.dispose();
    controller.dispose();
  });

  test('an interrupted cloud write retries the locally saved steps', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FakeCompletionStore();
    final controller = DiscoveryController(
      prefs,
      'cloud-user',
      completionStore: store,
    );
    await Future<void>.delayed(Duration.zero);
    store.failWrite = true;
    await controller.prepareWelcome();
    await controller.start();
    await controller.advance();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.syncError, isNotNull);
    expect(controller.state.step, 1);
    store.failWrite = false;
    await controller.refreshCloudCompletion();
    expect(controller.state.syncError, isNull);
    expect(store.progress?.step, 1);
    expect(store.progress?.completed, {0});
    controller.dispose();
  });

  testWidgets('spotlight follows a real target and leaves it tappable', (
    tester,
  ) async {
    final navigation = GlobalKey();
    final action = GlobalKey();
    final profile = GlobalKey();
    var taps = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  key: action,
                  width: 64,
                  height: 64,
                  child: FilledButton(
                    onPressed: () => taps++,
                    child: const Text('+'),
                  ),
                ),
              ),
              DiscoveryOverlay(
                progress: const DiscoveryProgress(
                  status: DiscoveryStatus.active,
                  step: 1,
                ),
                dashboardTarget: GlobalKey(),
                navigationTarget: navigation,
                actionTarget: action,
                profileTarget: profile,
                selectedTab: 0,
                hasAccounts: true,
                onSelectTab: (_) {},
                onStart: () {},
                onPause: () {},
                onFinish: () {},
                onPrevious: () {},
                onNext: () {},
                onSkipStep: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Make your first record'), findsOneWidget);
    final targetRect = tester.getRect(find.byKey(action));
    final tooltipRect = tester.getRect(find.text('Make your first record'));
    expect(targetRect.overlaps(tooltipRect), isFalse);
    await tester.tap(find.byKey(action));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'tour controls remain reachable at large text on a short screen',
    (tester) async {
      final navigation = GlobalKey();
      final action = GlobalKey();
      final profile = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(key: navigation, width: 300, height: 80),
                ),
                DiscoveryOverlay(
                  progress: const DiscoveryProgress(
                    status: DiscoveryStatus.active,
                  ),
                  dashboardTarget: navigation,
                  navigationTarget: navigation,
                  actionTarget: action,
                  profileTarget: profile,
                  selectedTab: 0,
                  hasAccounts: true,
                  onSelectTab: (_) {},
                  onStart: () {},
                  onPause: () {},
                  onFinish: () {},
                  onPrevious: () {},
                  onNext: () {},
                  onSkipStep: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Close guide'));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Close guide'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('spotlight panel stays clear of its target across layouts', (
    tester,
  ) async {
    for (final (size, scale, brightness) in [
      (const Size(360, 640), 1.0, Brightness.light),
      (const Size(640, 360), 2.0, Brightness.dark),
      (const Size(1024, 768), 1.3, Brightness.light),
    ]) {
      await tester.binding.setSurfaceSize(size);
      final target = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(key: target, width: 200, height: 80),
                ),
                DiscoveryOverlay(
                  progress: const DiscoveryProgress(
                    status: DiscoveryStatus.active,
                  ),
                  dashboardTarget: target,
                  navigationTarget: GlobalKey(),
                  actionTarget: GlobalKey(),
                  profileTarget: GlobalKey(),
                  selectedTab: 0,
                  hasAccounts: true,
                  onSelectTab: (_) {},
                  onStart: () {},
                  onPause: () {},
                  onFinish: () {},
                  onPrevious: () {},
                  onNext: () {},
                  onSkipStep: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final panel = find
          .ancestor(
            of: find.text('Your money, at a glance'),
            matching: find.byType(Material),
          )
          .first;
      expect(
        tester.getRect(panel).overlaps(tester.getRect(find.byKey(target))),
        isFalse,
      );
      await tester.ensureVisible(find.byTooltip('Close guide'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('spotlight follows a moving target and survives its removal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final target = GlobalKey();
    var alignment = Alignment.bottomCenter;
    var showTarget = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  if (showTarget)
                    Align(
                      alignment: alignment,
                      child: SizedBox(key: target, width: 200, height: 80),
                    ),
                  DiscoveryOverlay(
                    progress: const DiscoveryProgress(
                      status: DiscoveryStatus.active,
                    ),
                    dashboardTarget: target,
                    navigationTarget: GlobalKey(),
                    actionTarget: GlobalKey(),
                    profileTarget: GlobalKey(),
                    selectedTab: 0,
                    hasAccounts: true,
                    onSelectTab: (_) {},
                    onStart: () {},
                    onPause: () {},
                    onFinish: () {},
                    onPrevious: () {},
                    onNext: () {},
                    onSkipStep: () {},
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    update(() => alignment = Alignment.topCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    final panel = find
        .ancestor(
          of: find.text('Your money, at a glance'),
          matching: find.byType(Material),
        )
        .first;
    expect(
      tester.getRect(panel).overlaps(tester.getRect(find.byKey(target))),
      isFalse,
    );
    update(() => showTarget = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.byTooltip('Close guide'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real record navigation resumes without another popup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await SharedPreferences.getInstance();
    const user = AuthUser(id: 'tour-user', email: 'tour@example.test');
    final container = ProviderContainer(
      overrides: [
        ...authenticatedSampleOverrides(prefs: prefs),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(currentUser: user),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(discoveryControllerProvider(user.id).notifier)
        .prepareWelcome();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your wallet is ready'), findsOneWidget);
    await tester.tap(find.text('Show me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Make your first record'), findsOneWidget);
    await tester.tap(find.byType(IslandFloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(AddRecordScreen), findsOneWidget);
    expect(find.text('Try a real record'), findsOneWidget);
    await tester.tap(find.text('Try it yourself'));
    await tester.pumpAndSettle();
    expect(container.read(discoveryControllerProvider(user.id)).step, 2);
    expect(
      container.read(discoveryControllerProvider(user.id)).status,
      DiscoveryStatus.paused,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Continue your tour?'), findsNothing);
    expect(find.text('Find any record'), findsOneWidget);
    for (final (tab, nextTitle) in [
      ('History', 'Pick a day'),
      ('Calendar', 'Your accounts'),
      ('Accounts', 'Make it yours'),
    ]) {
      await tester.tap(find.text('Show $tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text(nextTitle), findsWidgets);
    }
    await tester.tap(find.text('Show Home'));
    await tester.pumpAndSettle();
    expect(container.read(discoveryControllerProvider(user.id)).step, 5);
    expect(
      container.read(discoveryControllerProvider(user.id)).status,
      DiscoveryStatus.active,
    );
    await tester.ensureVisible(find.text('Finish basics'));
    await tester.tap(find.text('Finish basics'));
    await tester.pumpAndSettle();
    expect(find.text('The essentials, covered'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      container.read(discoveryControllerProvider(user.id)).status,
      DiscoveryStatus.finished,
    );
    await container
        .read(discoveryControllerProvider(user.id).notifier)
        .replay(startStep: 1, endStep: 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IslandFloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Try a real record'), findsOneWidget);
    await tester.tap(find.text('Try it yourself'));
    await tester.pumpAndSettle();
    expect(find.text('Try a real record'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'new offline wallet completes account setup before offering a small tour',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        AppModeStore.storageKey: 'offline',
      });
      final prefs = await SharedPreferences.getInstance();
      LedgerProvidersConfig.disableAutoBackup = true;
      addTearDown(() => LedgerProvidersConfig.disableAutoBackup = false);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          ledgerRepositoryProvider.overrideWithValue(MemoryLedgerRepository()),
        ],
      );
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OneWalletApp(),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(OnboardingScreen).evaluate().isNotEmpty) break;
      }
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Your wallet is ready'), findsNothing);
      expect(container.read(ledgerProvider).accounts, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue').first);
      await tester.pumpAndSettle();
      final fields = find.byType(AppGlassTextField);
      await tester.enterText(fields.at(0), 'My wallet');
      await tester.enterText(fields.at(1), '100');
      await tester.ensureVisible(find.text('Save account'));
      await tester.tap(find.text('Save account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Looks good'));
      await tester.tap(find.text('Looks good'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Finish Setup'));
      await tester.tap(find.text('Finish Setup'));
      await tester.pumpAndSettle();
      expect(container.read(ledgerProvider).accounts.single.name, 'My wallet');
      expect(find.text('Your wallet is ready'), findsOneWidget);
      expect(container.read(ledgerProvider).transactions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings confirms and restarts the tour without changing wallet',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await SharedPreferences.getInstance();
      const user = AuthUser(id: 'replay-user', email: 'replay@example.test');
      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(prefs: prefs),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(currentUser: user),
          ),
        ],
      );
      addTearDown(container.dispose);
      final guide = container.read(
        discoveryControllerProvider(user.id).notifier,
      );
      await guide.prepareWelcome();
      await guide.start();
      await guide.advance();
      await guide.finish();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OneWalletApp(),
        ),
      );
      await tester.pumpAndSettle();
      final accountsBefore = container
          .read(ledgerProvider)
          .accounts
          .map((account) => account.id)
          .toList();
      final recordsBefore = container
          .read(ledgerProvider)
          .transactions
          .map((record) => record.id)
          .toList();
      final router = container.read(appRouterProvider);
      router.push('/settings');
      await tester.pumpAndSettle();
      expect(find.text('Make 1Wallet yours'), findsNothing);
      await guide.dismissHint('review-inbox');
      final guides = find.text('Feature guides');
      await tester.ensureVisible(guides);
      await tester.pumpAndSettle();
      await tester.tap(guides);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Review, account matching & alerts'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review, account matching & alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Message to account'), findsOneWidget);
      await tester.tap(find.byTooltip('Close guide'));
      await tester.pumpAndSettle();
      expect(find.text('Message to account'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.ensureVisible(guides);
      await tester.pumpAndSettle();
      await tester.tap(guides);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calendar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryControllerProvider(user.id)).step, 3);
      await tester.tap(find.text('Show Calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish basics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        container.read(discoveryControllerProvider(user.id)).introFinished,
        isTrue,
      );
      router.push('/settings');
      await tester.pumpAndSettle();
      expect(find.text('Make 1Wallet yours'), findsNothing);
      final replay = find.text('Replay the tour');
      await tester.ensureVisible(replay);
      await tester.pumpAndSettle();
      await tester.tap(replay);
      await tester.pumpAndSettle();
      expect(find.text('Restart the tour?'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryControllerProvider(user.id)).step, 0);
      expect(
        container.read(discoveryControllerProvider(user.id)).status,
        DiscoveryStatus.active,
      );
      expect(find.text('Your money, at a glance'), findsOneWidget);
      expect(
        container.read(ledgerProvider).accounts.map((a) => a.id),
        accountsBefore,
      );
      expect(
        container.read(ledgerProvider).transactions.map((r) => r.id),
        recordsBefore,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('tour welcome is non-optional and does not offer a dismiss action', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    const user = AuthUser(id: 'non-optional-user', email: 'mandatory@test.com');
    final container = ProviderContainer(
      overrides: [
        ...authenticatedSampleOverrides(prefs: prefs),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(currentUser: user),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(discoveryControllerProvider(user.id).notifier)
        .prepareWelcome();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your wallet is ready'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Interactive 1Wallet Story'), findsOneWidget);
    await tester.tap(find.text('Show me'));
    await tester.pumpAndSettle();
    expect(
      container.read(discoveryControllerProvider(user.id)).status,
      DiscoveryStatus.active,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'tour displays compact sample cards and interactive calendar forecast',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const user = AuthUser(id: 'samples-user', email: 'samples@test.com');
      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(prefs: prefs),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(currentUser: user),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(discoveryControllerProvider(user.id).notifier)
          .prepareWelcome();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OneWalletApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();

      // Step 0: Consolidated Wealth sample
      expect(find.text('Consolidated Wealth'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 1: Offline-First Logging sample
      expect(find.text('Offline-First Logging'), findsOneWidget);
      await tester.tap(find.text('Try later'));
      await tester.pumpAndSettle();

      // Step 2: Instant Search & Filters sample
      expect(find.text('Instant Search & Filters'), findsOneWidget);
      await tester.tap(find.text('Show History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 3: Calendar Net & Forecast sample
      expect(find.text('Projected Net & Forecast'), findsOneWidget);
      await tester.tap(find.text('Show Calendar'));
      await tester.pumpAndSettle();

      final nextMonthBtn = find.byKey(
        const ValueKey('discovery-tour-next-month'),
      );
      expect(nextMonthBtn, findsOneWidget);

      final initialMonth = container.read(calendarVisibleMonthProvider);
      await tester.ensureVisible(nextMonthBtn);
      await tester.tap(nextMonthBtn);
      await tester.pumpAndSettle();
      final nextMonth = container.read(calendarVisibleMonthProvider);
      expect(nextMonth, isNotNull);
      if (initialMonth != null) {
        expect(nextMonth!.isAfter(initialMonth), isTrue);
      }

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 4: Suffix Alert Matching sample
      expect(find.text('Suffix Alert Matching'), findsOneWidget);
      await tester.tap(find.text('Show Accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 5: Vault & Privacy sample
      expect(find.text('Vault & Privacy'), findsOneWidget);
      await tester.tap(find.text('Show Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish basics'));
      await tester.pumpAndSettle();

      expect(find.text('The essentials, covered'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        container.read(discoveryControllerProvider(user.id)).status,
        DiscoveryStatus.finished,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _FakeCompletionStore implements DiscoveryCompletionStore {
  bool finished = false;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  Completer<bool>? pendingRead;
  Completer<void>? pendingWrite;
  DiscoveryCloudProgress? progress;

  @override
  Future<DiscoveryCloudProgress?> readProgress() async {
    if (failRead) throw StateError('Cloud unavailable');
    final done = pendingRead == null ? finished : await pendingRead!.future;
    return progress ??
        (done ? const DiscoveryCloudProgress(finished: true) : null);
  }

  @override
  Future<DiscoveryCloudProgress> mergeProgress(
    DiscoveryCloudProgress next,
  ) async {
    if (failWrite) throw StateError('Cloud unavailable');
    if (pendingWrite != null) await pendingWrite!.future;
    writes++;
    progress = progress?.merge(next) ?? next;
    finished = progress!.finished;
    return progress!;
  }
}
