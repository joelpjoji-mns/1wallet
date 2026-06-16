import '../data/ledger_models.dart';

class ParsedTransactionMessage {
  const ParsedTransactionMessage({
    required this.rawText,
    required this.ignored,
    this.amount,
    this.merchant,
    this.transactionType,
    this.last4,
  });

  final String rawText;
  final bool ignored;
  final Money? amount;
  final String? merchant;
  final String? transactionType;
  final String? last4;
}

ParsedTransactionMessage parseTransactionMessage(
  String rawText, {
  String fallbackCurrency = kDefaultCurrency,
}) {
  final text = rawText.trim();
  if (text.isEmpty) {
    return const ParsedTransactionMessage(
      rawText: '',
      ignored: true,
    );
  }

  final normalized = text.toLowerCase();
  if (_looksLikeSecurityMessage(normalized)) {
    return ParsedTransactionMessage(
      rawText: text,
      ignored: true,
    );
  }

  final currency = _detectCurrency(text) ?? fallbackCurrency;
  final amountMinor = _extractAmountMinor(text);
  final merchant = _extractMerchant(text);
  final transactionType = _detectTransactionType(normalized);
  final last4 = _extractLast4(text);
  if (amountMinor == null || transactionType == null) {
    return ParsedTransactionMessage(
      rawText: text,
      ignored: true,
    );
  }

  return ParsedTransactionMessage(
    rawText: text,
    ignored: false,
    amount: Money(amountMinor: amountMinor, currency: currency),
    merchant: merchant,
    transactionType: transactionType,
    last4: last4,
  );
}

bool _looksLikeSecurityMessage(String normalized) {
  final securityWords = [
    'otp',
    'one time password',
    'verification code',
    'login code',
    'password reset',
    'do not share',
  ];
  return securityWords.any(normalized.contains);
}

String? _detectCurrency(String text) {
  if (RegExp(r'\bINR\b|\bRs\.?|₹', caseSensitive: false).hasMatch(text)) return 'INR';
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
      .replaceAll(RegExp(r'[\u{1F300}-\u{1F5FF}\u{1F900}-\u{1F9FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Ordered by precision
  final patterns = [
    // 0. Explicit Refunds
    RegExp(r'\brefund of\s+.*?\bfrom\s+([A-Za-z0-9 &._-]+?)(?=\s+(?:has|is|was|on|via|ref)|[\.,]\s|[\.,]?$)', caseSensitive: false),
    // 1. Generic postpositions with semicolons (very strong separator in Indian bank SMS)
    RegExp(r'[;]\s*([A-Za-z0-9 &._-]+)\s+(?:credited|debited)\b', caseSensitive: false),
    // 2. UPI / VPA markers (very common in India)
    RegExp(r'\b(?:vpa|upi|info)[:\s-]+([A-Za-z0-9&@._-]+)', caseSensitive: false),
    // 3. "paid <merchant>" or "transfer to <merchant>"
    RegExp(r'\b(?:paid to|paid|transfer to|spent at)\s+([A-Za-z0-9 &._-]+?)(?=\s+(?:from|on|using|via|ref|bal|avl|available|₹|\$|€|£|Rs)|[\.,]\s|[\.,]?$)', caseSensitive: false),
    // 4. Indian explicit "debited from ... to <merchant>"
    RegExp(r'\bfrom\s+a/c.*to\s+([A-Za-z0-9 &@._-]+?)(?=\s+(?:on|using|via|ref)|[\(\[]|[\.,]\s|[\.,]?$)', caseSensitive: false),
    // 5. "at <merchant>" or "to <merchant>" (avoiding common false positives)
    RegExp(r'\b(?:at|to|towards|favouring|for)\s+(?!your\s+card|card\b|a/c\b|account\b)([A-Za-z0-9 &._-]+?)(?=\s+(?:from|on|using|via|ref|bal|avl|available|was|effectu|effectué|₹|\$|€|£|Rs)|[\.,]\s|[\.,]?$)', caseSensitive: false),
    // 6. "credited by <merchant>" or "from <merchant>"
    RegExp(r'\b(?:by|from)\s+([A-Za-z0-9 &._-]+?)(?=\s+(?:on|using|via|ref|bal|avl|available|has|is)|[\.,]\s|[\.,]?$)', caseSensitive: false),
    // 7. Generic postpositions with dashes
    RegExp(r'[-]\s*([A-Za-z0-9 &._-]+)\s+(?:credited|debited)\b', caseSensitive: false),
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
    if (['bal', 'available', 'balance', 'account', 'card', 'bank', 'your'].contains(lowercaseCandidate)) {
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
  if (RegExp(r'\b(refund|reversal|reversed)\b').hasMatch(normalized)) return 'income';
  if (RegExp(r'\b(charge of|direct debit|standing order|cash withdrawal|purchase|fee|deducted|remitted|dr)\b').hasMatch(normalized)) return 'expense';

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
    RegExp(r'(?:card|acct|account|a\/c|ending|ending in)[^\d]*(\d{3,4})\b', caseSensitive: false),
    RegExp(r'\b[xX*]{2,4}(\d{3,4})\b', caseSensitive: false),
    RegExp(r'\b(\d{3,4})\s*(?:debited|credited)', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}
