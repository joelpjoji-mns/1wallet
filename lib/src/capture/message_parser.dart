import '../data/ledger_models.dart';

class ParsedTransactionMessage {
  const ParsedTransactionMessage({
    required this.rawText,
    required this.ignored,
    required this.warnings,
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
  final List<String> warnings;
}

ParsedTransactionMessage parseTransactionMessage(
  String rawText, {
  String fallbackCurrency = 'INR',
}) {
  final text = rawText.trim();
  if (text.isEmpty) {
    return const ParsedTransactionMessage(
      rawText: '',
      ignored: true,
      warnings: ['Message is empty'],
    );
  }

  final normalized = text.toLowerCase();
  if (_looksLikeSecurityMessage(normalized)) {
    return ParsedTransactionMessage(
      rawText: text,
      ignored: true,
      warnings: const ['Ignored security/OTP style message'],
    );
  }

  final currency = _detectCurrency(text) ?? fallbackCurrency;
  final amountMinor = _extractAmountMinor(text);
  final merchant = _extractMerchant(text);
  final transactionType = _detectTransactionType(normalized);
  final last4 = _extractLast4(text);
  final warnings = <String>[];

  if (amountMinor == null) warnings.add('Amount not detected');
  if (merchant == null) warnings.add('Merchant/account label not detected');
  if (transactionType == null) warnings.add('Transaction type not detected');

  return ParsedTransactionMessage(
    rawText: text,
    ignored: false,
    amount: amountMinor == null
        ? null
        : Money(amountMinor: amountMinor, currency: currency),
    merchant: merchant,
    transactionType: transactionType ?? 'expense',
    last4: last4,
    warnings: warnings,
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
  if (RegExp(r'\bINR\b|\bRs\.?\b|₹', caseSensitive: false).hasMatch(text)) {
    return 'INR';
  }
  if (RegExp(r'\bUSD\b|\$', caseSensitive: false).hasMatch(text)) {
    return 'USD';
  }
  if (RegExp(r'\bGBP\b|£', caseSensitive: false).hasMatch(text)) {
    return 'GBP';
  }
  if (RegExp(r'\bAED\b', caseSensitive: false).hasMatch(text)) {
    return 'AED';
  }
  if (RegExp(r'\bEUR\b|€', caseSensitive: false).hasMatch(text)) {
    return 'EUR';
  }
  return null;
}

int? _extractAmountMinor(String text) {
  final patterns = [
    RegExp(
      r'(?:INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    ),
    RegExp(
      r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:INR|Rs\.?|₹|USD|\$|GBP|£|AED|EUR|€)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:debited|credited|spent|paid|received|withdrawn|purchase(?:d)?|sent)\D+([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    ),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final value = match.group(1)?.replaceAll(',', '');
    if (value == null) continue;
    final parsed = double.tryParse(value);
    if (parsed == null) continue;
    return (parsed * 100).round();
  }
  return null;
}

String? _extractMerchant(String text) {
  final patterns = [
    RegExp(
      r'\b(?:at|to|towards)\s+([A-Za-z0-9 &._-]{3,32})',
      caseSensitive: false,
    ),
    RegExp(r'\bmerchant[:\s]+([A-Za-z0-9 &._-]{3,32})', caseSensitive: false),
    RegExp(r'\bupi[:\s]+([A-Za-z0-9._-]{3,32})', caseSensitive: false),
    RegExp(r'\bfrom\s+([A-Za-z0-9 &._-]{3,32})', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    final candidate = match?.group(1)?.trim();
    if (candidate == null || candidate.isEmpty) continue;
    return candidate
        .replaceFirst(RegExp(r'\s+(on|using|via|ref|available|bal).*$'), '')
        .trim();
  }
  return null;
}

String? _detectTransactionType(String normalized) {
  if (RegExp(
    r'\b(credited|received|deposited|salary|refund|cashback)\b',
  ).hasMatch(normalized)) {
    return 'income';
  }
  if (RegExp(
    r'\b(debited|spent|paid|withdrawn|purchase|purchased|sent)\b',
  ).hasMatch(normalized)) {
    return 'expense';
  }
  return null;
}

String? _extractLast4(String text) {
  final patterns = [
    RegExp(r'(?:card|acct|account|a\/c|ending in)[^\d]*(\d{4})\b', caseSensitive: false),
    RegExp(r'\b[xX*]{2,4}(\d{4})\b', caseSensitive: false),
    RegExp(r'\b(\d{4})\s*(?:debited|credited)', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}
