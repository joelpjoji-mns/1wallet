import 'dart:math' as math;

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
