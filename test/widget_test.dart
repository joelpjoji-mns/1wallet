import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('1Wallet app shell smoke test', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(prefs: prefs),
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1Wallet'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
  });
}
