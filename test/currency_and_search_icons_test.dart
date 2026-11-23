import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/utils/currency_utils.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';
import 'package:one_wallet_flutter/src/features/common/full_screen_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iconForCurrency tests', () {
    test('returns correct Material icon for major global currencies', () {
      expect(iconForCurrency('USD'), equals(Icons.attach_money_rounded));
      expect(iconForCurrency('CAD'), equals(Icons.attach_money_rounded));
      expect(iconForCurrency('AUD'), equals(Icons.attach_money_rounded));
      expect(iconForCurrency('EUR'), equals(Icons.euro_rounded));
      expect(iconForCurrency('GBP'), equals(Icons.currency_pound_rounded));
      expect(iconForCurrency('INR'), equals(Icons.currency_rupee_rounded));
      expect(iconForCurrency('JPY'), equals(Icons.currency_yen_rounded));
      expect(iconForCurrency('CNY'), equals(Icons.currency_yen_rounded));
      expect(iconForCurrency('RUB'), equals(Icons.currency_ruble_rounded));
      expect(iconForCurrency('TRY'), equals(Icons.currency_lira_rounded));
      expect(iconForCurrency('CHF'), equals(Icons.currency_franc_rounded));
      expect(iconForCurrency('BTC'), equals(Icons.currency_bitcoin_rounded));
    });

    test('returns payments fallback icon for unmapped currencies', () {
      expect(iconForCurrency('XYZ'), equals(Icons.payments_rounded));
      expect(iconForCurrency('UNKNOWN'), equals(Icons.payments_rounded));
    });

    test('CurrencyInfo.icon property returns expected icon', () {
      final usdInfo = getCurrencyInfo('USD');
      expect(usdInfo.icon, equals(Icons.attach_money_rounded));

      final inrInfo = getCurrencyInfo('INR');
      expect(inrInfo.icon, equals(Icons.currency_rupee_rounded));
    });
  });

  group('PremiumRow & PickerOption iconWidget tests', () {
    testWidgets('PremiumRow displays iconWidget when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumRow(
              icon: Icons.circle,
              iconWidget: const Text('CUSTOM_ICON'),
              title: 'US Dollar',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('CUSTOM_ICON'), findsOneWidget);
      expect(find.text('US Dollar'), findsOneWidget);
    });

    testWidgets('PickerOption accepts icon and iconWidget', (tester) async {
      const option = PickerOption<String>(
        value: 'USD',
        title: 'United States Dollar (USD)',
        icon: Icons.attach_money_rounded,
        iconWidget: Text('🇺🇸'),
      );

      expect(option.icon, equals(Icons.attach_money_rounded));
      expect(option.iconWidget, isNotNull);
    });
  });

  group('PremiumSearchInput Cupertino icon bundling test', () {
    testWidgets('PremiumSearchInput renders search bar successfully', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumSearchInput(
              hintText: 'Search records',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Search records'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
    });
  });
}
