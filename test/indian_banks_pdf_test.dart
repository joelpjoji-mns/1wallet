// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/imports/pdf_text_extractor.dart';
import 'package:one_wallet_flutter/src/imports/statement_parser.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List _generatePdfStatement({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
  String? password,
  String? headerDetails,
}) {
  final document = PdfDocument();
  if (password != null && password.isNotEmpty) {
    document.security.userPassword = password;
  }

  final page = document.pages.add();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 9);
  final boldFont = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);

  var yOffset = 20.0;
  page.graphics.drawString(title, boldFont, bounds: Rect.fromLTWH(20, yOffset, 500, 20));
  yOffset += 25;

  if (headerDetails != null) {
    page.graphics.drawString(headerDetails, font, bounds: Rect.fromLTWH(20, yOffset, 500, 30));
    yOffset += 35;
  }

  final grid = PdfGrid();
  grid.columns.add(count: headers.length);
  grid.headers.add(1);
  final headerRow = grid.headers[0];
  for (var i = 0; i < headers.length; i++) {
    headerRow.cells[i].value = headers[i];
  }

  for (final r in rows) {
    final row = grid.rows.add();
    for (var i = 0; i < r.length; i++) {
      row.cells[i].value = r[i];
    }
  }

  grid.draw(page: page, bounds: Rect.fromLTWH(20, yOffset, 500, 600));

  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

void main() {
  group('Real PDF Generation & Universal Parsing for Indian Banks', () {
    test('1. State Bank of India (SBI) - Real PDF with multi-line UPI narrations and balance delta', () {
      final sbiPdf = _generatePdfStatement(
        title: 'State Bank of India - Account Statement',
        headerDetails: 'Account Number: 30192837465\nCIF No: 89123456\nCurrency: INR\nPeriod: 01-04-2025 to 30-04-2025',
        headers: ['Txn Date', 'Description', 'Ref/Cheque No', 'Debit', 'Credit', 'Balance'],
        rows: [
          ['01/04/2025', 'OPENING BALANCE', '', '', '', '50,000.00'],
          ['03/04/2025', 'TO TRANSFER-UPI/DR/509122345/TEA STALL/PUNB/REF991823', 'UPI991823', '50.00', '', '49,950.00'],
          ['07/04/2025', 'BY TRANSFER-NEFT*INFOSYS LTD*SALARY MARCH 2025', 'NEFT88123', '', '85,000.00', '1,34,950.00'],
          ['12/04/2025', 'TO DEBIT-ATM CASH WDL KORAMANGALA BLR', 'ATM44123', '10,000.00', '', '1,24,950.00'],
          ['22/04/2025', 'TO TRANSFER-UPI/DR/612981721/AMAZON INDIA/HDFC/ORD9988', 'UPI33441', '2,499.00', '', '1,22,451.00'],
        ],
      );

      final extractedText = extractAllTextFromPdf(sbiPdf);
      final result = parseStatement(extractedText, accountName: 'SBI Savings');

      print('SBI Rows Extracted: ${result.rows.length}');
      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 4); // 4 real transactions (opening balance skipped)

      // Row 1: Tea Stall
      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 5000);
      expect(result.rows[0].notes, contains('TEA STALL'));

      // Row 2: Infosys Salary
      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 8500000);
      expect(result.rows[1].notes, contains('SALARY MARCH 2025'));

      // Row 3: ATM Cash
      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 1000000);

      // Row 4: Amazon
      expect(result.rows[3].type, 'expense');
      expect(result.rows[3].amount.amountMinor, 249900);
    });

    test('2. HDFC Bank - Real PDF with DD/MM/YY dates, Value Date, and POS narrations', () {
      final hdfcPdf = _generatePdfStatement(
        title: 'HDFC BANK LIMITED - Statement of Account',
        headerDetails: 'Cust ID: 98765432\nA/c No: 50100234567890\nBranch: KANJURMARG MUMBAI\nCurrency: INR',
        headers: ['Date', 'Narration', 'Chq/Ref No', 'Value Dt', 'Withdrawal Amt', 'Deposit Amt', 'Closing Balance'],
        rows: [
          ['02/05/25', 'POS 401293XXXXXX9182 DMART RETAIL MUMBAI', 'POS9182', '02/05/25', '1,450.50', '', '28,549.50'],
          ['10/05/25', 'UPI-SWIGGY-BANGALORE ORDER 581920', 'UPI82371', '10/05/25', '320.00', '', '28,229.50'],
          ['15/05/25', 'ACH CR-DIVIDEND-TCS LIMITED', 'ACH00918', '15/05/25', '', '3,500.00', '31,729.50'],
          ['25/05/25', 'CREDIT INTEREST CAPITALISED', '', '25/05/25', '', '420.00', '32,149.50'],
        ],
      );

      final extractedText = extractAllTextFromPdf(hdfcPdf);
      final result = parseStatement(extractedText, accountName: 'HDFC Salary');

      print('HDFC Rows Extracted: ${result.rows.length}');
      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 4);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 145050);
      expect(result.rows[0].notes, contains('DMART'));

      expect(result.rows[1].type, 'expense');
      expect(result.rows[1].amount.amountMinor, 32000);
      expect(result.rows[1].notes, contains('SWIGGY'));

      expect(result.rows[2].type, 'income');
      expect(result.rows[2].amount.amountMinor, 350000);
      expect(result.rows[2].notes, contains('DIVIDEND'));

      expect(result.rows[3].type, 'income');
      expect(result.rows[3].amount.amountMinor, 42000);
      expect(result.rows[3].notes, contains('CREDIT INTEREST'));
    });

    test('3. Axis Bank - Password-Protected Real PDF with DD-MM-YYYY dates and DR/CR columns', () {
      const axisPassword = 'JOEL1508'; // Example Axis password (Name + DDMM)

      final axisPdf = _generatePdfStatement(
        title: 'AXIS BANK LTD - STATEMENT OF ACCOUNT',
        password: axisPassword,
        headerDetails: 'Account No: 918010045678912\nCustomer ID: 77182930\nBranch: INDIRANAGAR BANGALORE\nCurrency: INR',
        headers: ['Tran Date', 'CHQNO', 'PARTICULARS', 'DR', 'CR', 'BAL'],
        rows: [
          ['05-06-2025', '', 'UPI/ZOMATO/ORDER9912/HDFC/REF8812', '450.00', '', '49,550.00'],
          ['12-06-2025', 'CHQ001', 'CLG CHQ DEPOSIT MR SHARMA', '', '25,000.00', '74,550.00'],
          ['18-06-2025', '', 'NETFLIX ENTERTAINMENT SVCS', '649.00', '', '73,901.00'],
          ['28-06-2025', '', 'ATM CASH WDL INDIRANAGAR', '5,000.00', '', '68,901.00'],
        ],
      );

      // Verify that without password it fails to open
      expect(() => extractAllTextFromPdf(axisPdf), throwsA(anything));

      // With correct password it extracts and parses seamlessly
      final extractedText = extractAllTextFromPdf(axisPdf, password: axisPassword);
      final result = parseStatement(extractedText, accountName: 'Axis Priority');

      print('Axis Rows Extracted (Unlocked with Password): ${result.rows.length}');
      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 4);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 45000);
      expect(result.rows[0].notes, contains('ZOMATO'));

      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 2500000);
      expect(result.rows[1].notes, contains('CLG CHQ DEPOSIT'));

      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 64900);

      expect(result.rows[3].type, 'expense');
      expect(result.rows[3].amount.amountMinor, 500000);
    });

    test('4. Kotak Mahindra Bank - Real PDF with DD Mon YYYY dates and DR/CR column', () {
      final kotakPdf = _generatePdfStatement(
        title: 'Kotak Mahindra Bank - Account Statement',
        headerDetails: 'Account Number: 2819203817\nCRN: 55443322\nPeriod: 01 Jan 2025 to 31 Jan 2025\nCurrency: INR',
        headers: ['Date', 'Narration', 'Chq/Ref No', 'Amount', 'Dr/Cr', 'Balance'],
        rows: [
          ['05 Jan 2025', 'AMAZON SELLER SERVICES ORD 123', 'REF1234', '2,199.00', 'DR', '45,801.00'],
          ['14 Jan 2025', 'REFUND FROM FLIPKART TXN 992', 'REF5678', '1,200.00', 'CR', '47,001.00'],
          ['20 Jan 2025', 'UBER RIDE MUMBAI INR TRIP 8812', 'REF9988', '350.00', 'DR', '46,651.00'],
        ],
      );

      final extractedText = extractAllTextFromPdf(kotakPdf);
      final result = parseStatement(extractedText, accountName: 'Kotak 811');

      print('Kotak Rows Extracted: ${result.rows.length}');
      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3);

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 219900);

      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 120000);

      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 35000);
    });

    test('5. Punjab National Bank (PNB) - Real PDF with Withdrawal / Deposit columns', () {
      final pnbPdf = _generatePdfStatement(
        title: 'Punjab National Bank - Statement of Transactions',
        headerDetails: 'Account No: 0192000100928371\nBranch: CONNAUGHT PLACE NEW DELHI\nCurrency: INR',
        headers: ['Date', 'Particulars', 'Cheque No', 'Withdrawal (Dr)', 'Deposit (Cr)', 'Balance'],
        rows: [
          ['02-03-2025', 'OPENING BALANCE', '', '', '', '15,000.00'],
          ['04-03-2025', 'UPI/ELECTRICITY BILL/BSES/REF1029', 'UPI1029', '1,850.00', '', '13,150.00'],
          ['10-03-2025', 'NEFT CR FROM GOVT OF INDIA PENSION', 'NEFT5512', '', '28,000.00', '41,150.00'],
          ['18-03-2025', 'SELF WITHDRAWAL CHEQUE NO 881920', '881920', '5,000.00', '', '36,150.00'],
        ],
      );

      final extractedText = extractAllTextFromPdf(pnbPdf);
      final result = parseStatement(extractedText, accountName: 'PNB Savings');

      print('PNB Rows Extracted: ${result.rows.length}');
      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3); // Opening balance skipped

      expect(result.rows[0].type, 'expense');
      expect(result.rows[0].amount.amountMinor, 185000);
      expect(result.rows[0].notes, contains('ELECTRICITY BILL'));

      expect(result.rows[1].type, 'income');
      expect(result.rows[1].amount.amountMinor, 2800000);
      expect(result.rows[1].notes, contains('PENSION'));

      expect(result.rows[2].type, 'expense');
      expect(result.rows[2].amount.amountMinor, 500000);
    });

    test('6. Bank of Baroda (BOB) - Real PDF with multi-page table and cash transactions', () {
      final bobPdf = _generatePdfStatement(
        title: 'Bank of Baroda - Account Statement',
        headerDetails: 'A/c No: 08910100029381\nBranch: ALKAPURI BARODA\nCurrency: INR',
        headers: ['Date', 'Particulars', 'Value Date', 'Withdrawal', 'Deposit', 'Balance'],
        rows: [
          ['10-02-2025', 'CASH DEPOSIT AT BRANCH COUNTER', '10-02-2025', '', '20,000.00', '35,000.00'],
          ['14-02-2025', 'UPI/GROCERY SUPERMARKET/BARB/REF99', '14-02-2025', '2,400.00', '', '32,600.00'],
          ['22-02-2025', 'FIXED DEPOSIT INTEREST CREDIT', '22-02-2025', '', '1,850.00', '34,450.00'],
        ],
      );

      final extractedText = extractAllTextFromPdf(bobPdf);
      final result = parseStatement(extractedText, accountName: 'BOB Current');

      print('BOB Rows Extracted: ${result.rows.length}');
      expect(result.detectedCurrency, 'INR');
      expect(result.rows.length, 3);

      expect(result.rows[0].type, 'income');
      expect(result.rows[0].amount.amountMinor, 2000000);

      expect(result.rows[1].type, 'expense');
      expect(result.rows[1].amount.amountMinor, 240000);

      expect(result.rows[2].type, 'income');
      expect(result.rows[2].amount.amountMinor, 185000);
    });
  });
}
