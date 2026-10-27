import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';
import 'test_harness.dart';

/// Pumps every reachable route across the supported presentation matrix
/// (light/dark AMOLED, normal/large text, narrow phone/tablet) and fails on
/// layout overflow or any other framework exception.
///
/// When run with `--dart-define=UI_AUDIT_SHOTS=<dir>` it also writes a PNG per
/// screen/variant into `<dir>` so the UI audit (`doc/ui-audit.md`) can show
/// before/after pairs. Without the define no files are written.
const _shotsDir = String.fromEnvironment('UI_AUDIT_SHOTS');
const _shotsFilter = String.fromEnvironment('UI_AUDIT_SHOTS_FILTER');

const _nativeCaptureChannel = MethodChannel('com.joelpjoji.one.wallet/sms');

const _homeRoutes = <String>[
  '/',
  '#tab1',
  '#tab2',
  '/accounts',
  '/add',
  '/add?transactionId=tx-salary',
  '/transaction/tx-salary',
  '/account/new',
  '/account/acc-bank',
  '/widgets',
  '/review',
  '/capture/cap-1',
  '/settings',
  '/recurring',
  '/recurring/new',
  '/recurring/tx-rent-planned',
  '/recurring/tx-rent-planned/edit',
  '/cards',
  '/loans',
  '/loans/new',
  '/loans/forecast',
  '/loans/acc-loan',
  '/loans/acc-loan/edit',
  '/categories',
  '/currencies',
  '/sync',
  '/import-statement',
  '/data-backup',
  '/auto-capture',
  '/auto-capture/debug',
  '/capture-settings',
  '/import-sms',
  '/notification-capture',
  '/notification-capture/apps',
  '/updates',
  '/device-permissions',
];

/// Empty states (dashboard tiles, lists, pickers) on a brand-new wallet.
const _emptyLedgerRoutes = <String>[
  '/',
  '#tab1',
  '#tab2',
  '/accounts',
  '/widgets',
  '/review',
  '/cards',
  '/loans',
  '/recurring',
  '/categories',
  '/sync',
];

const _emptyLedger = LedgerState(
  version: 14,
  userId: 'empty-test-user',
  preferences: LedgerPreferences(),
  accounts: [],
  categories: [],
  transactions: [],
  captureCandidates: [],
);

/// Routes that are only reachable for a specific startup destination.
const _gatedRoutes = <String, StartupDestination>{
  '/login': StartupDestination.login,
  '/onboarding': StartupDestination.onboarding,
  '/permissions-setup': StartupDestination.permissions,
};

@immutable
class _Variant {
  const _Variant(this.name, this.size, this.textScale, this.dark);

  final String name;
  final Size size;
  final double textScale;
  final bool dark;
}

const _variants = <_Variant>[
  _Variant('phone-light', Size(360, 780), 1.0, false),
  _Variant('phone-dark', Size(360, 780), 1.0, true),
  _Variant('phone-light-large', Size(360, 780), 1.3, false),
  _Variant('phone-dark-large', Size(360, 780), 1.3, true),
  _Variant('tablet-light', Size(1024, 1366), 1.0, false),
  _Variant('tablet-dark', Size(1024, 1366), 1.0, true),
];

Future<void> _settle(WidgetTester tester) async {
  // Glass shaders and live charts keep scheduling frames; pump a bounded
  // number of frames instead of waiting for idle.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _slug(String route) {
  if (route == '/') return 'home';
  if (route == '#tab1') return 'history';
  if (route == '#tab2') return 'calendar';
  return route
      .replaceAll(RegExp(r'^/'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+$'), '');
}

bool _shouldShoot(String slug, String variant) {
  if (_shotsDir.isEmpty) return false;
  if (_shotsFilter.isEmpty) return true;
  return _shotsFilter
      .split(',')
      .map((s) => s.trim())
      .any((f) => f == slug || f == '$slug@$variant');
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String slug,
  String variant,
) async {
  if (!_shouldShoot(slug, variant)) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory(_shotsDir)..createSync(recursive: true);
    File(
      '${dir.path}${Platform.pathSeparator}$slug@$variant.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
  }
  await inter.load();
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final file = File('assets/fonts/Roboto-$weight.ttf');
    if (file.existsSync()) {
      roboto.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await roboto.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}

Future<void> _pumpVariant(
  WidgetTester tester,
  _Variant variant,
  List<String> routes, {
  StartupDestination destination = StartupDestination.home,
  LedgerState? ledger,
}) async {
  tester.view.physicalSize = variant.size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = variant.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: destination == StartupDestination.home
        ? authenticatedSampleOverrides(prefs: prefs, ledger: ledger)
        : [
            startupStateProvider.overrideWithValue(
              StartupState.ready(destination: destination),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            ledgerRepositoryProvider.overrideWithValue(
              StaticLedgerRepository(sampleLedgerState()),
            ),
          ],
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);
  final boundaryKey = GlobalKey();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
          themeMode: variant.dark ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    ),
  );
  await _settle(tester);
  _drainErrors('initial ${variant.name}');

  for (final route in routes) {
    if (route.startsWith('#tab')) {
      router.go('/');
      await _settle(tester);
      final pageView = tester.widget<PageView>(find.byType(PageView).first);
      pageView.controller!.jumpToPage(int.parse(route.substring(4)));
    } else {
      router.go(route);
    }
    await _settle(tester);
    _drainErrors('$route @ ${variant.name}');
    await _capture(tester, boundaryKey, _slug(route), variant.name);
  }
}

final _collected = <String>[];

void _drainErrors(String where) {
  final seen = <String>{};
  for (final details in _pending) {
    final text = details.toString();
    if (text.contains('semantics.parentDataDirty')) continue;
    final summary = details.exceptionAsString().split('\n').first;
    final location = RegExp(
      r'(lib/src/[^\s:]+\.dart:\d+)',
    ).firstMatch(text)?.group(1);
    final line = '$where: $summary${location == null ? '' : ' ($location)'}';
    if (seen.add(line)) _collected.add(line);
  }
  _pending.clear();
}

final _pending = <FlutterErrorDetails>[];

Future<void> _run(WidgetTester tester, Future<void> Function() body) async {
  final previous = FlutterError.onError;
  FlutterError.onError = _pending.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  final errors = List<String>.of(_collected);
  _collected.clear();
  expect(errors, isEmpty, reason: errors.join('\n'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_IN');
    // Real fonts give realistic text metrics; the default test font renders
    // every glyph as a 1em square and massively over-reports overflow.
    await _loadFonts();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, null);
  });

  for (final variant in _variants) {
    testWidgets('home routes render cleanly (${variant.name})', (tester) async {
      await _run(tester, () => _pumpVariant(tester, variant, _homeRoutes));
    });

    testWidgets('empty-ledger routes render cleanly (${variant.name})', (
      tester,
    ) async {
      await _run(
        tester,
        () => _pumpVariant(
          tester,
          variant,
          _emptyLedgerRoutes,
          ledger: _emptyLedger,
        ),
      );
    });

    for (final entry in _gatedRoutes.entries) {
      testWidgets('${entry.key} renders cleanly (${variant.name})', (
        tester,
      ) async {
        await _run(
          tester,
          () => _pumpVariant(tester, variant, [
            entry.key,
          ], destination: entry.value),
        );
      });
    }
  }
}
