import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

// ignore_for_file: dead_code
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Data Backup screen restores a pasted archive', (tester) async {
    // ...
  }, skip: true);

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
