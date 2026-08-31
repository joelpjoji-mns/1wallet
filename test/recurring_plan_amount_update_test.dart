import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('upsertTransaction properly updates amount when changing plan amount', () async {
    final seedState = emptyLedgerState().copyWith(
      accounts: [
        Account(
          id: 'acc-usd',
          name: 'USD Checking',
          type: 'bank',
          currency: 'USD',
          color: Colors.blue,
          openingBalance: Money(amountMinor: 100000, currency: 'USD'),
        ),
        Account(
          id: 'acc-eur',
          name: 'EUR Savings',
          type: 'savings',
          currency: 'EUR',
          color: Colors.green,
          openingBalance: Money(amountMinor: 50000, currency: 'EUR'),
        ),
      ],
      preferences: LedgerPreferences(
        baseCurrency: 'USD',
        displayCurrency: 'USD',
        enabledCurrencies: ['USD', 'EUR'],
      ),
    );

    final controller = LedgerController(
      StaticLedgerRepository(seedState),
      setLoadState: (_) {},
      initialState: seedState,
    );

    // Wait a tick for async load
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 1. Create a planned transaction in USD (account currency)
    final plan1 = await controller.upsertTransaction(
      type: 'expense',
      accountId: 'acc-usd',
      amountMinor: 5000, // $50.00
      status: 'scheduled',
      source: 'recurring',
      name: 'Internet Subscription',
      recurrenceFrequency: 'monthly',
      recurrenceInterval: 1,
    );

    expect(plan1.amount.amountMinor, 5000);
    expect(plan1.originalAmount, isNull);

    // Update plan1 amount to $75.00 in account currency
    final updatedPlan1 = await controller.upsertTransaction(
      id: plan1.id,
      type: 'expense',
      accountId: 'acc-usd',
      amountMinor: 7500,
      originalCurrency: 'USD',
      originalAmountMinor: 7500,
      clearOriginalAmount: true,
      status: 'scheduled',
      source: 'recurring',
      name: 'Internet Subscription',
      recurrenceFrequency: 'monthly',
    );

    expect(updatedPlan1.amount.amountMinor, 7500);
    expect(updatedPlan1.originalAmount, isNull);

    // 2. Create a planned transaction in a foreign currency (EUR on USD account)
    final plan2 = await controller.upsertTransaction(
      type: 'expense',
      accountId: 'acc-usd',
      amountMinor: 11000, // Converted USD
      originalCurrency: 'EUR',
      originalAmountMinor: 10000, // 100.00 EUR
      status: 'scheduled',
      source: 'recurring',
      name: 'Hosting Plan',
      recurrenceFrequency: 'monthly',
    );

    expect(plan2.amount.amountMinor, 11000);
    expect(plan2.originalAmount?.amountMinor, 10000);
    expect(plan2.originalAmount?.currency, 'EUR');

    // Update foreign amount from 100 EUR to 150 EUR
    final updatedPlan2 = await controller.upsertTransaction(
      id: plan2.id,
      type: 'expense',
      accountId: 'acc-usd',
      amountMinor: 16500, // Converted USD
      originalCurrency: 'EUR',
      originalAmountMinor: 15000, // 150.00 EUR
      status: 'scheduled',
      source: 'recurring',
      name: 'Hosting Plan',
      recurrenceFrequency: 'monthly',
    );

    expect(updatedPlan2.amount.amountMinor, 16500);
    expect(updatedPlan2.originalAmount?.amountMinor, 15000);
    expect(updatedPlan2.originalAmount?.currency, 'EUR');

    // 3. Update plan2 to be in the account currency (USD) instead of EUR
    // Previous bug: originalAmount was NOT cleared and kept the old 150 EUR.
    final updatedPlan2ToUsd = await controller.upsertTransaction(
      id: plan2.id,
      type: 'expense',
      accountId: 'acc-usd',
      amountMinor: 8000, // $80.00 USD
      originalCurrency: 'USD',
      originalAmountMinor: 8000,
      clearOriginalAmount: true,
      status: 'scheduled',
      source: 'recurring',
      name: 'Hosting Plan',
      recurrenceFrequency: 'monthly',
    );

    expect(updatedPlan2ToUsd.amount.amountMinor, 8000);
    expect(updatedPlan2ToUsd.amount.currency, 'USD');
    expect(updatedPlan2ToUsd.originalAmount, isNull);
  });
}
