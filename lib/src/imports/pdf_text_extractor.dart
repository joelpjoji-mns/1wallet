import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts all text from a PDF file's bytes, page by page.
///
/// If [password] is provided, attempts to open the encrypted PDF with it.
/// Throws if the document is password-protected and no or invalid password is provided.
List<String> extractTextFromPdf(Uint8List bytes, {String? password}) {
  final document = password != null && password.isNotEmpty
      ? PdfDocument(inputBytes: bytes, password: password)
      : PdfDocument(inputBytes: bytes);
  try {
    final pages = <String>[];
    for (var i = 0; i < document.pages.count; i++) {
      try {
        final text = PdfTextExtractor(document).extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        pages.add(text);
      } catch (_) {
        pages.add('');
      }
    }
    return pages;
  } finally {
    document.dispose();
  }
}

/// Extracts all text from a PDF as a single combined string.
String extractAllTextFromPdf(Uint8List bytes, {String? password}) {
  return extractTextFromPdf(bytes, password: password).join('\n');
}
