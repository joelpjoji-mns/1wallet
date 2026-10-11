import 'dart:math' as math;

import '../data/ledger_models.dart';
import 'wallet_csv_parser.dart' show ParsedWalletCsvRow;

/// The strategy that successfully extracted transactions.
enum ParsingStrategy {
  dateAnchoredLedger('Date-Anchored Ledger (Delta Verified)'),
  looseScanner('Loose Date & Column Scanner'),
  creditCard('Credit Card Statement Scanner'),
  tabularDelimited('Tabular Space-Aligned Scanner');

  const ParsingStrategy(this.label);
  final String label;
}

/// Result of parsing an account or credit card statement.
class StatementParseResult {
  const StatementParseResult({
    required this.rows,
    required this.skippedLines,
    required this.totalLines,
    this.detectedCurrency = 'INR',
    this.statementPeriod,
    this.strategy = ParsingStrategy.dateAnchoredLedger,
    this.diagnostics,
  });

  /// Successfully parsed transaction rows.
  final List<ParsedWalletCsvRow> rows;

  /// Number of non-empty lines that were skipped (noise, headers, footers).
  final int skippedLines;

  /// Total number of non-empty lines processed.
  final int totalLines;

  /// Currency detected from statement text (INR, USD, EUR, GBP, etc.).
  final String detectedCurrency;

  /// Detected statement period (e.g. "01/04/2025 to 30/04/2025").
  final String? statementPeriod;

  /// The parsing strategy that succeeded.
  final ParsingStrategy strategy;

  /// Diagnostic details if parsing failed or was unusual.
  final String? diagnostics;

  /// Confidence score: ratio of parsed rows to total lines.
  double get confidence => totalLines == 0 ? 0.0 : rows.length / totalLines;
}

/// Parses raw extracted text from any statement into structured rows.
/// Automatically executes a 4-pass self-recovery pipeline to adapt to any
/// statement or credit card layout without requiring institution-specific profiles.
StatementParseResult parseStatement(
  String fullText, {
  String accountName = '',
  String? defaultCurrency,
  bool forceRelaxedMode = false,
}) {
  final lines = fullText
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.isEmpty || fullText.trim().length < 20) {
    return StatementParseResult(
      rows: const [],
      skippedLines: 0,
      totalLines: 0,
      detectedCurrency: defaultCurrency ?? 'INR',
      diagnostics: 'The document appears to be empty or contains no readable text. '
          'If this is a scanned paper statement, image-only PDFs require OCR.',
    );
  }

  // 1. Detect Currency, Period, and Fallback Year
  final detectedCurrency = detectCurrency(
    fullText,
    fallback: defaultCurrency ?? 'INR',
  );
  final fallbackYear = extractFallbackYear(fullText);
  final statementPeriod = extractStatementPeriod(fullText);
  final initialBalance = _extractOpeningBalance(lines);

  final monthFirst = _detectMonthFirst(
    lines,
    currency: detectedCurrency,
  );

  List<ParsedWalletCsvRow> bestRows = [];
  ParsingStrategy bestStrategy = ParsingStrategy.dateAnchoredLedger;
  int skippedCount = 0;

  // ─────────────────────────────────────────────────────────────
  // PASS 1: Date-Anchored Table Block Strategy (Strict & Delta Verified)
  // ─────────────────────────────────────────────────────────────
  if (!forceRelaxedMode) {
    final rawBlocks = _chunkIntoDateBlocks(
      lines,
      fallbackYear: fallbackYear,
      monthFirst: monthFirst,
    );

    if (rawBlocks.isNotEmpty) {
      final candidates = <_ParsedBlockCandidate>[];
      for (final block in rawBlocks) {
        final candidate = _parseBlockCandidate(
          block,
          fallbackYear: fallbackYear,
          currency: detectedCurrency,
          monthFirst: monthFirst,
        );
        if (candidate != null) candidates.add(candidate);
      }

      if (candidates.isNotEmpty) {
        final pass1Rows = _resolveCandidateRows(
          candidates,
          accountName: accountName,
          currency: detectedCurrency,
          initialBalance: initialBalance,
        );

        if (pass1Rows.isNotEmpty) {
          bestRows = pass1Rows;
          bestStrategy = ParsingStrategy.dateAnchoredLedger;
          skippedCount = lines.length - bestRows.length;
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PASS 2: Loose Date Scanner (Self-Recovery for prefix tokens / channel codes)
  // ─────────────────────────────────────────────────────────────
  if (bestRows.isEmpty) {
    final pass2Rows = _parseViaLooseDateScanner(
      lines,
      accountName: accountName,
      currency: detectedCurrency,
      fallbackYear: fallbackYear,
      monthFirst: monthFirst,
    );

    if (pass2Rows.isNotEmpty) {
      bestRows = pass2Rows;
      bestStrategy = ParsingStrategy.looseScanner;
      skippedCount = lines.length - bestRows.length;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PASS 3: Credit Card Statement Scanner (Self-Recovery for non-balance card bills)
  // ─────────────────────────────────────────────────────────────
  if (bestRows.isEmpty) {
    final pass3Rows = _parseViaCreditCardScanner(
      lines,
      accountName: accountName,
      currency: detectedCurrency,
      fallbackYear: fallbackYear,
      monthFirst: monthFirst,
    );

    if (pass3Rows.isNotEmpty) {
      bestRows = pass3Rows;
      bestStrategy = ParsingStrategy.creditCard;
      skippedCount = lines.length - bestRows.length;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PASS 4: Tabular Multi-Space Delimited Scanner
  // ─────────────────────────────────────────────────────────────
  if (bestRows.isEmpty) {
    final pass4Rows = _parseViaTabularDelimiter(
      lines,
      accountName: accountName,
      currency: detectedCurrency,
      fallbackYear: fallbackYear,
      monthFirst: monthFirst,
    );

    if (pass4Rows.isNotEmpty) {
      bestRows = pass4Rows;
      bestStrategy = ParsingStrategy.tabularDelimited;
      skippedCount = lines.length - bestRows.length;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Self-Recovery Diagnostic Report if all passes yielded 0
  // ─────────────────────────────────────────────────────────────
  String? diagnostics;
  if (bestRows.isEmpty) {
    diagnostics = _generateDiagnostics(fullText, lines);
  }

  return StatementParseResult(
    rows: bestRows,
    skippedLines: skippedCount,
    totalLines: lines.length,
    detectedCurrency: detectedCurrency,
    statementPeriod: statementPeriod,
    strategy: bestStrategy,
    diagnostics: diagnostics,
  );
}

// ─────────────────────────────────────────────────────────────
//  Currency & Amount Parsing
// ─────────────────────────────────────────────────────────────

/// Parses any formatted monetary amount string (e.g. "1,23,456.78" or "12,345.50" or "45.00")
/// into integer minor units (e.g. cents/paise).
int? parseAmountMinor(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) return null;
  final parsed = double.tryParse(cleaned);
  if (parsed == null) return null;
  return (parsed * 100).round();
}

const _validCurrencies = {
  'INR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'SGD', 'AED', 'JPY', 'CHF', 'NZD',
};

String detectCurrency(String text, {String fallback = 'INR'}) {
  final headerMatch = RegExp(
    r'(?:Account\s+)?Currency\s*[:\-]?\s*([A-Za-z]{3})',
    caseSensitive: false,
  ).firstMatch(text);
  if (headerMatch != null) {
    final code = headerMatch.group(1)!.toUpperCase();
    if (_validCurrencies.contains(code)) return code;
  }

  final counts = <String, int>{};
  void count(String curr, RegExp regex) {
    final matches = regex.allMatches(text).length;
    if (matches > 0) counts[curr] = (counts[curr] ?? 0) + matches;
  }

  count('INR', RegExp(r'₹|\bINR\b|\bRs\.?\b', caseSensitive: false));
  count('USD', RegExp(r'\$|\bUSD\b', caseSensitive: false));
  count('EUR', RegExp(r'€|\bEUR\b', caseSensitive: false));
  count('GBP', RegExp(r'£|\bGBP\b', caseSensitive: false));
  count('CAD', RegExp(r'\bCAD\b', caseSensitive: false));
  count('AUD', RegExp(r'\bAUD\b', caseSensitive: false));
  count('SGD', RegExp(r'\bSGD\b', caseSensitive: false));
  count('AED', RegExp(r'\bAED\b', caseSensitive: false));

  if (counts.isEmpty) return fallback;

  var best = fallback;
  var maxCount = 0;
  counts.forEach((curr, cnt) {
    if (cnt > maxCount) {
      maxCount = cnt;
      best = curr;
    }
  });
  return best;
}

int? extractFallbackYear(String text) {
  final head = text.substring(0, math.min(1000, text.length));
  final match = RegExp(
    r'(?:Period|From|To|Date)[:\s].*?\b(20\d{2})\b',
    caseSensitive: false,
  ).firstMatch(head);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  final anyYear = RegExp(r'\b(20\d{2})\b').firstMatch(head);
  if (anyYear != null) {
    return int.tryParse(anyYear.group(1)!);
  }
  return DateTime.now().year;
}

String? extractStatementPeriod(String text) {
  final head = text.substring(0, math.min(1000, text.length));
  final match = RegExp(
    r'(?:Statement\s+Period|Period|From)\s*[:\-]?\s*(\d{1,2}[/\-.][\w]+[/\-.]\d{2,4}\s*(?:to|-)\s*\d{1,2}[/\-.][\w]+[/\-.]\d{2,4})',
    caseSensitive: false,
  ).firstMatch(head);
  return match?.group(1);
}

int? _extractOpeningBalance(List<String> lines) {
  for (final line in lines) {
    if (RegExp(r'\b(?:OPENING\s+BALANCE|BROUGHT\s+FORWARD|B/F)\b', caseSensitive: false).hasMatch(line)) {
      final matches = RegExp(r'(?<!\d)([+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2})(?!\d)').allMatches(line);
      if (matches.isNotEmpty) {
        final parsed = parseAmountMinor(matches.last.group(1));
        if (parsed != null && parsed > 0) return parsed;
      }
    }
  }
  return null;
}

bool _detectMonthFirst(List<String> lines, {String? currency}) {
  var sawP1Over12 = false;
  var sawP2Over12 = false;

  for (final line in lines) {
    final matches = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').allMatches(line);
    for (final m in matches) {
      final p1 = int.tryParse(m.group(1)!);
      final p2 = int.tryParse(m.group(2)!);
      if (p1 != null && p2 != null) {
        if (p1 > 12) sawP1Over12 = true;
        if (p2 > 12) sawP2Over12 = true;
      }
    }
  }

  if (sawP2Over12) return true; // Proves MM/DD/YYYY
  if (sawP1Over12) return false; // Proves DD/MM/YYYY

  if (currency == 'USD') {
    return true;
  }
  return false;
}

// ─────────────────────────────────────────────────────────────
//  Date Patterns & Block Chunking (Strategy 1)
// ─────────────────────────────────────────────────────────────

final _monthMap = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'june': 6,
  'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
};

final _datePrefixRegex = RegExp(
  r'^\s*(?:[A-Za-z0-9_]{1,10}\s+)?(?:\d{1,4}[.)]\s+)?'
  r'(?:'
  r'(?<d1>\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})'
  r'|'
  r'(?<d2>\d{1,2}[\s\-](?:[A-Za-z]{3,9})[\s\-]\d{2,4})'
  r'|'
  r'(?<d3>(?:[A-Za-z]{3,9})\s+\d{1,2},?\s+\d{2,4})'
  r'|'
  r'(?<d4>\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2})'
  r'|'
  r'(?<d5>\d{1,2}[\s\-](?:[A-Za-z]{3,9}))'
  r')'
  r'(?:\s|$)',
  caseSensitive: false,
);

class _DateBlock {
  _DateBlock({required this.dateStr, required this.firstLine, required this.lines});
  final String dateStr;
  final String firstLine;
  final List<String> lines;
}

bool _blockHasMonetaryAmount(List<String> lines) {
  final combined = lines.join(' ');
  return RegExp(r'(?<!\d)([+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2})(?!\d)').hasMatch(combined);
}

List<_DateBlock> _chunkIntoDateBlocks(
  List<String> lines, {
  int? fallbackYear,
  bool monthFirst = false,
}) {
  final blocks = <_DateBlock>[];
  _DateBlock? current;

  for (final line in lines) {
    if (_isNoiseOrHeaderLine(line)) continue;

    final match = _datePrefixRegex.firstMatch(line);
    if (match != null) {
      final dateStr = (match.namedGroup('d1') ??
              match.namedGroup('d2') ??
              match.namedGroup('d3') ??
              match.namedGroup('d4') ??
              match.namedGroup('d5')) ??
          '';

      final parsed = _parseAnyDate(dateStr, fallbackYear: fallbackYear, monthFirst: monthFirst);
      if (parsed != null) {
        // If current block exists and doesn't have any monetary amounts yet,
        // this subsequent date is almost certainly a Value Date in the same row.
        if (current != null && !_blockHasMonetaryAmount(current.lines)) {
          current.lines.add(line);
          continue;
        }

        if (current != null) blocks.add(current);
        current = _DateBlock(
          dateStr: dateStr,
          firstLine: line,
          lines: [line],
        );
        continue;
      }
    }

    if (current != null) current.lines.add(line);
  }

  if (current != null) blocks.add(current);
  return blocks;
}

bool _isNoiseOrHeaderLine(String line) {
  // Page number footer
  if (RegExp(r'^Page\s+\d+(\s+of\s+\d+)?$', caseSensitive: false).hasMatch(line)) {
    return true;
  }
  // Standalone summary card lines (like "Opening Balance: $5,000" or "Closing Balance: $4,250")
  if (RegExp(r'^(?:Opening|Closing)\s+Balance\s*:\s*[$₹€£]?[\d,]+(?:\.\d{2})?', caseSensitive: false).hasMatch(line)) {
    return true;
  }
  // Table headers
  if (RegExp(r'\bDate\b', caseSensitive: false).hasMatch(line) &&
      (RegExp(r'\b(?:Narration|Particulars|Description|Details)\b', caseSensitive: false).hasMatch(line) ||
          RegExp(r'\b(?:Withdrawal|Debit|Deposit|Credit|Balance)\b', caseSensitive: false).hasMatch(line))) {
    return true;
  }
  if (RegExp(r'^(?:Statement\s+of\s+Account|Account\s+Number|Customer\s+ID|IFSC\s+Code|Branch\s*:)',
          caseSensitive: false)
      .hasMatch(line)) {
    return true;
  }
  return false;
}

DateTime? _parseAnyDate(
  String raw, {
  int? fallbackYear,
  bool monthFirst = false,
}) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;

  final m1 = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(cleaned);
  if (m1 != null) {
    var p1 = int.tryParse(m1.group(1)!);
    var p2 = int.tryParse(m1.group(2)!);
    var y = int.tryParse(m1.group(3)!);
    if (p1 == null || p2 == null || y == null) return null;
    if (y < 100) y += 2000;

    int d;
    int m;
    if (p1 > 12) {
      d = p1;
      m = p2;
    } else if (p2 > 12) {
      d = p2;
      m = p1;
    } else if (monthFirst) {
      m = p1;
      d = p2;
    } else {
      d = p1;
      m = p2;
    }

    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  final m4 = RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})$').firstMatch(cleaned);
  if (m4 != null) {
    final y = int.tryParse(m4.group(1)!);
    final m = int.tryParse(m4.group(2)!);
    final d = int.tryParse(m4.group(3)!);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  final m2 = RegExp(r'^(\d{1,2})[\s\-]([A-Za-z]{3,9})[\s\-](\d{2,4})$').firstMatch(cleaned);
  if (m2 != null) {
    final d = int.tryParse(m2.group(1)!);
    final mStr = m2.group(2)!.toLowerCase();
    var y = int.tryParse(m2.group(3)!);
    final m = _monthMap[mStr];
    if (d == null || m == null || y == null) return null;
    if (y < 100) y += 2000;
    if (d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  final m3 = RegExp(r'^([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{2,4})$').firstMatch(cleaned);
  if (m3 != null) {
    final mStr = m3.group(1)!.toLowerCase();
    final d = int.tryParse(m3.group(2)!);
    var y = int.tryParse(m3.group(3)!);
    final m = _monthMap[mStr];
    if (d == null || m == null || y == null) return null;
    if (y < 100) y += 2000;
    if (d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  final m5 = RegExp(r'^(\d{1,2})[\s\-]([A-Za-z]{3,9})$').firstMatch(cleaned);
  if (m5 != null) {
    final d = int.tryParse(m5.group(1)!);
    final mStr = m5.group(2)!.toLowerCase();
    final m = _monthMap[mStr];
    if (d == null || m == null) return null;
    final y = fallbackYear ?? DateTime.now().year;
    return DateTime(y, m, d);
  }

  return null;
}

// ─────────────────────────────────────────────────────────────
//  Block Candidate Extraction & Balance Math (Strategy 1)
// ─────────────────────────────────────────────────────────────

class _ExtractedAmount {
  const _ExtractedAmount({required this.raw, required this.minor, required this.isNegative});
  final String raw;
  final int minor;
  final bool isNegative;
}

class _ParsedBlockCandidate {
  _ParsedBlockCandidate({
    required this.date,
    required this.combinedText,
    required this.amounts,
    required this.notes,
    this.hasCrIndicator = false,
    this.hasDrIndicator = false,
  });

  final DateTime date;
  final String combinedText;
  final List<_ExtractedAmount> amounts;
  final String notes;
  final bool hasCrIndicator;
  final bool hasDrIndicator;

  int? get runningBalance => amounts.length >= 2 ? amounts.last.minor : null;
}

_ParsedBlockCandidate? _parseBlockCandidate(
  _DateBlock block, {
  int? fallbackYear,
  required String currency,
  bool monthFirst = false,
}) {
  final date = _parseAnyDate(block.dateStr, fallbackYear: fallbackYear, monthFirst: monthFirst);
  if (date == null) return null;

  final combined = block.lines.join(' ');
  final amountMatches = RegExp(
    r'(?<!\d)([+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2})(?!\d)',
  ).allMatches(combined);

  if (amountMatches.isEmpty) return null;

  final extracted = <_ExtractedAmount>[];
  for (final m in amountMatches) {
    final raw = m.group(1)!;
    final parsed = parseAmountMinor(raw);
    if (parsed != null && parsed != 0) {
      extracted.add(
        _ExtractedAmount(
          raw: raw,
          minor: parsed.abs(),
          isNegative: parsed < 0 || raw.startsWith('-'),
        ),
      );
    }
  }

  if (extracted.isEmpty) return null;

  final hasCr = RegExp(r'\b(?:CR|Cr)\b|(?:\s*/CR\b)|(?:\bCREDIT\b(?!(\s+CARD)))|(?:\bDEP(?:OSIT)?\b)',
          caseSensitive: false)
      .hasMatch(combined);

  final hasDr = RegExp(r'\b(?:DR|Dr)\b|(?:\s*/DR\b)|(?:\bDEBIT\b)|(?:\bWDL\b)|(?:\bWITHDRAWAL\b)',
          caseSensitive: false)
      .hasMatch(combined);

  final cleanNotes = _cleanNotes(combined, block.dateStr, extracted);

  return _ParsedBlockCandidate(
    date: date,
    combinedText: combined,
    amounts: extracted,
    notes: cleanNotes,
    hasCrIndicator: hasCr,
    hasDrIndicator: hasDr,
  );
}

String _cleanNotes(String combined, String dateStr, List<_ExtractedAmount> amounts) {
  var text = combined;
  text = text.replaceFirst(dateStr, ' ');
  for (final a in amounts) {
    text = text.replaceFirst(a.raw, ' ');
  }
  // Remove remaining dates (like Value Date)
  text = text.replaceAll(RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b'), ' ');
  text = text.replaceAll(RegExp(r'\b(?:CR|DR|Cr|Dr)\b'), ' ');
  text = text.replaceAll(RegExp(r'\b(?:Chq/Ref\s*No|Value\s*Dt)\b', caseSensitive: false), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? 'Transaction' : text;
}

List<ParsedWalletCsvRow> _resolveCandidateRows(
  List<_ParsedBlockCandidate> candidates, {
  required String accountName,
  required String currency,
  int? initialBalance,
}) {
  final rows = <ParsedWalletCsvRow>[];
  if (candidates.isEmpty) return rows;

  var isReverseChronological = false;
  if (candidates.length >= 2) {
    if (candidates.first.date.isAfter(candidates.last.date)) {
      isReverseChronological = true;
    }
  }

  var rowNumber = 0;

  for (var i = 0; i < candidates.length; i++) {
    final curr = candidates[i];

    // If this entry is purely an Opening Balance / Brought Forward entry without an actual transaction
    final isOpeningBalance = RegExp(r'\b(?:OPENING\s+BALANCE|BALANCE\s+B/F|BROUGHT\s+FORWARD|BAL\s+B/F)\b', caseSensitive: false)
            .hasMatch(curr.notes) ||
        RegExp(r'\b(?:OPENING\s+BALANCE|BALANCE\s+B/F|BROUGHT\s+FORWARD|BAL\s+B/F)\b', caseSensitive: false)
            .hasMatch(curr.combinedText);

    if (isOpeningBalance && (curr.amounts.length <= 1 || curr.runningBalance != null)) {
      if (initialBalance == null && curr.amounts.isNotEmpty) {
        initialBalance = curr.amounts.last.minor;
      }
      continue;
    }

    rowNumber++;

    int amountMinor;
    String type;
    bool resolved = false;

    // ── Mathematical Balance Delta ──
    if (curr.runningBalance != null) {
      if (!isReverseChronological) {
        int? previousBalance;
        if (i > 0 && candidates[i - 1].runningBalance != null) {
          previousBalance = candidates[i - 1].runningBalance;
        } else if (i == 0 && initialBalance != null) {
          previousBalance = initialBalance;
        }

        if (previousBalance != null) {
          final delta = curr.runningBalance! - previousBalance;
          if (delta != 0) {
            final targetMinor = delta.abs();
            final matched = curr.amounts
                .take(curr.amounts.length - 1)
                .firstWhere(
                  (a) => a.minor == targetMinor,
                  orElse: () => _ExtractedAmount(raw: '', minor: targetMinor, isNegative: delta < 0),
                );

            amountMinor = matched.minor;
            type = delta > 0 ? 'income' : 'expense';
            resolved = true;
            rows.add(_buildRow(rowNumber, accountName, amountMinor, type, curr.notes, curr.date, currency));
            continue;
          }
        }
      } else {
        if (i < candidates.length - 1 && candidates[i + 1].runningBalance != null) {
          final earlierBal = candidates[i + 1].runningBalance!;
          final delta = curr.runningBalance! - earlierBal;
          if (delta != 0) {
            final targetMinor = delta.abs();
            final matched = curr.amounts
                .take(curr.amounts.length - 1)
                .firstWhere(
                  (a) => a.minor == targetMinor,
                  orElse: () => _ExtractedAmount(raw: '', minor: targetMinor, isNegative: delta < 0),
                );

            amountMinor = matched.minor;
            type = delta > 0 ? 'income' : 'expense';
            resolved = true;
            rows.add(_buildRow(rowNumber, accountName, amountMinor, type, curr.notes, curr.date, currency));
            continue;
          }
        }
      }
    }

    // ── Fallback when Balance Delta is unavailable ──
    if (!resolved) {
      if (curr.amounts.length >= 3) {
        final wdl = curr.amounts[0].minor;
        final dep = curr.amounts[1].minor;
        if (dep > 0 && (wdl == 0 || curr.hasCrIndicator)) {
          amountMinor = dep;
          type = 'income';
        } else {
          amountMinor = wdl;
          type = 'expense';
        }
      } else if (curr.amounts.length == 2) {
        final amt = curr.amounts[0];
        amountMinor = amt.minor;
        if (amt.isNegative) {
          type = 'expense';
        } else if (curr.hasCrIndicator && !curr.hasDrIndicator) {
          type = 'income';
        } else if (curr.hasDrIndicator && !curr.hasCrIndicator) {
          type = 'expense';
        } else {
          type = _guessTypeFromNotes(curr.notes);
        }
      } else {
        final amt = curr.amounts[0];
        amountMinor = amt.minor;
        if (amt.isNegative) {
          type = 'expense';
        } else if (curr.hasCrIndicator && !curr.hasDrIndicator) {
          type = 'income';
        } else if (curr.hasDrIndicator && !curr.hasCrIndicator) {
          type = 'expense';
        } else {
          type = _guessTypeFromNotes(curr.notes);
        }
      }

      rows.add(_buildRow(rowNumber, accountName, amountMinor, type, curr.notes, curr.date, currency));
    }
  }

  return rows;
}

// ─────────────────────────────────────────────────────────────
//  PASS 2: Loose Date Scanner (Self-Recovery for Token-Prefixed Rows)
// ─────────────────────────────────────────────────────────────

final _anywhereDateRegex = RegExp(
  r'\b(?:\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}[\s\-][A-Za-z]{3,9}[\s\-]\d{2,4})\b',
);

List<ParsedWalletCsvRow> _parseViaLooseDateScanner(
  List<String> lines, {
  required String accountName,
  required String currency,
  int? fallbackYear,
  bool monthFirst = false,
}) {
  final rows = <ParsedWalletCsvRow>[];
  var rowNumber = 0;

  for (final line in lines) {
    if (_isNoiseOrHeaderLine(line)) continue;

    final dateMatch = _anywhereDateRegex.firstMatch(line);
    if (dateMatch == null) continue;

    final date = _parseAnyDate(dateMatch.group(0)!, fallbackYear: fallbackYear, monthFirst: monthFirst);
    if (date == null) continue;

    final amountMatches = RegExp(
      r'(?<!\d)([+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2})(?!\d)',
    ).allMatches(line);

    if (amountMatches.isEmpty) continue;

    final amounts = <_ExtractedAmount>[];
    for (final m in amountMatches) {
      final raw = m.group(1)!;
      final parsed = parseAmountMinor(raw);
      if (parsed != null && parsed != 0) {
        amounts.add(_ExtractedAmount(raw: raw, minor: parsed.abs(), isNegative: parsed < 0 || raw.startsWith('-')));
      }
    }

    if (amounts.isEmpty) continue;

    rowNumber++;
    final amt = amounts.first;
    final cleanNotes = _cleanNotes(line, dateMatch.group(0)!, amounts);

    final hasCr = RegExp(r'\b(?:CR|Cr|Credit|Deposit|Refund)\b', caseSensitive: false).hasMatch(line);
    final hasDr = RegExp(r'\b(?:DR|Dr|Debit|Withdrawal)\b', caseSensitive: false).hasMatch(line);

    String type;
    if (amt.isNegative) {
      type = 'expense';
    } else if (hasCr && !hasDr) {
      type = 'income';
    } else if (hasDr && !hasCr) {
      type = 'expense';
    } else {
      type = _guessTypeFromNotes(cleanNotes);
    }

    rows.add(_buildRow(rowNumber, accountName, amt.minor, type, cleanNotes, date, currency));
  }

  return rows;
}

// ─────────────────────────────────────────────────────────────
//  PASS 3: Credit Card Statement Scanner (Self-Recovery for Cards)
// ─────────────────────────────────────────────────────────────

List<ParsedWalletCsvRow> _parseViaCreditCardScanner(
  List<String> lines, {
  required String accountName,
  required String currency,
  int? fallbackYear,
  bool monthFirst = false,
}) {
  final rows = <ParsedWalletCsvRow>[];
  var rowNumber = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_isNoiseOrHeaderLine(line)) continue;

    final dateMatch = _anywhereDateRegex.firstMatch(line);
    if (dateMatch == null) continue;

    final date = _parseAnyDate(dateMatch.group(0)!, fallbackYear: fallbackYear, monthFirst: monthFirst);
    if (date == null) continue;

    var combined = line;
    // Check if amount is on the next line (common in credit card layouts)
    if (!RegExp(r'\d+\.\d{2}').hasMatch(combined) && i + 1 < lines.length) {
      combined = '$line ${lines[i + 1]}';
    }

    final amountMatches = RegExp(
      r'(?<!\d)([+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2})(?!\d)',
    ).allMatches(combined);

    if (amountMatches.isEmpty) continue;

    final rawAmount = amountMatches.first.group(1)!;
    final parsed = parseAmountMinor(rawAmount);
    if (parsed == null || parsed == 0) continue;

    rowNumber++;
    final isCredit = RegExp(
      r'\b(?:CR|Cr|CREDIT|REFUND|PAYMENT\s+RECEIVED|AUTOPAY|THANK\s+YOU)\b',
      caseSensitive: false,
    ).hasMatch(combined);

    final cleanNotes = _cleanNotes(
      combined,
      dateMatch.group(0)!,
      [_ExtractedAmount(raw: rawAmount, minor: parsed.abs(), isNegative: parsed < 0)],
    );

    final type = (parsed < 0 || isCredit) ? 'income' : 'expense';

    rows.add(_buildRow(rowNumber, accountName, parsed.abs(), type, cleanNotes, date, currency));
  }

  return rows;
}

// ─────────────────────────────────────────────────────────────
//  PASS 4: Tabular Multi-Space Delimited Scanner
// ─────────────────────────────────────────────────────────────

List<ParsedWalletCsvRow> _parseViaTabularDelimiter(
  List<String> lines, {
  required String accountName,
  required String currency,
  int? fallbackYear,
  bool monthFirst = false,
}) {
  final rows = <ParsedWalletCsvRow>[];
  var rowNumber = 0;

  for (final line in lines) {
    if (_isNoiseOrHeaderLine(line)) continue;

    // Split on 2 or more spaces or tabs
    final parts = line.split(RegExp(r'\s{2,}|\t')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length < 3) continue;

    DateTime? date;
    int? amountMinor;
    String? narration;
    String type = 'expense';

    for (final part in parts) {
      if (date == null) {
        final d = _parseAnyDate(part, fallbackYear: fallbackYear, monthFirst: monthFirst);
        if (d != null) {
          date = d;
          continue;
        }
      }

      final amtMatch = RegExp(r'(?<!\d)([+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2})(?!\d)').firstMatch(part);
      if (amtMatch != null && amountMinor == null) {
        final p = parseAmountMinor(amtMatch.group(1)!);
        if (p != null && p != 0) {
          amountMinor = p.abs();
          if (p < 0 || part.toUpperCase().contains('CR')) {
            type = 'income';
          }
          continue;
        }
      }

      if (part.length > 3 && !RegExp(r'^\d+$').hasMatch(part) && narration == null) {
        narration = part;
      }
    }

    if (date != null && amountMinor != null) {
      rowNumber++;
      rows.add(_buildRow(rowNumber, accountName, amountMinor, type, narration ?? 'Transaction', date, currency));
    }
  }

  return rows;
}

// ─────────────────────────────────────────────────────────────
//  Diagnostics Generator
// ─────────────────────────────────────────────────────────────

String _generateDiagnostics(String fullText, List<String> lines) {
  if (fullText.trim().length < 100) {
    return 'The PDF contains very little readable text (${fullText.trim().length} characters). '
        'This usually indicates a scanned physical document or an image. Scanned PDFs require OCR text recognition.';
  }

  final datesFound = _anywhereDateRegex.allMatches(fullText).length;
  final amountsFound = RegExp(r'(?<!\d)[+\-]?(?:\d{1,3}(?:,\d{2,3})*|\d+)\.\d{2}(?!\d)')
      .allMatches(fullText)
      .length;

  if (datesFound == 0) {
    return 'Text was extracted (${lines.length} lines), but no valid transaction dates '
        '(e.g. DD/MM/YYYY, DD-Mon-YYYY) were detected.';
  }

  if (amountsFound == 0) {
    return 'Found $datesFound date(s), but no valid monetary amounts with 2 decimals (e.g. 50.00) '
        'could be identified.';
  }

  return 'Detected $datesFound dates and $amountsFound numbers, but they could not be correlated '
      'into structured transactions. Try checking if the PDF text is grouped into non-standard table columns.';
}

String _guessTypeFromNotes(String notes) {
  final upper = notes.toUpperCase();
  if (upper.contains('SALARY') ||
      upper.contains('DIVIDEND') ||
      upper.contains('INTEREST') ||
      upper.contains('REFUND') ||
      upper.contains('CREDITED') ||
      upper.contains('DEPOSIT') ||
      upper.contains('PAYROLL') ||
      upper.contains('DIRECT DEP')) {
    return 'income';
  }
  return 'expense';
}

ParsedWalletCsvRow _buildRow(
  int rowNumber,
  String accountName,
  int amountMinor,
  String type,
  String notes,
  DateTime date,
  String currency,
) {
  return ParsedWalletCsvRow(
    rowNumber: rowNumber,
    accountName: accountName,
    amount: Money(
      amountMinor: amountMinor,
      currency: currency,
    ),
    type: type,
    categoryName: null,
    notes: notes,
    occurredAt: date,
  );
}
