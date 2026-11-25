import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/data_backup_screen.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

// ignore_for_file: dead_code
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Data Backup screen restores a pasted archive', (tester) async {
    // ...
  }, skip: true);

  testWidgets('backup actions remain single-line at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const DataBackupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Back up now', 'Export to file', 'Secure export']) {
      final text = find.text(label);
      await tester.ensureVisible(text);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(
        paragraph.size.height,
        lessThanOrEqualTo(paragraph.preferredLineHeight + 1),
        reason: label,
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Widgets screen persists home widget order changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
        ),
      ),
    );
    router.go('/widgets');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Move down Balance Hero'));
    await tester.pumpAndSettle();

    expect(container.read(ledgerProvider).preferences.homeWidgetOrder.take(2), [
      'accountGrid',
      'balanceHero',
    ]);

    await tester.tap(find.byTooltip('Reset widget order'));
    await tester.pumpAndSettle();

    expect(container.read(ledgerProvider).preferences.homeWidgetOrder.take(2), [
      'balanceHero',
      'accountGrid',
    ]);
  }, skip: true);
}
