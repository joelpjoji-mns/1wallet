import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/imports/statement_parser.dart';

void main() {
  group('Universal Statement Parser', () {
    test('parses statement with multi-line narration and balance delta', () {
      const statement = '''
Account Statement
Account Number: 12345678901
Branch: CENTRAL
Currency: INR
Statement Period: 01/04/2025 to 30/04/2025

Txn Date    Narration                             Chq/Ref No    Debit         Credit        Balance
01/04/2025  OPENING BALANCE                                                                 50,000.00
03/04/2025  TO TRANSFER-UPI/DR/509122345/
            TEA STALL/PUNB/REF991823              UPI991823     50.00                       49,950.00
05/04/2025  BY TRANSFER-NEFT*ACME CORP*
            SALARY FOR MARCH 2025                 NEFT88123                   75,000.00     1,24,950.00
12/04/2025  TO DEBIT-ATM CASH WDL
            ATM CENTRAL CITY                      ATM44123      5,000.00                    1,19,950.00
Page 1 of 1
This is a system generated statement
''';

      final result = parseStatement(statement, accountName: 'Primary Savings');

      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3);

      // Row 1: Tea Stall (Expense)
      final row1 = result.rows[0];
      expect(row1.type, 'expense');
      expect(row1.amount.amountMinor, 5000); // 50.00
      expect(row1.notes, contains('TEA STALL'));
      expect(row1.occurredAt, DateTime(2025, 4, 3));

      // Row 2: Salary (Income)
      final row2 = result.rows[1];
      expect(row2.type, 'income');
      expect(row2.amount.amountMinor, 7500000); // 75,000.00
      expect(row2.notes, contains('SALARY FOR MARCH 2025'));
      expect(row2.occurredAt, DateTime(2025, 4, 5));

      // Row 3: ATM Cash Wdl (Expense)
      final row3 = result.rows[2];
      expect(row3.type, 'expense');
      expect(row3.amount.amountMinor, 500000); // 5,000.00
      expect(row3.occurredAt, DateTime(2025, 4, 12));
    });

    test('parses statement with DD/MM/YY dates and wrapped POS details', () {
      const statement = '''
Statement of Account
Customer ID: 98765432
Account No: 50100234567890
From: 01/05/2025 To: 31/05/2025

Date        Narration                             Chq/Ref No    Value Dt    Withdrawal    Deposit    Closing Balance
02/05/25    POS 401293XXXXXX9182
            DMART RETAIL MUMBAI
            VALUE DATE 02/05/2025                 POS9182       02/05/25    1,450.50                 28,549.50
10/05/25    UPI-SWIGGY-BANGALORE
            ORDER 581920                          UPI82371      10/05/25    320.00                   28,229.50
25/05/25    CREDIT INTEREST CAPITALISED                         25/05/25                  420.00     28,649.50
''';

      final result = parseStatement(statement, accountName: 'Main Checking');

      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 145050);
      expect(result.rows[0].notes, contains('DMART RETAIL MUMBAI'));
      expect(result.rows[0].occurredAt, DateTime(2025, 5, 2));

      expect(result.rows[1].type, 'expense');
      expect(result.rows[1].amount.amountMinor, 32000);
      expect(result.rows[1].occurredAt, DateTime(2025, 5, 10));

      expect(result.rows[2].type, 'income');
      expect(result.rows[2].amount.amountMinor, 42000);
      expect(result.rows[2].notes, contains('CREDIT INTEREST'));
      expect(result.rows[2].occurredAt, DateTime(2025, 5, 25));
    });

    test('parses statement with DD Mon YYYY dates and CR/DR column', () {
      const statement = '''
Account Statement
Statement Period: 01 Jan 2025 to 31 Jan 2025
Account No: 1122334455

Date          Description                         Chq/Ref No    Amount          Dr / Cr    Balance
05 Jan 2025   AMAZON SELLER SERVICES
              ORDER 403-1928371-1234567           REF1234       2,199.00        DR         45,801.00
14 Jan 2025   REFUND FROM FLIPKART
              TXN 9928172                         REF5678       1,200.00        CR         47,001.00
20 Jan 2025   UBER RIDE MUMBAI
              INR TRIP 8812                       REF9988       350.00          DR         46,651.00
''';

      final result = parseStatement(statement, accountName: 'Personal');

      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 219900);
      expect(result.rows[0].notes, contains('AMAZON SELLER'));
      expect(result.rows[0].occurredAt, DateTime(2025, 1, 5));

      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 120000);
      expect(result.rows[1].notes, contains('REFUND FROM FLIPKART'));
      expect(result.rows[1].occurredAt, DateTime(2025, 1, 14));

      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 35000);
      expect(result.rows[2].occurredAt, DateTime(2025, 1, 20));
    });

    test('parses statement with USD currency and negative amounts', () {
      const statement = '''
Account Statement
Account Number: ...4321
Currency: USD

Date        Description                               Amount          Balance
10/12/2024  STARBUCKS STORE 1024 SEATTLE WA           -4.75           2,495.25
10/14/2024  PAYROLL DIRECT DEPOSIT ACME CORP          2,500.00        4,995.25
10/18/2024  TARGET T-1244 BELLEVUE WA                 -82.10          4,913.15
''';

      final result = parseStatement(statement, accountName: 'USD Checking');

      expect(result.detectedCurrency, 'USD');
      expect(result.rows.length, 3);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 475); // $4.75
      expect(result.rows[0].amount.currency, 'USD');
      expect(result.rows[0].notes, contains('STARBUCKS STORE'));
      expect(result.rows[0].occurredAt, DateTime(2024, 10, 12));

      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 250000); // $2,500.00
      expect(result.rows[1].amount.currency, 'USD');
      expect(result.rows[1].occurredAt, DateTime(2024, 10, 14));

      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 8210); // $82.10
      expect(result.rows[2].amount.currency, 'USD');
      expect(result.rows[2].occurredAt, DateTime(2024, 10, 18));
    });

    test('parses statement with GBP currency (£ symbol)', () {
      const statement = '''
Account Statement
Account ending 8912
Sort Code: 20-00-00

Date        Description                       Money out (£)   Money in (£)    Balance (£)
03/06/2025  TFL TRAVEL CHARGE TFL.GOV.UK      3.40                            1,246.60
05/06/2025  MARKS AND SPENCER LONDON          18.50                           1,228.10
15/06/2025  DIVIDEND VANGUARD FTSE                            150.00          1,378.10
''';

      final result = parseStatement(statement, accountName: 'GBP Current');

      expect(result.detectedCurrency, 'GBP');
      expect(result.rows.length, 3);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 340); // £3.40
      expect(result.rows[0].amount.currency, 'GBP');
      expect(result.rows[0].notes, contains('TFL TRAVEL CHARGE'));

      expect(result.rows[1].type, 'expense');
      expect(result.rows[1].amount.amountMinor, 1850); // £18.50

      expect(result.rows[2].type, 'income');
      expect(result.rows[2].amount.amountMinor, 15000); // £150.00
      expect(result.rows[2].notes, contains('DIVIDEND VANGUARD'));
    });

    test('parses reverse-chronological statement (newest first)', () {
      const reverseStatement = '''
Account Statement
Account: 99887766
Currency: EUR

Date        Details                           Amount (€)      Balance (€)
15/07/2025  SUPERMARCHE CARREFOUR PARIS       -45.00          1,955.00
10/07/2025  SALARY JULY 2025                  2,000.00        2,000.00
''';

      final result = parseStatement(reverseStatement, accountName: 'EUR Account');

      expect(result.detectedCurrency, 'EUR');
      expect(result.rows.length, 2);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 4500);

      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 200000);
    });

    test('ignores messy page headers and footers across multi-page statement', () {
      const multiPageStatement = '''
Statement of Account
Account No: 12340001
Page 1 of 2

Date          Narration                         Withdrawal      Deposit       Balance
01-04-2025    OPENING BALANCE                                                 10,000.00
02-04-2025    UPI/GROCERIES/REF123              250.00                        9,750.00
Page 1 of 2
-------------------------------------------------------------
Statement of Account
Account No: 12340001
Page 2 of 2
03-04-2025    CASH DEPOSIT BRANCH                               5,000.00      14,750.00
04-04-2025    ELECTRICITY BILL PAYMENT          1,100.00                      13,650.00
Page 2 of 2
End of statement
''';

      final result = parseStatement(multiPageStatement, accountName: 'Savings');

      expect(result.rows.length, 3);
      expect(result.rows[0].notes, contains('GROCERIES'));
      expect(result.rows[0].type, 'expense');
      expect(result.rows[1].notes, contains('CASH DEPOSIT'));
      expect(result.rows[1].type, 'income');
      expect(result.rows[2].notes, contains('ELECTRICITY BILL'));
      expect(result.rows[2].type, 'expense');
    });

    test('Pass 3 self-recovery: parses credit card statement without running balances', () {
      const cardStatement = '''
Credit Card Statement
Card ending: 9182
Total Due: INR 22,450.00
Payment Due Date: 20/07/2025

Date        Transaction Description           Amount (INR)
12/06/2025  NETFLIX ENTERTAINMENT MUMBAI      649.00
15/06/2025  AUTOPAY PAYMENT RECEIVED - THANK YOU  15,000.00 CR
20/06/2025  AMAZON INDIA RETAIL               2,450.00
''';

      final result = parseStatement(cardStatement, accountName: 'Credit Card');

      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3);
      expect(result.rows[0].notes, contains('NETFLIX'));
      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 64900);

      expect(result.rows[1].notes, contains('AUTOPAY PAYMENT'));
      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 1500000);

      expect(result.rows[2].notes, contains('AMAZON'));
      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 245000);
    });

    test('Pass 2 self-recovery: parses statements with transaction token prefix before date', () {
      const tokenPrefixStatement = '''
Account Statement
Account: 1092837465

Txn ID      Date        Particulars                   Amount      Dr/Cr
TXN001      15/04/2025  CAFE COFFEE DAY BANGALORE     280.00      DR
TXN002      18/04/2025  CLIENT PAYMENT INWARD         12,000.00   CR
TXN003      25/04/2025  UBER TRIP BLR                 420.00      DR
''';

      final result = parseStatement(tokenPrefixStatement, accountName: 'Current');

      expect(result.rows.length, 3);
      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 28000);
      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 1200000);
      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 42000);
    });

    test('generates diagnostic explanation on scanned image PDF with minimal text', () {
      const scannedPdfText = 'Scan 001.pdf\n';

      final result = parseStatement(scannedPdfText, accountName: 'Test');

      expect(result.rows, isEmpty);
      expect(result.diagnostics, isNotNull);
      expect(result.diagnostics, contains('scanned'));
    });
  });
}
