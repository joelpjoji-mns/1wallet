import '../data/ledger_models.dart';
import 'bank_profiles.dart';
import 'wallet_csv_parser.dart' show ParsedWalletCsvRow;

/// Result of parsing a PDF bank statement.
class StatementParseResult {
  const StatementParseResult({
    required this.profile,
    required this.rows,
    required this.skippedLines,
    required this.totalLines,
  });

  /// The bank profile that was used (auto-detected or manually chosen).
  final BankProfile profile;

  /// Successfully parsed transaction rows.
  final List<ParsedWalletCsvRow> rows;

  /// Number of lines that didn't match any pattern (noise).
  final int skippedLines;

  /// Total number of non-empty lines processed.
  final int totalLines;

  /// Rough confidence score: ratio of parsed rows to total lines.
  double get confidence =>
      totalLines == 0 ? 0.0 : rows.length / totalLines;
}

/// Parses raw extracted text from a PDF statement into structured rows.
///
/// If [profile] is null, auto-detection is attempted via [detectBankProfile].
/// The [accountName] is assigned to every parsed row (the user picks it in the
/// UI before confirming the import).
StatementParseResult parseStatement(
  String fullText, {
  BankProfile? profile,
  String accountName = '',
}) {
  final effectiveProfile = profile ?? detectBankProfile(fullText);
  final lines = fullText
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final rows = <ParsedWalletCsvRow>[];
  var skipped = 0;
  var rowNumber = 0;

  // Try to extract a fallback year from the statement header.
  int? fallbackYear;
  if (effectiveProfile.dateYear != null) {
    final yearMatch = effectiveProfile.dateYear!.firstMatch(fullText);
    if (yearMatch != null) {
      final yearStr = yearMatch.group(1);
      if (yearStr != null) fallbackYear = int.tryParse(yearStr);
    }
  }
  // Also try to find year from common statement period patterns.
  fallbackYear ??= _extractFallbackYear(fullText);

  for (final line in lines) {
    // Skip known noise lines.
    final shouldSkip = effectiveProfile.skipPatterns.any(
      (pattern) => pattern.hasMatch(line),
    );
    if (shouldSkip) {
      skipped++;
      continue;
    }

    final match = effectiveProfile.rowPattern.firstMatch(line);
    if (match == null) {
      skipped++;
      continue;
    }

    rowNumber++;

    // Extract fields from named groups.
    final dateStr = _tryGroup(match, 'date') ?? '';
    final desc = _tryGroup(match, 'desc')?.trim() ?? '';
    final debitStr = _tryGroup(match, 'debit');
    final creditStr = _tryGroup(match, 'credit');
    final amountStr = _tryGroup(match, 'amount');

    // Determine amount and type.
    final debitAmount = parseIndianAmount(debitStr);
    final creditAmount = parseIndianAmount(creditStr);
    final genericAmount = parseIndianAmount(amountStr);

    int? amountMinor;
    String type;

    if (debitAmount != null && debitAmount > 0) {
      amountMinor = debitAmount;
      type = 'expense';
    } else if (creditAmount != null && creditAmount > 0) {
      amountMinor = creditAmount;
      type = 'income';
    } else if (genericAmount != null) {
      amountMinor = genericAmount.abs();
      type = genericAmount < 0 ? 'expense' : 'income';
    } else {
      skipped++;
      continue;
    }

    final date = parseStatementDate(
      dateStr,
      effectiveProfile.dateParseHint,
      fallbackYear: fallbackYear,
    );

    rows.add(
      ParsedWalletCsvRow(
        rowNumber: rowNumber,
        accountName: accountName,
        amount: Money(
          amountMinor: amountMinor,
          currency: effectiveProfile.defaultCurrency,
        ),
        type: type,
        categoryName: null, // Category auto-matching happens in ledger_providers
        notes: desc.isEmpty ? null : desc,
        occurredAt: date,
      ),
    );
  }

  return StatementParseResult(
    profile: effectiveProfile,
    rows: rows,
    skippedLines: skipped,
    totalLines: lines.length,
  );
}

/// Tries to read a named group from the match; returns null if the group
/// doesn't exist or is empty.
String? _tryGroup(RegExpMatch match, String name) {
  try {
    final value = match.namedGroup(name);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  } catch (_) {
    return null;
  }
}

/// Tries to extract a year from common statement header patterns:
///   "Statement Period: 01/04/2025 to 30/04/2025"
///   "From 01-04-2025 To 30-04-2025"
///   "April 2025"
int? _extractFallbackYear(String text) {
  // Try "YYYY" from date ranges in the first ~500 chars.
  final header = text.substring(0, text.length < 500 ? text.length : 500);
  final yearMatch = RegExp(r'20\d{2}').firstMatch(header);
  if (yearMatch != null) {
    return int.tryParse(yearMatch.group(0)!);
  }
  return null;
}
