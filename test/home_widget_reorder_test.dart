import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home screen reorders widgets in place and persists order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reorder widgets'), findsNothing);

    await tester.longPress(find.byTooltip('Long press All accounts to reorder widgets'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Done reordering widgets'), findsOneWidget);
    expect(find.byTooltip('Drag All accounts'), findsOneWidget);

    await tester.tap(find.byTooltip('Move up All accounts'));
    await tester.pumpAndSettle();

    expect(container.read(ledgerProvider).preferences.homeWidgetOrder.take(2), [
      'accountGrid',
      'balanceHero',
    ]);

    await tester.tap(find.byTooltip('Done reordering widgets'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reorder widgets'), findsNothing);
  });
}
