import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/ledger_models.dart';

class ParsedTransactionMessage {
  const ParsedTransactionMessage({
    required this.rawText,
    required this.ignored,
    this.hasAmount = false,
    this.hasTriggerWord = false,
    this.amount,
    this.merchant,
    this.transactionType,
    this.last4,
    this.institutionName,
    this.matchedTriggerWord,
    this.matchedIgnoreWord,
  });

  final String rawText;
  final bool ignored;
  final bool hasAmount;
  final bool hasTriggerWord;
  final Money? amount;
  final String? merchant;
  final String? transactionType;
  final String? last4;
  final String? institutionName;
  final String? matchedTriggerWord;
  final String? matchedIgnoreWord;
}

ParsedTransactionMessage parseTransactionMessage(
  String rawText, {
  String fallbackCurrency = kDefaultCurrency,
  List<String> triggerWords = kDefaultSmsTriggerWords,
  List<String> ignoreWords = kDefaultSmsIgnoreWords,
}) {
  final text = rawText.trim();
  if (text.isEmpty) {
    return const ParsedTransactionMessage(rawText: '', ignored: true);
  }

  final normalized = text.toLowerCase();
  final currency = _detectCurrency(text) ?? fallbackCurrency;
  final amountMinor = _extractAmountMinor(text, currency: currency);
  final matchedTrigger = _findMatchingWord(normalized, triggerWords);
  final parsedAmount = amountMinor == null
      ? null
      : Money(amountMinor: amountMinor, currency: currency);
  final merchant = _extractMerchant(text);
  final transactionType = _detectTransactionType(normalized);
  final last4 = _extractLast4(text);
  final institutionName = _detectInstitution(normalized);

  // 1. Reject anything matching an ignore word (OTP, promo, reminder,
  //    request, failure, ...) even if it also looks transactional.
  final matchedIgnore = _findMatchingWord(normalized, ignoreWords);
  if (matchedIgnore != null) {
    return ParsedTransactionMessage(
      rawText: text,
      ignored: true,
      hasAmount: amountMinor != null,
      hasTriggerWord: matchedTrigger != null,
      amount: parsedAmount,
      merchant: merchant,
      transactionType: transactionType,
      last4: last4,
      institutionName: institutionName,
      matchedTriggerWord: matchedTrigger,
      matchedIgnoreWord: matchedIgnore,
    );
  }

  // 2. A real, completed transaction needs BOTH an amount and a trigger word.
  //    This is the exact rule the native SMS receiver applies, so a
  //    notification is raised if and only if a review candidate is created.
  if (amountMinor == null || matchedTrigger == null) {
    return ParsedTransactionMessage(
      rawText: text,
      ignored: true,
      hasAmount: amountMinor != null,
      hasTriggerWord: matchedTrigger != null,
      amount: parsedAmount,
      merchant: merchant,
      transactionType: transactionType,
      last4: last4,
      institutionName: institutionName,
      matchedTriggerWord: matchedTrigger,
    );
  }

  return ParsedTransactionMessage(
    rawText: text,
    ignored: false,
    hasAmount: true,
    hasTriggerWord: true,
    amount: parsedAmount,
    merchant: merchant,
    transactionType: transactionType ?? 'expense',
    last4: last4,
    institutionName: institutionName,
    matchedTriggerWord: matchedTrigger,
  );
}

/// Shared accept predicate. Mirrors the native Android pre-filter so the
/// notification and the review queue always agree.
bool smsLooksLikeTransaction(
  String rawText, {
  List<String> triggerWords = kDefaultSmsTriggerWords,
  List<String> ignoreWords = kDefaultSmsIgnoreWords,
}) => !parseTransactionMessage(
  rawText,
  triggerWords: triggerWords,
  ignoreWords: ignoreWords,
).ignored;

String? _findMatchingWord(String normalizedText, List<String> words) {
  for (final raw in words) {
    final word = raw.trim().toLowerCase();
    if (word.isEmpty) continue;
    bool matched = false;
    if (word.contains(' ')) {
      matched = normalizedText.contains(word);
    } else if (word.length <= 3) {
      final pattern = RegExp('(^|\\W)${RegExp.escape(word)}(\$|\\W)');
      matched = pattern.hasMatch(normalizedText);
    } else {
      matched = normalizedText.contains(word);
    }
    if (matched) {
      return raw;
    }
  }
  return null;
}

final Map<String, RegExp> _institutionPatterns = {
  'HDFC': RegExp(r'\b(?:hdfc|hdfcbank)\b'),
  'ICICI': RegExp(r'\b(?:icici|icicibank)\b'),
  'SBI': RegExp(r'\b(?:sbi|state bank)\b'),
  'Axis': RegExp(r'\b(?:axis|axisbank)\b'),
  'Kotak': RegExp(r'\b(?:kotak)\b'),
  'Yes Bank': RegExp(r'\b(?:yes bank|yesbank)\b'),
  'IndusInd': RegExp(r'\b(?:indusind)\b'),
  'Chase': RegExp(r'\b(?:chase)\b'),
  'Citi': RegExp(r'\b(?:citi|citibank)\b'),
  'Wells Fargo': RegExp(r'\b(?:wells fargo)\b'),
  'BoA': RegExp(r'\b(?:bank of america|bofa)\b'),
  'Amex': RegExp(r'\b(?:amex|american express)\b'),
  'Discover': RegExp(r'\b(?:discover)\b'),
  'Revolut': RegExp(r'\b(?:revolut)\b'),
  'Monzo': RegExp(r'\b(?:monzo)\b'),
  'Wise': RegExp(r'\b(?:wise|transferwise)\b'),
  'Barclays': RegExp(r'\b(?:barclays)\b'),
  'HSBC': RegExp(r'\b(?:hsbc)\b'),
  'Standard Chartered': RegExp(r'\b(?:standard chartered|stanchart)\b'),
  'Paytm': RegExp(r'\b(?:paytm|paytm bank)\b'),
  'PhonePe': RegExp(r'\b(?:phonepe)\b'),
  'GPay': RegExp(r'\b(?:gpay|google pay)\b'),
};

String? _detectInstitution(String normalized) {
  for (final entry in _institutionPatterns.entries) {
    if (entry.value.hasMatch(normalized)) {
      return entry.key;
    }
  }
  return null;
}

final Map<String, RegExp> _currencyPatterns = {
  'INR': RegExp(r'\bINR\b|\bRs\.?|₹', caseSensitive: false),
  'USD': RegExp(r'\bUSD\b|\$', caseSensitive: false),
  'GBP': RegExp(r'\bGBP\b|£', caseSensitive: false),
  'EUR': RegExp(r'\bEUR\b|€', caseSensitive: false),
  'AED': RegExp(r'\bAED\b', caseSensitive: false),
  'AUD': RegExp(r'\bAUD\b|A\$', caseSensitive: false),
  'CAD': RegExp(r'\bCAD\b|C\$', caseSensitive: false),
  'SGD': RegExp(r'\bSGD\b|S\$', caseSensitive: false),
  'JPY': RegExp(r'\bJPY\b|¥', caseSensitive: false),
  'CHF': RegExp(r'\bCHF\b|₣', caseSensitive: false),
  'CNY': RegExp(r'\bCNY\b', caseSensitive: false),
};

String? _detectCurrency(String text) {
  for (final entry in _currencyPatterns.entries) {
    if (entry.value.hasMatch(text)) {
      return entry.key;
    }
  }
  return null;
}

int _minorDigits(String currency) => switch (currency.toUpperCase()) {
  'JPY' ||
  'KRW' ||
  'VND' ||
  'CLP' ||
  'ISK' ||
  'PYG' ||
  'UGX' ||
  'RWF' ||
  'XAF' ||
  'XOF' ||
  'XPF' ||
  'DJF' ||
  'GNF' ||
  'KMF' ||
  'BIF' ||
  'VUV' => 0,
  'BHD' || 'KWD' || 'OMR' || 'TND' || 'IQD' || 'JOD' || 'LYD' => 3,
  _ => 2,
};

final List<RegExp> _amountPatterns = [
  // 1. Explicit amount markers with currency codes
  RegExp(
    r'(?:Amt|Amount|Sum|Value|INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€|AUD|A\$|CAD|C\$|SGD|S\$|JPY|¥|CHF|₣|CNY)[:\s]*([0-9]+(?:[.,\s][0-9]+)*)',
    caseSensitive: false,
  ),
  // 2. Numeric values followed by currency
  RegExp(
    r'([0-9]+(?:[.,\s][0-9]+)*)\s*(?:INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€|AUD|A\$|CAD|C\$|SGD|S\$|JPY|¥|CHF|₣|CNY)',
    caseSensitive: false,
  ),
  // 3. Action keywords followed by amount
  RegExp(
    r'(?:debited|credited|spent|paid|received|withdrawn|purchase(?:d)?|sent|charge of|Refund of|fee of|deducted|remitted|txn of|transfer of)\D+([0-9]+(?:[.,\s][0-9]+)*)',
    caseSensitive: false,
  ),
];
final RegExp _europeanDecimalCommaRegex = RegExp(r',[0-9]{1,2}$');

int? _extractAmountMinor(String text, {String? currency}) {
  for (final pattern in _amountPatterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;

    var value = match.group(1)!;
    value = value.replaceAll(' ', '');
    // Handle European comma format vs thousands comma format
    // If the last non-digit is a comma and there are 1-2 digits after it, it's a decimal comma.
    if (_europeanDecimalCommaRegex.hasMatch(value)) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }

    final parsed = double.tryParse(value);
    if (parsed == null) continue;

    // Sanity check: ignore very small or very large amounts that are likely not transactions
    final digits = _minorDigits(currency ?? 'USD');
    if (parsed > 0 && parsed < 10000000) {
      return (parsed * math.pow(10, digits)).round();
    }
  }
  return null;
}

final RegExp _emojiStripRegex = RegExp(
  r'[\u{1F300}-\u{1F5FF}\u{1F900}-\u{1F9FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
  unicode: true,
);
final RegExp _whitespaceRegex = RegExp(r'\s+');
final List<RegExp> _merchantPatterns = [
  // 0. Explicit Refunds
  RegExp(
    r'\brefund of\s+.*?\bfrom\s+([A-Za-z0-9 &._-]+?)(?=\s+(?:has|is|was|on|via|ref)|[\.,]\s|[\.,]?$)',
    caseSensitive: false,
  ),
  // 1. Generic postpositions with semicolons (very strong separator in Indian bank SMS)
  RegExp(
    r'[;]\s*([A-Za-z0-9 &._-]+)\s+(?:credited|debited)\b',
    caseSensitive: false,
  ),
  // 2. UPI / VPA markers (very common in India)
  RegExp(
    r'\b(?:vpa|upi|info)[:\s-]+([A-Za-z0-9&@._-]+)',
    caseSensitive: false,
  ),
  // 3. "paid <merchant>" or "transfer to <merchant>"
  RegExp(
    r'\b(?:paid to|paid|transfer to|spent at)\s+([A-Za-z0-9 &._-]+?)(?=\s+(?:from|on|using|via|ref|bal|avl|available|₹|\$|€|£|Rs)|[\.,]\s|[\.,]?$)',
    caseSensitive: false,
  ),
  // 4. Indian explicit "debited from ... to <merchant>"
  RegExp(
    r'\bfrom\s+a/c.*to\s+([A-Za-z0-9 &@._-]+?)(?=\s+(?:on|using|via|ref)|[\(\[]|[\.,]\s|[\.,]?$)',
    caseSensitive: false,
  ),
  // 5. "at <merchant>" or "to <merchant>" (avoiding common false positives)
  RegExp(
    r'\b(?:at|to|towards|favouring|for)\s+(?!your\s+card|card\b|a/c\b|account\b)([A-Za-z0-9 &._-]+?)(?=\s+(?:from|on|using|via|ref|bal|avl|available|was|effectu|effectué|₹|\$|€|£|Rs)|[\.,]\s|[\.,]?$)',
    caseSensitive: false,
  ),
  // 6. "credited by <merchant>" or "from <merchant>"
  RegExp(
    r'\b(?:by|from)\s+([A-Za-z0-9 &._-]+?)(?=\s+(?:on|using|via|ref|bal|avl|available|has|is)|[\.,]\s|[\.,]?$)',
    caseSensitive: false,
  ),
  // 7. Generic postpositions with dashes
  RegExp(
    r'[-]\s*([A-Za-z0-9 &._-]+)\s+(?:credited|debited)\b',
    caseSensitive: false,
  ),
];
final RegExp _smsBlockDigitsRegex = RegExp(r'^\d{8,12}$');
final RegExp _smsBlockTextRegex = RegExp(r'block\s+.*\bto\b', caseSensitive: false);
final RegExp _numericRefRegex = RegExp(r'^[\d.\-]+$');
final RegExp _asteriskHashRegex = RegExp(r'[*#]');
const Set<String> _merchantNoiseWords = {
  'bal',
  'available',
  'balance',
  'account',
  'card',
  'bank',
  'your',
};

String? _extractMerchant(String text) {
  // Strip emojis and normalize whitespace
  final cleanText = text
      .replaceAll(_emojiStripRegex, '')
      .replaceAll(_whitespaceRegex, ' ')
      .trim();

  for (final pattern in _merchantPatterns) {
    final match = pattern.firstMatch(cleanText);
    var candidate = match?.group(1)?.trim();
    if (candidate == null || candidate.isEmpty) continue;

    // Ignore candidates that are just phone numbers following "SMS BLOCK"
    if (_smsBlockDigitsRegex.hasMatch(candidate) &&
        _smsBlockTextRegex.hasMatch(cleanText)) {
      continue;
    }

    // Filter out purely numeric reference numbers (unless it's a VPA with @)
    if (_numericRefRegex.hasMatch(candidate) && !candidate.contains('@')) {
      continue;
    }

    // Filter out common bank noise
    final lowercaseCandidate = candidate.toLowerCase();
    if (_merchantNoiseWords.contains(lowercaseCandidate)) {
      continue;
    }

    // Clean up asterisks, hashes, and leading/trailing noise
    candidate = candidate.replaceAll(_asteriskHashRegex, '').trim();
    if (candidate.isEmpty) continue;

    return candidate;
  }
  return null;
}

final RegExp _refundTypeRegex = RegExp(r'\b(refund|reversal|reversed)\b');
final RegExp _explicitExpenseTypeRegex = RegExp(
  r'\b(charge of|direct debit|standing order|cash withdrawal|purchase|fee|deducted|remitted|dr)\b',
);
final RegExp _incomeTypeRegex = RegExp(
  r'\b(credited|received|deposited|salary|cashback|added to|inward clearing|credit of)\b',
);
final RegExp _expenseTypeRegex = RegExp(
  r'\b(debited|spent|paid|withdrawn|sent|transfer to|remittance|payment of|paiement)\b',
);

String? _detectTransactionType(String normalized) {
  // If specific phrases exist, prioritize them
  if (_refundTypeRegex.hasMatch(normalized)) {
    return 'income';
  }
  if (_explicitExpenseTypeRegex.hasMatch(normalized)) {
    return 'expense';
  }

  final incomeMatch = _incomeTypeRegex.firstMatch(normalized);
  final expenseMatch = _expenseTypeRegex.firstMatch(normalized);

  if (incomeMatch != null && expenseMatch != null) {
    return incomeMatch.start < expenseMatch.start ? 'income' : 'expense';
  } else if (incomeMatch != null) {
    return 'income';
  } else if (expenseMatch != null) {
    return 'expense';
  }
  return null;
}

final List<RegExp> _last4Patterns = [
  // 1. Explicit keywords followed by digits (most reliable)
  RegExp(
    r'(?:card|acct|account|a\/c|ac|ending|ending in|ending with)[^\d]*(\d{3,6})\b',
    caseSensitive: false,
  ),
  // 2. "a/c no" / "account no" / "card no" variants
  RegExp(
    r'(?:a\/c\s*no|ac\s*no|account\s*no|card\s*no)[.\s]*[xX*]*(\d{3,6})\b',
    caseSensitive: false,
  ),
  // 3. "card no ending" / "card number ending" patterns
  RegExp(
    r'(?:card|account|a\/c)\s*(?:no|number|num)?\s*(?:ending|end)\s*(?:in|with)?\s*[^\d]*(\d{3,6})\b',
    caseSensitive: false,
  ),
  // 4. Masking with X/x/*/• followed by digits: XX1234, xxxx1234, **1234, ••1234
  RegExp(r'[xX*•]{2,12}(\d{3,6})\b', caseSensitive: false),
  // 5. Dots masking: ...1234, ..1234, …1234
  RegExp(r'[.…]{2,6}(\d{3,6})\b', caseSensitive: false),
  // 6. "4567 debited/credited" pattern
  RegExp(r'\b(\d{3,4})\s*(?:debited|credited)', caseSensitive: false),
  // 7. "from a/c 1234" / "to a/c 1234" / "in a/c 1234"
  RegExp(
    r'(?:from|to|in|on|for)\s+(?:a\/c|ac|acct|account)\s*[^\d]*(\d{3,6})\b',
    caseSensitive: false,
  ),
  // 8. "your 1234 account" or "ur 1234 card"
  RegExp(
    r'(?:your|ur)\s+[^\d]*(\d{3,4})\s+(?:account|card|a\/c)',
    caseSensitive: false,
  ),
];

String? _extractLast4(String text) {
  for (final pattern in _last4Patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      final digits = match.group(1)!;
      // Return last 4 digits if we got more (e.g. from a 5-6 digit match)
      if (digits.length > 4) {
        return digits.substring(digits.length - 4);
      }
      return digits;
    }
  }
  return null;
}

final RegExp _maskedFragmentPattern = RegExp(r'[xX*•.…]{1,12}(\d{3,6})\b');
final RegExp _keywordFragmentPattern = RegExp(
  r'(?:card|acct|account|a\/c|ac|ending)\s*(?:in|with|no|number|num)?[^\d]{0,6}(\d{3,6})\b',
  caseSensitive: false,
);
final RegExp _bareFragmentPattern = RegExp(r'(?<!\d)(\d{3,4})(?!\d)');

/// Extracts all candidate digit sequences (3–6 digits) from the raw SMS,
/// stripping masking characters (X, x, *, •, .) beforehand. This provides a
/// fallback pool of numbers for the account matcher to try when _extractLast4
/// only returns one result or none.
List<String> extractAllNumberFragments(String text) {
  final results = <String>{};

  // 1. Find masked sequences and extract their trailing digits
  //    e.g. "XX1234", "****5678", "...9012", "XXXX3456"
  for (final match in _maskedFragmentPattern.allMatches(text)) {
    final digits = match.group(1)!;
    results.add(digits);
    if (digits.length > 4) {
      results.add(digits.substring(digits.length - 4));
    }
    if (digits.length > 3) {
      results.add(digits.substring(digits.length - 3));
    }
  }

  // 2. Find digits preceded by account/card keywords
  for (final match in _keywordFragmentPattern.allMatches(text)) {
    final digits = match.group(1)!;
    results.add(digits);
    if (digits.length > 4) {
      results.add(digits.substring(digits.length - 4));
    }
    if (digits.length > 3) {
      results.add(digits.substring(digits.length - 3));
    }
  }

  // 3. Find all standalone 3-4 digit sequences (non-greedy, avoid matching
  //    amounts, years, times, OTPs etc. — but include them for exhaustive
  //    matching; the scorer will rank account matches by signal strength)
  for (final match in _bareFragmentPattern.allMatches(text)) {
    results.add(match.group(1)!);
  }

  return results.toList();
}

bool digitsSuffixMatch(String? candidate, String query) {
  if (candidate == null) return false;
  final cleanCandidate = candidate.replaceAll(RegExp(r'\D'), '');
  final cleanQuery = query.replaceAll(RegExp(r'\D'), '');
  if (cleanCandidate.isEmpty || cleanQuery.isEmpty) return false;
  return cleanCandidate.endsWith(cleanQuery) ||
      cleanQuery.endsWith(cleanCandidate);
}

@immutable
class BillStatementNotice {
  const BillStatementNotice({
    required this.rawText,
    this.amount,
    this.minAmountDue,
    this.dueDate,
    this.dueDay,
    this.statementDate,
    this.statementDay,
    this.last4,
    this.institution,
  });

  final String rawText;
  final Money? amount;
  final Money? minAmountDue;
  final DateTime? dueDate;
  final int? dueDay;
  final DateTime? statementDate;
  final int? statementDay;
  final String? last4;
  final String? institution;
}

final RegExp _statementMarkersRegex = RegExp(
  r'\b(?:e-?statement|e-?bill|statement|credit\s+card\s+bill)\b',
  caseSensitive: false,
);

final RegExp _dueMarkersRegex = RegExp(
  r'\b(?:total\s+amount\s+due|total\s+amt\s+due|total\s+due|minimum\s+amount\s+due|min\s+amount\s+due|min\s+due|payment\s+due\s+date|payment\s+due|amount\s+due|bill\s+due|bill\s+is\s+ready|statement\s+ready|statement\s+is\s+ready|statement\s+generated|statement\s+has\s+been\s+generated|statement\s+has\s+generated|statement\s+is\s+generated|bill\s+generated|bill\s+has\s+been\s+generated|bill\s+is\s+generated)\b',
  caseSensitive: false,
);

bool isBillStatementMessage(String text) {
  final lower = text.toLowerCase();
  if (_dueMarkersRegex.hasMatch(lower)) return true;
  if (_statementMarkersRegex.hasMatch(lower) &&
      (lower.contains('due') ||
          lower.contains('ready') ||
          lower.contains('generated') ||
          lower.contains('balance'))) {
    return true;
  }
  return false;
}

const Map<String, int> _statementMonthMap = {
  'jan': 1, 'january': 1,
  'feb': 2, 'february': 2,
  'mar': 3, 'march': 3,
  'apr': 4, 'april': 4,
  'may': 5,
  'jun': 6, 'june': 6,
  'jul': 7, 'july': 7,
  'aug': 8, 'august': 8,
  'sep': 9, 'september': 9, 'sept': 9,
  'oct': 10, 'october': 10,
  'nov': 11, 'november': 11,
  'dec': 12, 'december': 12,
};

DateTime? _parseStatementDateComponent(
  String dayStr,
  String monthStr,
  String? yearStr, {
  DateTime? fallbackNow,
}) {
  final day = int.tryParse(dayStr);
  if (day == null || day < 1 || day > 31) return null;

  int? month = int.tryParse(monthStr);
  month ??= _statementMonthMap[monthStr.toLowerCase().trim()];
  if (month == null || month < 1 || month > 12) return null;

  int year;
  if (yearStr != null && yearStr.isNotEmpty) {
    var y = int.tryParse(yearStr);
    if (y == null) return null;
    if (y < 100) {
      y += 2000;
    }
    year = y;
  } else {
    final now = fallbackNow ?? DateTime.now();
    year = now.year;
    if (month < now.month - 6) {
      year += 1;
    }
  }

  final maxDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day.clamp(1, maxDay));
}

final List<RegExp> _dueDatePatterns = [
  // 1. Due date: 15-Nov-2026 / 15/11/2026 / 15-11-26
  RegExp(
    r'(?:due\s*(?:date|on|by)?|payment\s*due(?:\s*date)?|pay\s*by)[:\s]+(\d{1,2})[-/. ]([A-Za-z]{3,9}|\d{1,2})[-/. ](\d{2,4})',
    caseSensitive: false,
  ),
  // 2. Due on Nov 18, 2026 / Dec 2
  RegExp(
    r'(?:due\s*(?:date|on|by)?|payment\s*due(?:\s*date)?|pay\s*by)[:\s]+([A-Za-z]{3,9})\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(\d{2,4}))?',
    caseSensitive: false,
  ),
  // 3. Due 15th Nov / 22 Nov 2026
  RegExp(
    r'(?:due\s*(?:date|on|by)?|payment\s*due(?:\s*date)?|pay\s*by)[:\s]+(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})(?:,?\s*(\d{2,4}))?',
    caseSensitive: false,
  ),
  // 4. Due on 15th / due by 20th
  RegExp(
    r'(?:due\s*(?:on|by)|payment\s*due)[:\s]+(\d{1,2})(?:st|nd|rd|th)?\b',
    caseSensitive: false,
  ),
];

final List<RegExp> _statementDatePatterns = [
  RegExp(
    r'(?:statement\s*(?:generated\s*on|date|as\s*on|dated|of)|e-?statement\s*(?:dated|of|for)|bill\s*(?:generated\s*on|date))[:\s]+(\d{1,2})[-/. ]([A-Za-z]{3,9}|\d{1,2})(?:[-/. ](\d{2,4}))?',
    caseSensitive: false,
  ),
  RegExp(
    r'(?:statement\s*(?:generated\s*on|date|as\s*on|dated|of)|e-?statement\s*(?:dated|of|for)|bill\s*(?:generated\s*on|date))[:\s]+([A-Za-z]{3,9})\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(\d{2,4}))?',
    caseSensitive: false,
  ),
];

final List<RegExp> _statementAmountPatterns = [
  RegExp(
    r'(?:total\s+amount\s+due|total\s+amt\s+due|total\s+due|amount\s+due|new\s+balance|bill\s+amount|payment\s+of)[:\s]*(?:INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€|AUD|A\$|CAD|C\$|SGD|S\$)?[:\s]*([0-9]+(?:[.,\s][0-9]+)*)',
    caseSensitive: false,
  ),
  RegExp(
    r'(?:INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€|AUD|A\$|CAD|C\$|SGD|S\$)\s*([0-9]+(?:[.,\s][0-9]+)*)\s*(?:is\s+due|due)',
    caseSensitive: false,
  ),
];

final RegExp _minAmountPattern = RegExp(
  r'(?:min(?:imum)?\s*(?:amount|amt)?\s*due|min\s*due)[:\s]*(?:INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€|AUD|A\$|CAD|C\$|SGD|S\$)?[:\s]*([0-9]+(?:[.,\s][0-9]+)*)',
  caseSensitive: false,
);

BillStatementNotice? parseBillStatementNotice(
  String rawText, {
  String fallbackCurrency = kDefaultCurrency,
  DateTime? receivedAt,
}) {
  final text = rawText.trim();
  if (text.isEmpty) return null;

  final currency = _detectCurrency(text) ?? fallbackCurrency;

  // 1. Extract total amount due
  int? amountMinor;
  for (final pattern in _statementAmountPatterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      var valStr = match.group(1)!.replaceAll(' ', '');
      if (_europeanDecimalCommaRegex.hasMatch(valStr)) {
        valStr = valStr.replaceAll('.', '').replaceAll(',', '.');
      } else {
        valStr = valStr.replaceAll(',', '');
      }
      final parsed = double.tryParse(valStr);
      if (parsed != null && parsed > 0 && parsed < 100000000) {
        final digits = _minorDigits(currency);
        amountMinor = (parsed * math.pow(10, digits)).round();
        break;
      }
    }
  }
  // Fallback to general amount extractor
  amountMinor ??= _extractAmountMinor(text, currency: currency);

  final totalAmount = amountMinor != null
      ? Money(amountMinor: amountMinor, currency: currency)
      : null;

  // 2. Extract minimum amount due
  Money? minAmountDue;
  final minMatch = _minAmountPattern.firstMatch(text);
  if (minMatch != null) {
    var valStr = minMatch.group(1)!.replaceAll(' ', '');
    if (_europeanDecimalCommaRegex.hasMatch(valStr)) {
      valStr = valStr.replaceAll('.', '').replaceAll(',', '.');
    } else {
      valStr = valStr.replaceAll(',', '');
    }
    final parsed = double.tryParse(valStr);
    if (parsed != null && parsed > 0 && parsed < 100000000) {
      final digits = _minorDigits(currency);
      final minMinor = (parsed * math.pow(10, digits)).round();
      minAmountDue = Money(amountMinor: minMinor, currency: currency);
    }
  }

  // 3. Extract Due Date / Due Day
  DateTime? dueDate;
  int? dueDay;
  final refNow = receivedAt ?? DateTime.now();

  for (int i = 0; i < _dueDatePatterns.length; i++) {
    final pattern = _dueDatePatterns[i];
    final match = pattern.firstMatch(text);
    if (match == null) continue;

    if (i == 0) {
      // day, month, year
      dueDate = _parseStatementDateComponent(
        match.group(1)!,
        match.group(2)!,
        match.group(3),
        fallbackNow: refNow,
      );
      if (dueDate != null) {
        dueDay = dueDate.day;
        break;
      }
    } else if (i == 1) {
      // month, day, year
      dueDate = _parseStatementDateComponent(
        match.group(2)!,
        match.group(1)!,
        match.group(3),
        fallbackNow: refNow,
      );
      if (dueDate != null) {
        dueDay = dueDate.day;
        break;
      }
    } else if (i == 2) {
      // day, month, year
      dueDate = _parseStatementDateComponent(
        match.group(1)!,
        match.group(2)!,
        match.group(3),
        fallbackNow: refNow,
      );
      if (dueDate != null) {
        dueDay = dueDate.day;
        break;
      }
    } else if (i == 3) {
      // day only
      final d = int.tryParse(match.group(1)!);
      if (d != null && d >= 1 && d <= 31) {
        dueDay = d;
        break;
      }
    }
  }

  // 4. Extract Statement Date / Statement Day
  DateTime? statementDate;
  int? statementDay;

  for (int i = 0; i < _statementDatePatterns.length; i++) {
    final pattern = _statementDatePatterns[i];
    final match = pattern.firstMatch(text);
    if (match == null) continue;

    if (i == 0) {
      statementDate = _parseStatementDateComponent(
        match.group(1)!,
        match.group(2)!,
        match.group(3),
        fallbackNow: refNow,
      );
      if (statementDate != null) {
        statementDay = statementDate.day;
        break;
      }
    } else if (i == 1) {
      statementDate = _parseStatementDateComponent(
        match.group(2)!,
        match.group(1)!,
        match.group(3),
        fallbackNow: refNow,
      );
      if (statementDate != null) {
        statementDay = statementDate.day;
        break;
      }
    }
  }

  // Fallback statement date/day from receivedAt
  if (statementDate == null && receivedAt != null) {
    statementDate = receivedAt;
    statementDay = receivedAt.day;
  }

  // 5. Last 4 & Institution
  final last4 = _extractLast4(text);
  final institution = _detectInstitution(text.toLowerCase());

  return BillStatementNotice(
    rawText: text,
    amount: totalAmount,
    minAmountDue: minAmountDue,
    dueDate: dueDate,
    dueDay: dueDay,
    statementDate: statementDate,
    statementDay: statementDay,
    last4: last4,
    institution: institution,
  );
}

Account? matchAccountForStatement(LedgerState state, BillStatementNotice notice) {
  final activeAccounts = state.accounts.where((a) => !a.isArchived).toList();
  if (activeAccounts.isEmpty) return null;

  final rawLower = notice.rawText.toLowerCase();
  final allFragments = extractAllNumberFragments(notice.rawText);

  Account? bestMatch;
  int highestScore = -1;

  for (final account in activeAccounts) {
    int score = 0;
    final isCard = account.type == 'card' || account.type == 'credit_card';
    if (isCard) {
      score += 25; // Priority for cards on statement matching
    }

    // 1. Last 4 match
    if (notice.last4 != null) {
      if (digitsSuffixMatch(account.cardLast4, notice.last4!) ||
          digitsSuffixMatch(account.accountLast4, notice.last4!)) {
        score += 100;
      }
      if (account.encryptedDetails != null) {
        final accNum = account.encryptedDetails!['accountNumber'];
        if (accNum != null) {
          final cleanAccNum = accNum.replaceAll(RegExp(r'\D'), '');
          if (cleanAccNum.isNotEmpty && cleanAccNum.endsWith(notice.last4!)) {
            score += 150;
          }
        }
      }
    }

    // 2. Fragment match if not already matched
    if (score < 100) {
      for (final fragment in allFragments) {
        if (digitsSuffixMatch(account.cardLast4, fragment) ||
            digitsSuffixMatch(account.accountLast4, fragment)) {
          score += 80;
          break;
        }
      }
    }

    // 3. Institution match
    if (notice.institution != null && account.institution != null) {
      final instLower = account.institution!.toLowerCase();
      final noticeInstLower = notice.institution!.toLowerCase();
      if (instLower.contains(noticeInstLower) ||
          noticeInstLower.contains(instLower)) {
        score += 50;
      }
    } else if (account.institution != null) {
      final instLower = account.institution!.toLowerCase();
      if (rawLower.contains(instLower)) {
        score += 35;
      }
    }

    // 4. Account name match
    final nameLower = account.name.toLowerCase();
    if (rawLower.contains(nameLower)) {
      score += 50;
    } else {
      final nameTokens = nameLower
          .split(RegExp(r'\s+'))
          .where((t) => t.length > 2)
          .toList();
      if (nameTokens.isNotEmpty) {
        final matched = nameTokens.where((t) => rawLower.contains(t)).length;
        if (matched > 0) {
          score += (40 * matched / nameTokens.length).round();
        }
      }
    }

    if (score > highestScore) {
      highestScore = score;
      bestMatch = account;
    }
  }

  // Minimum threshold: 50 points
  if (highestScore >= 50) {
    return bestMatch;
  }
  return null;
}
