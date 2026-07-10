import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_components.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets('HomeFlowPanel numerically animates money changes', (
    WidgetTester tester,
  ) async {
    const locale = 'en_IN';
    const start = Money(amountMinor: 0, currency: 'INR');
    const end = Money(amountMinor: 100000, currency: 'INR');

    await tester.pumpWidget(
      _wrap(
        const HomeFlowPanel(
          label: 'Income',
          value: start,
          locale: locale,
          tone: MetricTone.positive,
        ),
      ),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
    expect(find.text(formatMoney(start, locale)), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        const HomeFlowPanel(
          label: 'Income',
          value: end,
          locale: locale,
          tone: MetricTone.positive,
        ),
      ),
    );

    expect(find.text(formatMoney(start, locale)), findsOneWidget);
    expect(find.text(formatMoney(end, locale)), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(formatMoney(end, locale)), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}
