import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_components.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_widgets.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  test('system dynamic scheme is the shared app accent source', () {
    final systemScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );

    final theme = AppTheme.amoled(systemColorScheme: systemScheme);

    expect(theme.colorScheme.primary, systemScheme.primary);
  });

  test('AMOLED surfaces remain black-based', () {
    final amoled = AppTheme.amoled();
    expect(amoled.scaffoldBackgroundColor, Colors.black);
    expect(amoled.colorScheme.surface, AppColors.amoledBackground);
    expect(
      amoled.colorScheme.surfaceContainerLowest,
      AppColors.amoledBackground,
    );
    expect(amoled.cardTheme.color, AppColors.amoledSurfaceLow);
  });

  test('fallback accent is stable without dynamic color', () {
    expect(
      AppTheme.light().colorScheme.primary,
      AppTheme.light().colorScheme.primary,
    );
  });

  test(
    'custom accent color seeds the colorScheme when useSystemColor is false',
    () {
      const sapphire = Color(0xFF007AFF);
      final theme = AppTheme.light(
        customAccentColor: sapphire,
        useSystemColor: false,
      );
      expect(theme.colorScheme.primary, isNot(AppColors.primary));
      expect(theme.colorScheme.primary.toARGB32(), isNotNull);

      final amoledTheme = AppTheme.amoled(
        customAccentColor: sapphire,
        useSystemColor: false,
      );
      expect(amoledTheme.colorScheme.surface, AppColors.amoledBackground);
    },
  );

  test('color intensity changes saturation of primary color', () {
    const color = Color(0xFF007AFF);
    final lowIntensity = AppTheme.adjustColorIntensity(color, 0.2);
    final normalIntensity = AppTheme.adjustColorIntensity(color, 1.0);
    final highIntensity = AppTheme.adjustColorIntensity(color, 1.5);

    expect(normalIntensity, color);
    final lowHsl = HSLColor.fromColor(lowIntensity);
    final normalHsl = HSLColor.fromColor(normalIntensity);
    final highHsl = HSLColor.fromColor(highIntensity);

    expect(lowHsl.saturation, lessThan(normalHsl.saturation));
    expect(highHsl.saturation, greaterThanOrEqualTo(normalHsl.saturation));
  });

  testWidgets('category and add-record colors follow theme color scheme', (
    WidgetTester tester,
  ) async {
    final theme = AppTheme.light();
    late Color incomeCategoryColor;
    late ({
      Color operatorBackground,
      Color operatorForeground,
      Color equalsBackground,
      Color equalsForeground,
    })
    incomePadColors;

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
    expect(
      incomePadColors.operatorBackground,
      theme.colorScheme.tertiaryContainer.withValues(alpha: 0.43),
    );
    expect(incomePadColors.operatorForeground, theme.colorScheme.tertiary);
    expect(incomePadColors.equalsBackground, theme.colorScheme.tertiary);
    expect(incomePadColors.equalsForeground, theme.colorScheme.onTertiary);
  });

  testWidgets('add-record FAB glass icon uses the theme accent', (
    WidgetTester tester,
  ) async {
    final theme = AppTheme.light();

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

    final glassButton = tester.widget<GlassButton>(find.byType(GlassButton));

    expect(glassButton.iconColor, theme.colorScheme.primary);
    expect(glassButton.width, 64);
  });

  testWidgets('home balance pill uses accent tint instead of error color', (
    WidgetTester tester,
  ) async {
    final theme = AppTheme.light();

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

  testWidgets('search input keeps its controller and cursor across rebuilds', (
    WidgetTester tester,
  ) async {
    var query = '';
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: PremiumSearchInput(
                hintText: 'Search',
                value: query,
                onChanged: (value) => setState(() => query = value),
              ),
            );
          },
        ),
      ),
    );

    final searchBar = tester.widget<GlassSearchBar>(
      find.byType(GlassSearchBar),
    );
    final controller = searchBar.controller!;
    controller.value = const TextEditingValue(
      text: 'merchant',
      selection: TextSelection.collapsed(offset: 2),
    );
    searchBar.onChanged?.call('merchant');
    await tester.pump();

    final rebuiltSearchBar = tester.widget<GlassSearchBar>(
      find.byType(GlassSearchBar),
    );
    expect(identical(rebuiltSearchBar.controller, controller), isTrue);
    controller.selection = const TextSelection.collapsed(offset: 2);
    rebuild(() {});
    await tester.pump();

    final rebuiltController = tester
        .widget<GlassSearchBar>(find.byType(GlassSearchBar))
        .controller!;
    expect(identical(rebuiltController, controller), isTrue);
    expect(rebuiltController.selection.extentOffset, 2);
  });
}
