import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_components.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_widgets.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {

  test('custom accent overrides system dynamic scheme', () {
    final systemScheme = ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.light,
    );

    final theme = AppTheme.light(
      accentColor: '#123456',
      systemColorScheme: systemScheme,
    );

    expect(theme.colorScheme.primary, const Color(0xFF123456));
  });

  test('system dynamic scheme is used when no custom accent is selected', () {
    final systemScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );

    final theme = AppTheme.dark(systemColorScheme: systemScheme);

    expect(theme.colorScheme.primary, systemScheme.primary);
  });

  test('card surfaces are tinted by the selected accent', () {
    final cyanTheme = AppTheme.light(accentColor: '#00BCD4');
    final purpleTheme = AppTheme.light(accentColor: '#6750A4');

    expect(cyanTheme.colorScheme.surfaceContainerLow,
        isNot(purpleTheme.colorScheme.surfaceContainerLow));
    expect(cyanTheme.cardTheme.color, cyanTheme.colorScheme.surfaceContainerLow);
  });

  testWidgets('category and add-record colors follow theme color scheme', (
    WidgetTester tester,
  ) async {
    final theme = AppTheme.light(accentColor: '#6750A4');
    late Color incomeCategoryColor;
    late ({
      Color operatorBackground,
      Color operatorForeground,
      Color equalsBackground,
      Color equalsForeground,
    }) incomePadColors;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            incomeCategoryColor = categoryColor(
              const Category(id: 'salary', name: 'Salary', kind: 'income'),
              context,
            );
            incomePadColors = addRecordCalculatorPadColors(context, 'income');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(incomeCategoryColor, theme.colorScheme.tertiary);
    expect(incomePadColors.operatorBackground, theme.colorScheme.tertiaryContainer.withAlpha(110));
    expect(incomePadColors.operatorForeground, theme.colorScheme.tertiary);
    expect(incomePadColors.equalsBackground, theme.colorScheme.tertiary);
    expect(incomePadColors.equalsForeground, theme.colorScheme.onTertiary);
  });

  testWidgets('add-record FAB inner fill uses lighter accent tint', (
    WidgetTester tester,
  ) async {
    final theme = AppTheme.light(accentColor: '#00BCD4');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: IslandFloatingActionButton(
                icon: Icons.add_rounded,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = animatedContainer.decoration! as BoxDecoration;

    expect(
      decoration.color,
      theme.colorScheme.primary.withAlphaFactor(0.15),
    );
  });

  testWidgets('home balance pill uses accent tint instead of error color', (
    WidgetTester tester,
  ) async {
    final theme = AppTheme.light(accentColor: '#00BCD4');

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: HomeBalancePill(
              label: 'This month',
              icon: Icons.calendar_month,
              showChevron: true,
            ),
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(HomeBalancePill),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.color, theme.colorScheme.primary.withAlphaFactor(0.16));
  });
}
