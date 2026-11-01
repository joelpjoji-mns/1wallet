import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  testWidgets('CreditUtilizationWidget sorts cards by utilisation percentage descending', (tester) async {
    final now = DateTime(2026, 11, 1);
    Money usd(int minor) => Money(amountMinor: minor, currency: 'USD');

    final cardLowUtil = Account(
      id: 'card-low',
      name: 'Card Low 10%',
      type: 'credit_card',
      currency: 'USD',
      openingBalance: usd(0),
      creditLimit: usd(100000), // $1000 limit
    );
    final cardHighUtil = Account(
      id: 'card-high',
      name: 'Card High 80%',
      type: 'credit_card',
      currency: 'USD',
      openingBalance: usd(0),
      creditLimit: usd(100000), // $1000 limit
    );
    final cardZeroUtil = Account(
      id: 'card-zero',
      name: 'Card Zero 0%',
      type: 'credit_card',
      currency: 'USD',
      openingBalance: usd(0),
      creditLimit: usd(50000), // $500 limit
    );

    final base = sampleLedgerState();
    final sampleTx = base.transactions.first;

    final txLow = sampleTx.copyWith(
      id: 'tx-low',
      type: 'expense',
      status: 'cleared',
      accountId: 'card-low',
      amount: usd(10000),
      occurredAt: now,
    );
    final txHigh = sampleTx.copyWith(
      id: 'tx-high',
      type: 'expense',
      status: 'cleared',
      accountId: 'card-high',
      amount: usd(80000),
      occurredAt: now,
    );

    final ledgerState = base.copyWith(
      accounts: [cardLowUtil, cardZeroUtil, cardHighUtil],
      transactions: [txLow, txHigh],
      preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderScope(
            child: SingleChildScrollView(
              child: CreditUtilizationWidget(state: ledgerState),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify all 3 cards are rendered
    expect(find.text('Card High 80%'), findsOneWidget);
    expect(find.text('Card Low 10%'), findsOneWidget);
    expect(find.text('Card Zero 0%'), findsOneWidget);

    // Verify ordering: High (80%) must appear before Low (10%) and Zero (0%)
    final highTop = tester.getTopLeft(find.text('Card High 80%')).dy;
    final lowTop = tester.getTopLeft(find.text('Card Low 10%')).dy;
    final zeroTop = tester.getTopLeft(find.text('Card Zero 0%')).dy;

    expect(highTop, lessThan(lowTop), reason: '80% card should appear before 10% card');
    expect(lowTop, lessThan(zeroTop), reason: '10% card should appear before 0% card');
  });
}
