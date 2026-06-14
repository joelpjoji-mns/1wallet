import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/imports/wallet_csv_parser.dart';

void main() {
  test('parses wallet CSV with headers into import rows', () {
    final result = parseWalletCsv('''
date,account,amount,category,notes,currency
2026-06-08,HDFC Main,-890.50,Food,"Swiggy, dinner",INR
2026-06-07,HDFC Main,185000,Salary,Monthly salary,INR
''');

    expect(result.rows.length, 2);
    expect(result.rows.first.rowNumber, 2);
    expect(result.rows.first.type, 'expense');
    expect(result.rows.first.amount.amountMinor, 89050);
    expect(result.rows.first.categoryName, 'Food');
    expect(result.rows.first.notes, 'Swiggy, dinner');
    expect(result.rows.last.type, 'income');
    expect(result.rows.last.amount.amountMinor, 18500000);
  });

  test('skips rows with invalid amounts and reports warnings', () {
    final result = parseWalletCsv('''
date,account,amount,category
2026-06-08,HDFC Main,not-money,Food
2026-06-07,HDFC Main,-120,Travel
''');

    expect(result.rows.length, 1);
  });

  test('supports headerless default wallet CSV order', () {
    final result = parseWalletCsv(
      '08/06/2026,Cash Wallet,-120,Travel,Metro ride',
    );

    expect(result.rows.single.accountName, 'Cash Wallet');
    expect(result.rows.single.amount.amountMinor, 12000);
    expect(result.rows.single.occurredAt, isNotNull);
    expect(result.rows.single.categoryName, 'Travel');
  });

  test('supports manual column mapping for unusual column order', () {
    final result = parseWalletCsv(
      'HDFC Main,Food,-321,Manual mapped note,2026-06-08',
      mapping: const WalletCsvColumnMapping(
        accountColumn: 1,
        categoryColumn: 2,
        amountColumn: 3,
        notesColumn: 4,
        dateColumn: 5,
      ),
    );

    expect(result.rows.single.accountName, 'HDFC Main');
    expect(result.rows.single.categoryName, 'Food');
    expect(result.rows.single.amount.amountMinor, 32100);
    expect(result.rows.single.notes, 'Manual mapped note');
    expect(result.rows.single.occurredAt, DateTime(2026, 6, 8));
  });

  test('manual column mapping can skip a header row', () {
    final result = parseWalletCsv(
      '''account_name,label,total,memo,posted
HDFC Main,Food,-321,Manual mapped note,2026-06-08''',
      mapping: const WalletCsvColumnMapping(
        hasHeader: true,
        accountColumn: 1,
        categoryColumn: 2,
        amountColumn: 3,
        notesColumn: 4,
        dateColumn: 5,
      ),
    );

    expect(result.rows.single.rowNumber, 2);
    expect(result.rows.single.notes, 'Manual mapped note');
  });
}
