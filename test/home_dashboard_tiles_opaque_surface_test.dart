import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/features/home/home_widget_card.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

/// The dashboard cards use the shared Liquid Glass surface while keeping
/// their content visible and interactions functional.
void main() {
  testWidgets('HomeWidgetCard renders a Liquid Glass surface', (tester) async {
    const scheme = ColorScheme.light(
      surface: Color(0xFF112233),
      outlineVariant: Color(0xFF445566),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: HomeWidgetCard(
            title: 'Net worth',
            icon: Icons.account_balance_outlined,
            child: const Text('tile body'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GlassCard), findsOneWidget);

    // The card content still renders.
    expect(find.text('Net worth'), findsOneWidget);
    expect(find.text('tile body'), findsOneWidget);
  });

  testWidgets('DashboardCard renders a Liquid Glass surface '
      'and still forwards taps', (tester) async {
    const scheme = ColorScheme.light(surface: Color(0xFF223344));
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: DashboardCard(
            onTap: () => tapped = true,
            child: const Text('dashboard body'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GlassCard), findsOneWidget);
    expect(find.text('dashboard body'), findsOneWidget);

    await tester.tap(find.byType(DashboardCard));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
