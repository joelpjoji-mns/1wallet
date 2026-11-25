import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_card.dart';
import 'package:one_wallet_flutter/src/widgets/privacy_text.dart';

import 'test_harness.dart';

/// Regression coverage for a fixed-height overflow in the "All accounts"
/// grid tile: it used to size its content box with a hard `height: 60`,
/// which clips/overflows once accessibility text scaling makes the
/// name/balance/currency rows taller than that. It now uses a `minHeight`
/// constraint so the tile can grow instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dashboard card headings wrap beside trailing controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: _ledger()),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: HomeWidgetCard(
                  title: 'Recent records',
                  subtitle: 'Select an account to filter',
                  icon: Icons.receipt_long,
                  headerTrailing: SizedBox(width: 120),
                  child: SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.text('Select an account to filter'),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Recent records'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('balance currency breakdown remains visible at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _ledger();
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: BalanceHomeWidget(state: state, onTabSelected: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amount = find.byWidgetPredicate(
      (widget) => widget is PrivacyText && widget.text.startsWith('USD '),
    );
    expect(amount, findsOneWidget);
    final label = find.descendant(of: amount, matching: find.byType(Text));
    final scroll = find
        .ancestor(of: amount, matching: find.byType(SingleChildScrollView))
        .first;
    expect(
      tester.getRect(scroll).contains(tester.getRect(label).topLeft),
      isTrue,
    );
    expect(
      tester.getRect(scroll).contains(tester.getRect(label).bottomLeft),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('account tiles keep one-line names and a uniform height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longName = 'Household Emergency Savings Account';
    final base = _ledger();
    final state = base.copyWith(
      accounts: [
        ...base.accounts,
        const Account(
          id: 'long',
          name: longName,
          type: 'bank',
          currency: 'INR',
          openingBalance: Money(amountMinor: 100, currency: 'INR'),
          showOnHome: true,
          sortOrder: 3,
        ),
        const Account(
          id: 'plain',
          name: 'Plain',
          type: 'bank',
          currency: 'INR',
          openingBalance: Money(amountMinor: 100, currency: 'INR'),
          showOnHome: true,
          sortOrder: 4,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountGridHomeWidget(state: state, onTabSelected: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final semantics = tester.ensureSemantics();
    final longNameSemanticsFinder = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == longName,
    );
    expect(longNameSemanticsFinder, findsOneWidget);
    expect(
      find.descendant(
        of: longNameSemanticsFinder,
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    final tileFinders = [
      for (final account in ['Foreign Wallet', 'Cash Purse', 'Plain'])
        find
            .ancestor(
              of: _nameSemantics(account),
              matching: find.byType(InkWell),
            )
            .first,
      find
          .ancestor(of: longNameSemanticsFinder, matching: find.byType(InkWell))
          .first,
    ];
    final tileNode = tester.getSemantics(tileFinders.last);
    final tileSemantics = tileNode.getSemanticsData();
    expect(tileSemantics.label, contains(longName));
    expect(tileSemantics.hasAction(SemanticsAction.tap), isTrue);
    final heights = {
      for (final tile in tileFinders) tester.getSize(tile).height,
    };
    expect(heights, hasLength(1), reason: 'all tiles share one height');
    tester
        .renderObject(tileFinders.last)
        .owner!
        .semanticsOwner!
        .performAction(tileNode.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(
        tester.element(tileFinders.last),
      ).read(homeSelectedAccountProvider),
      'long',
    );
    semantics.dispose();
  });

  testWidgets('long account names paint exactly two trailing dots', (
    tester,
  ) async {
    const name = 'Household Emergency Savings Account';
    const account = Account(
      id: 'long',
      name: name,
      type: 'bank',
      currency: 'INR',
      openingBalance: Money(amountMinor: 100, currency: 'INR'),
      color: Color(0xFF203040),
      showOnHome: true,
    );
    final theme = ThemeData.light();
    final state = _ledger().copyWith(accounts: [account]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: AccountGridHomeWidget(state: state, onTabSelected: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final namePaint = find.descendant(
      of: _nameSemantics(name),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(namePaint).painter!;
    final height = tester.getSize(namePaint).height;
    final style = Theme.of(tester.element(namePaint)).textTheme.labelSmall!
        .copyWith(
          color: Colors.white,
          height: 1.1,
          fontWeight: FontWeight.w900,
        );
    final measurement = TextPainter(
      text: TextSpan(text: name, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: 100);
    expect(measurement.didExceedMaxLines, isTrue);
    measurement.dispose();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (final (key, namePainter) in [
                ('actual', painter),
                ('two-dots', _ExpectedNamePainter(name, style, '..')),
                ('three-dots', _ExpectedNamePainter(name, style, '...')),
              ])
                RepaintBoundary(
                  key: ValueKey(key),
                  child: SizedBox(
                    width: 100,
                    height: height,
                    child: CustomPaint(painter: namePainter),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<List<int>> pixels(String key) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(key)),
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final pixels = data.buffer.asUint8List().toList();
        image.dispose();
        return pixels;
      }))!;
    }

    final actual = await pixels('actual');
    expect(actual, orderedEquals(await pixels('two-dots')));
    expect(actual, isNot(orderedEquals(await pixels('three-dots'))));
  });

  testWidgets(
    'account tiles do not overflow under a large accessibility text scale',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = _ledger();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            // Simulate a large system accessibility text-scale setting
            // (well beyond typical "Largest" presets) applied app-wide.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.0)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AccountGridHomeWidget(
                  state: state,
                  onTabSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      expect(_nameSemantics('Foreign Wallet'), findsOneWidget);
      expect(_nameSemantics('Cash Purse'), findsOneWidget);
      await tester.ensureVisible(_nameSemantics('Cash Purse'));
      expect(tester.takeException(), isNull);
      for (final name in ['Foreign Wallet', 'Cash Purse']) {
        final tile = find
            .ancestor(of: _nameSemantics(name), matching: find.byType(InkWell))
            .first;
        expect(
          tester.getSemantics(tile).getSemanticsData().label,
          contains(name),
        );
        expect(
          find.descendant(
            of: _nameSemantics(name),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      }
      final amounts = find.byType(PrivacyText);
      for (final text in tester.widgetList<Text>(
        find.descendant(of: amounts, matching: find.byType(Text)),
      )) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.byWidget(text))
              .didExceedMaxLines,
          isFalse,
        );
      }
      semantics.dispose();
    },
  );
}

class _ExpectedNamePainter extends CustomPainter {
  const _ExpectedNamePainter(this.name, this.style, this.ellipsis);

  final String name;
  final TextStyle style;
  final String ellipsis;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: name, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      ellipsis: ellipsis,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, Offset.zero);
    painter.dispose();
  }

  @override
  bool shouldRepaint(_ExpectedNamePainter oldDelegate) => false;
}

LedgerState _ledger() {
  return const LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: LedgerPreferences(baseCurrency: 'INR'),
    accounts: [
      Account(
        id: 'foreign',
        name: 'Foreign Wallet',
        type: 'bank',
        currency: 'USD',
        openingBalance: Money(amountMinor: 543210, currency: 'USD'),
        showOnHome: true,
        sortOrder: 1,
      ),
      Account(
        id: 'cash',
        name: 'Cash Purse',
        type: 'cash',
        currency: 'INR',
        openingBalance: Money(amountMinor: 250000, currency: 'INR'),
        showOnHome: true,
        sortOrder: 2,
      ),
    ],
    categories: [],
    transactions: [],
    captureCandidates: [],
  );
}

Finder _nameSemantics(String name) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == name,
);
