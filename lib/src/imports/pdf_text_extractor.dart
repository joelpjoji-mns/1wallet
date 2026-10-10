import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts all text from a PDF file's bytes, page by page.
///
/// Returns a list of strings, one per page. Pages whose text extraction
/// fails silently return an empty string for that page.
List<String> extractTextFromPdf(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
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
String extractAllTextFromPdf(Uint8List bytes) {
  return extractTextFromPdf(bytes).join('\n');
}
