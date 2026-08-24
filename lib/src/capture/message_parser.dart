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
  final amountMinor = _extractAmountMinor(text);
  final matchedTrigger = _findMatchingWord(normalized, triggerWords);
  final currency = _detectCurrency(text) ?? fallbackCurrency;
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

String? _detectInstitution(String normalized) {
  // Common banks and institutions
  final patterns = {
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

  for (final entry in patterns.entries) {
    if (entry.value.hasMatch(normalized)) {
      return entry.key;
    }
  }
  return null;
}

String? _detectCurrency(String text) {
  if (RegExp(r'\bINR\b|\bRs\.?|₹', caseSensitive: false).hasMatch(text)) {
    return 'INR';
  }
  if (RegExp(r'\bUSD\b|\$', caseSensitive: false).hasMatch(text)) return 'USD';
  if (RegExp(r'\bGBP\b|£', caseSensitive: false).hasMatch(text)) return 'GBP';
  if (RegExp(r'\bEUR\b|€', caseSensitive: false).hasMatch(text)) return 'EUR';
  if (RegExp(r'\bAED\b', caseSensitive: false).hasMatch(text)) return 'AED';
  if (RegExp(r'\bAUD\b|A\$', caseSensitive: false).hasMatch(text)) return 'AUD';
  if (RegExp(r'\bCAD\b|C\$', caseSensitive: false).hasMatch(text)) return 'CAD';
  if (RegExp(r'\bSGD\b|S\$', caseSensitive: false).hasMatch(text)) return 'SGD';
  if (RegExp(r'\bJPY\b|¥', caseSensitive: false).hasMatch(text)) return 'JPY';
  if (RegExp(r'\bCHF\b|₣', caseSensitive: false).hasMatch(text)) return 'CHF';
  if (RegExp(r'\bCNY\b', caseSensitive: false).hasMatch(text)) return 'CNY';
  return null;
}

int? _extractAmountMinor(String text) {
  final patterns = [
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

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;

    var value = match.group(1)!;
    value = value.replaceAll(' ', '');
    // Handle European comma format vs thousands comma format
    // If the last non-digit is a comma and there are 1-2 digits after it, it's a decimal comma.
    if (RegExp(r',[0-9]{1,2}$').hasMatch(value)) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }

    final parsed = double.tryParse(value);
    if (parsed == null) continue;

    // Sanity check: ignore very small or very large amounts that are likely not transactions
    if (parsed > 0 && parsed < 10000000) {
      return (parsed * 100).round();
    }
  }
  return null;
}

String? _extractMerchant(String text) {
  // Strip emojis and normalize whitespace
  final cleanText = text
      .replaceAll(
        RegExp(
          r'[\u{1F300}-\u{1F5FF}\u{1F900}-\u{1F9FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
          unicode: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Ordered by precision
  final patterns = [
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

  for (final pattern in patterns) {
    final match = pattern.firstMatch(cleanText);
    var candidate = match?.group(1)?.trim();
    if (candidate == null || candidate.isEmpty) continue;

    // Ignore candidates that are just phone numbers following "SMS BLOCK"
    if (RegExp(r'^\d{8,12}$').hasMatch(candidate) &&
        RegExp(r'block\s+.*\bto\b', caseSensitive: false).hasMatch(cleanText)) {
      continue;
    }

    // Filter out purely numeric reference numbers (unless it's a VPA with @)
    if (RegExp(r'^[\d.\-]+$').hasMatch(candidate) && !candidate.contains('@')) {
      continue;
    }

    // Filter out common bank noise
    final lowercaseCandidate = candidate.toLowerCase();
    if ([
      'bal',
      'available',
      'balance',
      'account',
      'card',
      'bank',
      'your',
    ].contains(lowercaseCandidate)) {
      continue;
    }

    // Clean up asterisks, hashes, and leading/trailing noise
    candidate = candidate.replaceAll(RegExp(r'[*#]'), '').trim();
    if (candidate.isEmpty) continue;

    return candidate;
  }
  return null;
}

String? _detectTransactionType(String normalized) {
  // If specific phrases exist, prioritize them
  if (RegExp(r'\b(refund|reversal|reversed)\b').hasMatch(normalized)) {
    return 'income';
  }
  if (RegExp(
    r'\b(charge of|direct debit|standing order|cash withdrawal|purchase|fee|deducted|remitted|dr)\b',
  ).hasMatch(normalized)) {
    return 'expense';
  }

  final incomeMatch = RegExp(
    r'\b(credited|received|deposited|salary|cashback|added to|inward clearing|credit of)\b',
  ).firstMatch(normalized);

  final expenseMatch = RegExp(
    r'\b(debited|spent|paid|withdrawn|sent|transfer to|remittance|payment of|paiement)\b',
  ).firstMatch(normalized);

  if (incomeMatch != null && expenseMatch != null) {
    return incomeMatch.start < expenseMatch.start ? 'income' : 'expense';
  } else if (incomeMatch != null) {
    return 'income';
  } else if (expenseMatch != null) {
    return 'expense';
  }
  return null;
}

String? _extractLast4(String text) {
  final patterns = [
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

  for (final pattern in patterns) {
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

/// Extracts all candidate digit sequences (3–6 digits) from the raw SMS,
/// stripping masking characters (X, x, *, •, .) beforehand. This provides a
/// fallback pool of numbers for the account matcher to try when _extractLast4
/// only returns one result or none.
List<String> extractAllNumberFragments(String text) {
  final results = <String>{};

  // 1. Find masked sequences and extract their trailing digits
  //    e.g. "XX1234", "****5678", "...9012", "XXXX3456"
  final maskedPattern = RegExp(r'[xX*•.…]{1,12}(\d{3,6})\b');
  for (final match in maskedPattern.allMatches(text)) {
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
  final keywordPattern = RegExp(
    r'(?:card|acct|account|a\/c|ac|ending)\s*(?:in|with|no|number|num)?[^\d]{0,6}(\d{3,6})\b',
    caseSensitive: false,
  );
  for (final match in keywordPattern.allMatches(text)) {
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
  final barePattern = RegExp(r'(?<!\d)(\d{3,4})(?!\d)');
  for (final match in barePattern.allMatches(text)) {
    results.add(match.group(1)!);
  }

  return results.toList();
}
