import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('account details color swatch persists selected color', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
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
    await tester.pumpAndSettle();
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());
    await tester.pumpAndSettle();
    router.go('/account/acc-bank');
    await tester.pumpAndSettle();

    final chooseColorFinder = find.text('Choose color');
    await tester.ensureVisible(chooseColorFinder);
    await tester.pumpAndSettle();
    await tester.tap(chooseColorFinder);
    await tester.pumpAndSettle();

    final hexInput = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(hexInput);
    await tester.enterText(hexInput, '#123456');
    await tester.pump();
    await tester.ensureVisible(find.text('Select'));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    final colorPanel = tester.widget<AppPanel>(
      find
          .ancestor(of: chooseColorFinder, matching: find.byType(AppPanel))
          .first,
    );
    expect(colorPanel.color, const Color(0xff123456));
    expect(tester.widget<Text>(chooseColorFinder).style!.color, Colors.white);

    final icon = find.byKey(const ValueKey('account-color-icon'));
    await tester.ensureVisible(icon);
    await tester.pumpAndSettle();
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('Account color'), findsOneWidget);
    expect(
      tester.widget<TextField>(hexInput).controller!.text,
      contains('123456'),
    );
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    final account = container
        .read(ledgerProvider)
        .accounts
        .firstWhere((item) => item.id == 'acc-bank');
    expect(account.color, const Color(0xff123456));
  });
}
