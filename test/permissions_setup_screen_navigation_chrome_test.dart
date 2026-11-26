// Focused tests for `PermissionsSetupScreen`'s navigation chrome
// (lib/src/features/settings/permissions_setup_screen.dart), covering the
// Material AppBar -> GlassAppBar conversion.
//
// This screen never had an explicit `leading:` before the conversion, so it
// relied entirely on Material's AppBar auto-injecting a back button when
// `Navigator.canPop(context)`. GlassAppBar has no such auto-detection, so
// the conversion had to replicate that explicitly
// (`Navigator.of(context).canPop() ? const AppBackAction() : null`) - this
// test guards that replication for both the root-route (no back button) and
// pushed-route (back button that pops) cases, mirroring the same regression
// already found and fixed in RouteScaffold's desktop path.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/permission_setup_controller.dart';
import 'package:one_wallet_flutter/src/features/settings/permissions_setup_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'offline_mode_fakes.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  testWidgets('setup heading does not break words at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const PermissionsSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Almost\nthere.'),
    );
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    expect(painter.computeLineMetrics(), hasLength(2));
    painter.dispose();
    expect(tester.takeException(), isNull);
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('as a root route it shows no back button', (tester) async {
    await pump(tester, const PermissionsSetupScreen());

    expect(find.text('Setup'), findsOneWidget);
    expect(find.byType(AppBackAction), findsNothing);
  });

  testWidgets('when pushed it shows a back button that pops', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const PermissionsSetupScreen(),
                ),
              ),
              child: const Text('Push setup'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Push setup'));
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsOneWidget);

    final backButton = find.byType(AppBackAction);
    expect(backButton, findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsNothing);
    expect(find.text('Push setup'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('permissions can be skipped without a system request', (
    tester,
  ) async {
    final (container, calls) = await _pumpSetupFlow(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(container.read(permissionSetupControllerProvider).completed, isTrue);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('one_wallet_flutter.permissions_setup.completed.local-user'),
      isTrue,
    );
    expect(find.text('Onboarding continues'), findsOneWidget);
    expect(
      find.text('You can manage permissions later in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets('denied permissions are not reported as granted', (tester) async {
    final (container, calls) = await _pumpSetupFlow(tester);
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), contains('requestPermissions'));
    expect(container.read(permissionSetupControllerProvider).completed, isTrue);
    expect(
      find.text(
        'Some permissions were not granted. Change them later in Settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Permissions are ready.'), findsNothing);
  });

  testWidgets('a failed permission request can be skipped', (tester) async {
    final (container, calls) = await _pumpSetupFlow(tester, failRequest: true);
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), contains('requestPermissions'));
    expect(
      container.read(permissionSetupControllerProvider).completed,
      isFalse,
    );
    expect(
      find.text('Could not request permissions. Try again or choose Not now.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(container.read(permissionSetupControllerProvider).completed, isTrue);
    expect(find.text('Onboarding continues'), findsOneWidget);
  });

  testWidgets('permission errors leave both actions reachable at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final (container, _) = await _pumpSetupFlow(tester, failRequest: true);
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(container.read(permissionSetupControllerProvider).completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  test(
    'a failed completion write does not complete permission setup',
    () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FailingPreferencesStore();
      final prefs = await SharedPreferences.getInstance();
      final controller = PermissionSetupController(
        prefs: prefs,
        initialUserId: 'local-user',
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.setCompleted('local-user', true),
        throwsStateError,
      );
      expect(controller.state.completed, isFalse);
    },
  );
}

class _FailingPreferencesStore extends InMemorySharedPreferencesStore {
  _FailingPreferencesStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

Future<(ProviderContainer, List<MethodCall>)> _pumpSetupFlow(
  WidgetTester tester, {
  bool failRequest = false,
}) async {
  SharedPreferences.setMockInitialValues({AppModeStore.storageKey: 'offline'});
  final prefs = await SharedPreferences.getInstance();
  final calls = <MethodCall>[];
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    if (failRequest) throw PlatformException(code: 'permission-unavailable');
    final arguments = call.arguments;
    if (call.method != 'requestPermissions' || arguments is! List) {
      throw StateError('Unexpected permission call: ${call.method}');
    }
    return {for (final id in arguments.whereType<int>()) id: 0};
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ledgerRepositoryProvider.overrideWithValue(MemoryLedgerRepository()),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/permissions-setup',
    routes: [
      GoRoute(
        path: '/permissions-setup',
        builder: (_, _) => const PermissionsSetupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Onboarding continues')),
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
  await tester.pumpAndSettle();
  expect(container.read(authControllerProvider).ownerId, 'local-user');
  return (container, calls);
}
