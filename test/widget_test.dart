import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';

import 'test_harness.dart';

void main() {
  testWidgets('1Wallet app shell smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(),
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1Wallet'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
  });
}
