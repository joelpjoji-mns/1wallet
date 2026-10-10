import 'dart:math' as math;

/// A profile describing how a specific bank formats its PDF statement.
///
/// Each profile contains regex patterns and section markers used to
/// extract structured transaction rows from raw text.
class BankProfile {
  const BankProfile({
    required this.id,
    required this.name,
    required this.country,
    required this.rowPattern,
    this.dateYear,
    this.debitSectionMarkers = const [],
    this.creditSectionMarkers = const [],
    this.identifyPatterns = const [],
    this.skipPatterns = const [],
    this.dateParseHint = DateParseHint.ddMmYyyy,
    this.defaultCurrency = 'INR',
  });

  final String id;
  final String name;
  final String country;

  /// Regex to match a single transaction row.
  ///
  /// Named groups expected:
  /// - `date` — transaction date string
  /// - `desc` — description / narration
  /// - `amount` — numeric amount (may include commas)
  ///
  /// Optional named groups:
  /// - `debit` — debit amount (if separate columns)
  /// - `credit` — credit amount (if separate columns)
  /// - `balance` — running balance (ignored but helps pattern matching)
  final RegExp rowPattern;

  /// If the statement only prints DD/MM or DD-MM (no year), this regex
  /// extracts the year from a header like "Statement Period: 01/04/2025 to 30/04/2025".
  final RegExp? dateYear;

  /// Section header text(s) that indicate rows below are debits.
  final List<String> debitSectionMarkers;

  /// Section header text(s) that indicate rows below are credits.
  final List<String> creditSectionMarkers;

  /// Regex patterns that, if found in the full text, identify this profile.
  final List<RegExp> identifyPatterns;

  /// Line patterns to skip (headers, footers, page numbers, etc.).
  final List<RegExp> skipPatterns;

  /// How to parse the date string extracted by [rowPattern].
  final DateParseHint dateParseHint;

  /// Fallback currency if none detected.
  final String defaultCurrency;
}

enum DateParseHint {
  /// DD/MM/YYYY or DD-MM-YYYY
  ddMmYyyy,

  /// DD/MM/YY or DD-MM-YY
  ddMmYy,

  /// DD MMM YYYY (e.g. "15 Apr 2025")
  ddMmmYyyy,

  /// DD-MMM-YY (e.g. "15-Apr-25")
  ddMmmYy,

  /// DD MMM (no year, must infer from statement header)
  ddMmm,
}

// ─────────────────────────────────────────────────────────────
//  Indian Bank Profiles
// ─────────────────────────────────────────────────────────────

/// State Bank of India — savings/current account statement.
///
/// Format: DD/MM/YYYY | Narration | Chq/Ref No | Debit | Credit | Balance
final sbiProfile = BankProfile(
  id: 'sbi',
  name: 'State Bank of India',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'State\s+Bank\s+of\s+India', caseSensitive: false),
    RegExp(r'SBI', caseSensitive: false),
    RegExp(r'Account\s+Statement.*SBI', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
    RegExp(r'Page\s+\d+', caseSensitive: false),
    RegExp(r'Txn\s+Date', caseSensitive: false),
  ],
);

/// HDFC Bank — savings account statement.
///
/// Format: DD/MM/YY | Narration | Chq/Ref Number | Value Dt | Withdrawal Amt | Deposit Amt | Closing Balance
final hdfcProfile = BankProfile(
  id: 'hdfc',
  name: 'HDFC Bank',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'HDFC\s+BANK', caseSensitive: false),
    RegExp(r'hdfc\s*bank', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:\d{2}[/\-]\d{2}[/\-]\d{2,4}\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
    RegExp(r'Page\s+\d+', caseSensitive: false),
    RegExp(r'Date\s+Narration', caseSensitive: false),
  ],
);

/// ICICI Bank — savings account statement.
///
/// Format: DD/MM/YYYY | Mode | Particulars | Deposits | Withdrawals | Balance
final iciciProfile = BankProfile(
  id: 'icici',
  name: 'ICICI Bank',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'ICICI\s+Bank', caseSensitive: false),
    RegExp(r'icicibank', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?:\w+\s+)?'
    r'(?<desc>.+?)\s{2,}'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
    RegExp(r'Date\s+Mode', caseSensitive: false),
  ],
);

/// Axis Bank — savings account statement.
///
/// Format: DD-MM-YYYY | Particulars | Chq/Ref No | Debit | Credit | Balance
final axisProfile = BankProfile(
  id: 'axis',
  name: 'Axis Bank',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'Axis\s+Bank', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[-/]\d{2}[-/]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
    RegExp(r'Tran\s+Date', caseSensitive: false),
  ],
);

/// Kotak Mahindra Bank — savings account statement.
///
/// Format: DD Mon YYYY | Description | Chq / Ref No. | Debit | Credit | Balance
final kotakProfile = BankProfile(
  id: 'kotak',
  name: 'Kotak Mahindra Bank',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'Kotak\s+Mahindra', caseSensitive: false),
    RegExp(r'kotak', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}\s+\w{3}\s+\d{4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
    RegExp(r'Date\s+Description', caseSensitive: false),
  ],
);

/// Punjab National Bank — savings account statement.
final pnbProfile = BankProfile(
  id: 'pnb',
  name: 'Punjab National Bank',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'Punjab\s+National\s+Bank', caseSensitive: false),
    RegExp(r'PNB', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
  ],
);

/// Bank of Baroda — savings account statement.
final bobProfile = BankProfile(
  id: 'bob',
  name: 'Bank of Baroda',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'Bank\s+of\s+Baroda', caseSensitive: false),
    RegExp(r'BOB', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
  ],
);

/// Indian Overseas Bank — savings account statement.
final iobProfile = BankProfile(
  id: 'iob',
  name: 'Indian Overseas Bank',
  country: 'IN',
  identifyPatterns: [
    RegExp(r'Indian\s+Overseas\s+Bank', caseSensitive: false),
    RegExp(r'IOB', caseSensitive: false),
  ],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
  ],
);

/// A generic fallback profile that tries common Indian statement layouts.
///
/// Works for most banks that follow the standard format:
///   Date | Description | ... | Debit | Credit | Balance
final genericIndianProfile = BankProfile(
  id: 'generic_in',
  name: 'Generic Indian Bank',
  country: 'IN',
  identifyPatterns: [],
  rowPattern: RegExp(
    r'(?<date>\d{2}[/\-]\d{2}[/\-]\d{2,4})\s+'
    r'(?<desc>.+?)\s{2,}'
    r'(?:[\w/]*\s+)?'
    r'(?:(?<debit>[\d,]+\.\d{2})\s+)?'
    r'(?:(?<credit>[\d,]+\.\d{2})\s+)?'
    r'(?<balance>[\d,]+\.\d{2})',
  ),
  dateParseHint: DateParseHint.ddMmYyyy,
  skipPatterns: [
    RegExp(r'(Opening|Closing)\s+Balance', caseSensitive: false),
    RegExp(r'Page\s+\d+', caseSensitive: false),
    RegExp(r'^\s*$'),
  ],
);

/// All known bank profiles, ordered from most specific to generic fallback.
final List<BankProfile> allBankProfiles = [
  sbiProfile,
  hdfcProfile,
  iciciProfile,
  axisProfile,
  kotakProfile,
  pnbProfile,
  bobProfile,
  iobProfile,
  genericIndianProfile,
];

/// Tries to auto-detect which bank profile matches the extracted text.
///
/// Returns the first profile whose [BankProfile.identifyPatterns] match,
/// or the generic fallback if none match.
BankProfile detectBankProfile(String fullText) {
  for (final profile in allBankProfiles) {
    if (profile.identifyPatterns.isEmpty) continue;
    for (final pattern in profile.identifyPatterns) {
      if (pattern.hasMatch(fullText)) return profile;
    }
  }
  return genericIndianProfile;
}

// ─────────────────────────────────────────────────────────────
//  Date Parsing Helpers
// ─────────────────────────────────────────────────────────────

const _monthNames = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses a date string according to the given [hint].
///
/// [fallbackYear] is used when the date format has no year (e.g. DD MMM).
DateTime? parseStatementDate(String raw, DateParseHint hint, {int? fallbackYear}) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;

  switch (hint) {
    case DateParseHint.ddMmYyyy:
      return _parseDdMmYyyy(cleaned);
    case DateParseHint.ddMmYy:
      return _parseDdMmYy(cleaned);
    case DateParseHint.ddMmmYyyy:
      return _parseDdMmmYyyy(cleaned);
    case DateParseHint.ddMmmYy:
      return _parseDdMmmYy(cleaned);
    case DateParseHint.ddMmm:
      return _parseDdMmm(cleaned, fallbackYear ?? DateTime.now().year);
  }
}

DateTime? _parseDdMmYyyy(String value) {
  final match = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})').firstMatch(value);
  if (match == null) return _parseDdMmYy(value);
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  if (month > 12 || month < 1 || day > 31 || day < 1) return null;
  return DateTime(year, month, day);
}

DateTime? _parseDdMmYy(String value) {
  final match = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2})').firstMatch(value);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final yearShort = int.tryParse(match.group(3)!);
  if (day == null || month == null || yearShort == null) return null;
  final year = 2000 + yearShort;
  if (month > 12 || month < 1 || day > 31 || day < 1) return null;
  return DateTime(year, month, day);
}

DateTime? _parseDdMmmYyyy(String value) {
  final match = RegExp(r'(\d{1,2})\s+(\w{3})\s+(\d{4})').firstMatch(value);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final monthStr = match.group(2)!.toLowerCase();
  final year = int.tryParse(match.group(3)!);
  final month = _monthNames[monthStr];
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

DateTime? _parseDdMmmYy(String value) {
  final match = RegExp(r'(\d{1,2})[/\-](\w{3})[/\-](\d{2})').firstMatch(value);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final monthStr = match.group(2)!.toLowerCase();
  final yearShort = int.tryParse(match.group(3)!);
  final month = _monthNames[monthStr];
  if (day == null || month == null || yearShort == null) return null;
  return DateTime(2000 + yearShort, month, day);
}

DateTime? _parseDdMmm(String value, int fallbackYear) {
  final match = RegExp(r'(\d{1,2})\s+(\w{3})').firstMatch(value);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final monthStr = match.group(2)!.toLowerCase();
  final month = _monthNames[monthStr];
  if (day == null || month == null) return null;
  return DateTime(fallbackYear, month, day);
}

// ─────────────────────────────────────────────────────────────
//  Amount Parsing
// ─────────────────────────────────────────────────────────────

/// Parses an Indian-format amount string like "1,23,456.78" or "12345.00"
/// into minor units (paise).
int? parseIndianAmount(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) return null;
  final parsed = double.tryParse(cleaned);
  if (parsed == null) return null;
  return (parsed * math.pow(10, 2)).round();
}
