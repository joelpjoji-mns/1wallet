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
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/login/login_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_widgets.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';
import 'test_harness.dart';

/// Pumps representative routes across the supported presentation matrix
/// (light/dark AMOLED, normal/large text, narrow phone/tablet) and fails on
/// layout overflow, wrapped/clipped button labels, or framework exceptions
/// other than the known test-harness `semantics.parentDataDirty` error.
///
/// When run with `--dart-define=UI_AUDIT_SHOTS=<dir>` it also writes a PNG per
/// screen/variant into `<dir>` so the UI audit (`doc/ui-audit.md`) can show
/// before/after pairs. Without the define no files are written.
const _shotsDir = String.fromEnvironment('UI_AUDIT_SHOTS');
const _shotsFilter = String.fromEnvironment('UI_AUDIT_SHOTS_FILTER');

const _nativeCaptureChannel = MethodChannel('com.joelpjoji.one.wallet/sms');

class _CloudWalletSyncController extends StateNotifier<CloudSyncState>
    implements CloudSyncController {
  _CloudWalletSyncController()
    : super(const CloudSyncState(hasCloudWallet: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _homeRoutes = <String>[
  '/',
  '#tab1',
  '#tab2',
  '#tab3',
  '/accounts',
  '/add',
  '/add?tab=1',
  '/add?type=transfer&accountId=acc-bank&counterAccountId=acc-card',
  '/add?plannedId=tx-rent-planned',
  '/add?transactionId=tx-salary',
  '/transaction/tx-salary',
  '/account/new',
  '/account/acc-bank',
  '/account/acc-bank/secure',
  '/widgets',
  '/review',
  '/capture/cap-1',
  '/settings',
  '/settings/glass',
  '/settings/theme',
  '/settings/feedback',
  '/recurring',
  '/recurring/new',
  '/recurring/past',
  '/recurring/tx-rent-planned',
  '/recurring/tx-rent-planned/edit',
  '/cards',
  '/loans',
  '/loans/new',
  '/loans/past',
  '/loans/forecast',
  '/loans/acc-loan',
  '/loans/acc-loan/edit',
  '/categories',
  '/currencies',
  '/sync',
  '/import-statement',
  '/imports/batch-1',
  '/imports/missing-batch',
  '/data-backup',
  '/auto-capture',
  '/auto-capture/debug',
  '/capture-diagnostics',
  '/import-sms',
  '/notification-capture',
  '/notification-capture/apps',
  '/device-permissions',
  '/not-a-real-route',
];

/// Empty states (dashboard tiles, lists, pickers) on a brand-new wallet.
const _emptyLedgerRoutes = <String>[
  '/',
  '#tab1',
  '#tab2',
  '#tab3',
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

LedgerState _populatedLedger() {
  final ledger = sampleLedgerState();
  return ledger.copyWith(
    importBatches: [
      ImportBatch(
        id: 'batch-1',
        source: 'csv',
        status: 'completed',
        createdAt: DateTime(2026, 1, 5),
        rowCount: 1,
        importedCount: 1,
        duplicateCount: 0,
      ),
    ],
    transactions: [
      for (final transaction in ledger.transactions)
        transaction.id == 'tx-grocery'
            ? transaction.copyWith(importBatchId: 'batch-1')
            : transaction,
    ],
  );
}

/// Routes that are only reachable for a specific startup destination.
const _gatedRoutes = <String, StartupDestination>{
  '/login': StartupDestination.login,
  '/onboarding': StartupDestination.onboarding,
  '/permissions-setup': StartupDestination.permissions,
  '/account-deletion': StartupDestination.deletion,
  '/launch': StartupDestination.launch,
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
  _Variant('phone-light-115', Size(360, 780), 1.15, false),
  _Variant('phone-light-large', Size(360, 780), 1.3, false),
  _Variant('phone-dark-large', Size(360, 780), 1.3, true),
  _Variant('phone-light-150', Size(360, 780), 1.5, false),
  _Variant('phone-light-200', Size(360, 780), 2.0, false),
  _Variant('phone-dark-200', Size(360, 780), 2.0, true),
  _Variant('compact-phone-light', Size(320, 568), 1.0, false),
  _Variant('compact-phone-200', Size(320, 568), 2.0, false),
  _Variant('landscape-phone-light', Size(780, 360), 1.0, false),
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
  bool hasCloudWallet = false,
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
        ? authenticatedSampleOverrides(
            prefs: prefs,
            ledger: ledger ?? _populatedLedger(),
          )
        : [
            startupStateProvider.overrideWithValue(
              StartupState.ready(destination: destination),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            ledgerRepositoryProvider.overrideWithValue(
              StaticLedgerRepository(sampleLedgerState()),
            ),
            if (hasCloudWallet)
              cloudSyncControllerProvider.overrideWith(
                (ref) => _CloudWalletSyncController(),
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
    _auditButtonLabels(tester, '$route @ ${variant.name}');
    await _auditScrolledButtons(tester, '$route @ ${variant.name}');
    await _settle(tester);
    _drainErrors('$route while scrolling @ ${variant.name}');
    await _capture(
      tester,
      boundaryKey,
      '${ledger == null ? '' : 'empty-'}${_slug(route)}',
      variant.name,
    );
  }
}

final _collected = <String>[];

Future<void> _auditScrolledButtons(WidgetTester tester, String where) async {
  final visited = <ScrollableState>{};

  Future<void> audit(ScrollableState state) async {
    if (!visited.add(state)) return;
    if (!state.mounted ||
        axisDirectionToAxis(state.axisDirection) != Axis.vertical) {
      return;
    }
    final position = state.position;
    if (!position.hasContentDimensions ||
        !position.maxScrollExtent.isFinite ||
        position.viewportDimension <= 0 ||
        position.maxScrollExtent <= position.minScrollExtent) {
      return;
    }
    final initial = position.pixels;
    var offset = position.minScrollExtent;
    final step = position.viewportDimension * 0.8;
    var reachedEnd = false;
    for (var stops = 0; stops < 100 && state.mounted; stops++) {
      if (!identical(state.position, position)) break;
      position.jumpTo(offset);
      await tester.pump(const Duration(milliseconds: 16));
      _auditButtonLabels(tester, where);
      for (final element in find.byType(Scrollable).evaluate().toList()) {
        if (!element.mounted) continue;
        final child = (element as StatefulElement).state as ScrollableState;
        if (!visited.contains(child)) await audit(child);
      }
      if (!state.mounted || !identical(state.position, position)) break;
      if (offset >= position.maxScrollExtent) {
        reachedEnd = true;
        break;
      }
      offset = (offset + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
    }
    if (state.mounted && identical(state.position, position)) {
      if (!reachedEnd) _collected.add('$where: scroll audit did not reach end');
      position.jumpTo(
        initial.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  for (final element in find.byType(Scrollable).evaluate().toList()) {
    if (!element.mounted) continue;
    await audit((element as StatefulElement).state as ScrollableState);
  }
}

Future<void> _auditOverlay(WidgetTester tester, String where) async {
  await _settle(tester);
  _drainErrors(where);
  _auditButtonLabels(tester, where);
  await _auditScrolledButtons(tester, where);
  await _settle(tester);
  _drainErrors('$where while scrolling');
}

void _auditButtonLabels(WidgetTester tester, String where) {
  final buttons = find.byWidgetPredicate(
    (widget) =>
        widget is ButtonStyleButton ||
        widget is AppActionButton ||
        widget is HeaderSaveAction ||
        widget is AddRecordCalcKey,
  );
  for (final button in buttons.evaluate()) {
    void visit(Element element) {
      if (element.widget is Text) {
        final paragraph = element.findRenderObject();
        if (paragraph is RenderParagraph && paragraph.hasSize) {
          final label = paragraph.text.toPlainText().trim();
          if (label.isNotEmpty) {
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              textAlign: paragraph.textAlign,
              locale: paragraph.locale,
              strutStyle: paragraph.strutStyle,
              textWidthBasis: paragraph.textWidthBasis,
              textHeightBehavior: paragraph.textHeightBehavior,
            )..layout(maxWidth: paragraph.size.width);
            final lines = painter.computeLineMetrics().length;
            painter.dispose();
            final intrinsicWidth = paragraph.getMaxIntrinsicWidth(
              double.infinity,
            );
            if (lines > 1 ||
                paragraph.didExceedMaxLines ||
                intrinsicWidth > paragraph.size.width + 1) {
              final issue =
                  '$where: ${button.widget.runtimeType} label "$label" '
                  'wraps or clips (lines=$lines, '
                  'width=${paragraph.size.width.toStringAsFixed(1)}, '
                  'needed=${intrinsicWidth.toStringAsFixed(1)})';
              if (!_collected.contains(issue)) _collected.add(issue);
            }
          }
        }
      }
      element.visitChildElements(visit);
    }

    button.visitChildElements(visit);
  }
}

void _drainErrors(String where) {
  final seen = <String>{};
  for (final details in _pending) {
    final text = details.exceptionAsString();
    if (text.contains('semantics.parentDataDirty')) continue;
    final summary = text.split('\n').first;
    final location = RegExp(
      r'(package:one_wallet_flutter/src/[^\s:]+\.dart:\d+)',
    ).firstMatch(details.stack?.toString() ?? '')?.group(1);
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
    final errors = List<String>.of(_collected);
    expect(errors, isEmpty, reason: errors.join('\n'));
  } finally {
    FlutterError.onError = previous;
    _pending.clear();
    _collected.clear();
  }
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

  for (final variant in [
    _variants.firstWhere((variant) => variant.name == 'compact-phone-light'),
    _variants.firstWhere((variant) => variant.name == 'phone-light-200'),
    _variants.firstWhere((variant) => variant.name == 'compact-phone-200'),
  ]) {
    testWidgets('representative overlays render cleanly (${variant.name})', (
      tester,
    ) async {
      await _run(tester, () async {
        await _pumpVariant(tester, variant, ['/loans/acc-loan']);
        final archive = find.widgetWithText(OutlinedButton, 'Archive');
        await tester.ensureVisible(archive);
        await _settle(tester);
        await tester.tap(archive);
        await _settle(tester);
        expect(find.text('Archive loan?'), findsOneWidget);
        await _auditOverlay(tester, 'loan archive dialog @ ${variant.name}');
        await tester.tap(find.text('Cancel').last);
        await _settle(tester);

        await _pumpVariant(tester, variant, ['/categories']);
        await tester.tap(find.byTooltip('Add category'));
        await _settle(tester);
        expect(find.text('New category'), findsOneWidget);
        await _auditOverlay(tester, 'category editor @ ${variant.name}');
        await tester.showKeyboard(find.byType(TextFormField).first);
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await _auditOverlay(
          tester,
          'category editor with keyboard @ ${variant.name}',
        );
        tester.view.resetViewInsets();
        await tester.pump();
        await tester.tap(find.text('Cancel').last);
        await _settle(tester);

        await _pumpVariant(tester, variant, [
          '/login',
        ], destination: StartupDestination.login);
        final offline = find.byKey(LoginScreen.offlineButtonKey);
        await tester.scrollUntilVisible(
          offline,
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(offline);
        await _settle(tester);
        expect(find.text('Use 1Wallet offline'), findsOneWidget);
        await _auditOverlay(tester, 'offline consent sheet @ ${variant.name}');
      });
    });
  }

  for (final variant in [
    _variants.firstWhere((variant) => variant.name == 'compact-phone-light'),
    _variants.firstWhere((variant) => variant.name == 'phone-light-200'),
    _variants.firstWhere((variant) => variant.name == 'compact-phone-200'),
  ]) {
    testWidgets('onboarding steps render cleanly (${variant.name})', (
      tester,
    ) async {
      await _run(tester, () async {
        await _pumpVariant(tester, variant, [
          '/onboarding',
        ], destination: StartupDestination.onboarding);

        Future<void> tapAtBottom(String label) async {
          final vertical = find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          );
          final state = tester.state<ScrollableState>(vertical.first);
          state.position.jumpTo(state.position.maxScrollExtent);
          await _settle(tester);
          await tester.tap(find.text(label).first);
          await _settle(tester);
        }

        await tapAtBottom('Continue');
        expect(find.text('Step 2 of 4'), findsOneWidget);
        await _auditOverlay(tester, 'onboarding account @ ${variant.name}');

        await tapAtBottom('Skip for now');
        expect(find.text('Step 3 of 4'), findsOneWidget);
        await _auditOverlay(tester, 'onboarding review @ ${variant.name}');

        await tapAtBottom('Looks good');
        expect(find.text('Step 4 of 4'), findsOneWidget);
        await _auditOverlay(tester, 'onboarding permissions @ ${variant.name}');
      });
    });
  }

  for (final variant in [
    _variants.firstWhere((variant) => variant.name == 'compact-phone-light'),
    _variants.firstWhere((variant) => variant.name == 'compact-phone-200'),
  ]) {
    testWidgets('cloud wallet recovery renders cleanly (${variant.name})', (
      tester,
    ) async {
      await _run(
        tester,
        () => _pumpVariant(
          tester,
          variant,
          ['/onboarding'],
          destination: StartupDestination.onboarding,
          hasCloudWallet: true,
        ),
      );
      expect(find.text('Cloud Wallet Found'), findsOneWidget);
    });
  }
}
