import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('All accounts tiles use account color and contrast foreground', (
    tester,
  ) async {
    const accountColor = Color(0xFF315DA8);
    final state = _ledger(
      accounts: const [
        Account(
          id: 'dark-account',
          name: 'Dark Account Tile',
          type: 'bank',
          currency: 'INR',
          openingBalance: Money(amountMinor: 10000, currency: 'INR'),
          color: accountColor,
          sortOrder: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('account-grid'),
              child: AccountGridHomeWidget(
                state: state,
                onTabSelected: (int index) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final accountTiles = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == accountColor;
    });

    expect(accountTiles, findsWidgets);
    await _expectNameColor(tester, 'Dark Account Tile', Colors.white);
  });

  testWidgets('All accounts tiles use dark text on light account color', (
    tester,
  ) async {
    const accountColor = Color(0xFFFFE082);
    final state = _ledger(
      accounts: const [
        Account(
          id: 'light-account',
          name: 'Light Account Tile',
          type: 'wallet',
          currency: 'INR',
          openingBalance: Money(amountMinor: 20000, currency: 'INR'),
          color: accountColor,
          sortOrder: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('account-grid'),
              child: AccountGridHomeWidget(
                state: state,
                onTabSelected: (int index) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final accountTiles = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == accountColor;
    });

    expect(accountTiles, findsWidgets);
    await _expectNameColor(tester, 'Light Account Tile', Colors.black);
  });
}

Future<void> _expectNameColor(
  WidgetTester tester,
  String name,
  Color expected,
) async {
  final nameLabel = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == name,
  );
  final namePaint = find.descendant(
    of: nameLabel,
    matching: find.byType(CustomPaint),
  );
  expect(namePaint, findsOneWidget);

  final boundaryFinder = find.byKey(const ValueKey('account-grid'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final bounds = tester
      .getRect(namePaint)
      .shift(-tester.getTopLeft(boundaryFinder));
  final imageData = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width;
    image.dispose();
    return (bytes, width);
  }))!;
  final (bytes, width) = imageData;
  var found = false;
  for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
    for (var x = bounds.left.ceil(); x < bounds.right.floor(); x++) {
      final offset = (y * width + x) * 4;
      final r = bytes.getUint8(offset);
      final g = bytes.getUint8(offset + 1);
      final b = bytes.getUint8(offset + 2);
      if (expected == Colors.white
          ? r > 245 && g > 245 && b > 245
          : r < 10 && g < 10 && b < 10) {
        found = true;
      }
    }
  }
  expect(found, isTrue, reason: 'Account name should paint in $expected');
}

LedgerState _ledger({required List<Account> accounts}) {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: const LedgerPreferences(),
    accounts: accounts,
    categories: const [],
    transactions: const [],

    captureCandidates: const [],
  );
}
