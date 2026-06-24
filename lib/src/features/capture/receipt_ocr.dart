import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../data/ledger_models.dart';

const String kReceiptOcrProvider = 'mlkit-text-recognition';

enum ReceiptOcrStatus { parsed, skipped, failed }

class ReceiptPhotoFields {
  final String provider;
  final ReceiptOcrStatus status;
  final String? text;
  final List<String> lines;
  final int? amountMinor;
  final String? currency;
  final String? merchant;
  final String? occurredAt;
  final String? paymentMethod;
  final String? notes;
  final int confidence;
  final String? errorMessage;

  const ReceiptPhotoFields({
    required this.provider,
    required this.status,
    this.text,
    required this.lines,
    this.amountMinor,
    this.currency,
    this.merchant,
    this.occurredAt,
    this.paymentMethod,
    this.notes,
    required this.confidence,
    this.errorMessage,
  });
}

class ReceiptPhotoOptions {
  final String fallbackCurrency;
  final String fallbackOccurredAt;
  final String? fileName;

  const ReceiptPhotoOptions({
    required this.fallbackCurrency,
    required this.fallbackOccurredAt,
    this.fileName,
  });
}

class AmountCandidate {
  final double amount;
  final String currency;
  final int score;

  const AmountCandidate({
    required this.amount,
    required this.currency,
    required this.score,
  });
}

class ParsedDateParts {
  final int year;
  final int month;
  final int day;
  final int? hour;
  final int? minute;
  final int score;

  const ParsedDateParts({
    required this.year,
    required this.month,
    required this.day,
    this.hour,
    this.minute,
    required this.score,
  });
}

const _preciseTotalKeywords = [
  'grand total',
  'amount paid',
  'amount payable',
  'net payable',
  'total paid',
  'total due',
  'balance due',
  'final total',
];

const _looseTotalKeywords = ['total', 'paid', 'payable', 'due'];

const _amountExcludeKeywords = [
  'subtotal',
  'sub total',
  'tax',
  'gst',
  'vat',
  'cgst',
  'sgst',
  'igst',
  'discount',
  'change',
  'tender',
  'cash back',
  'cashback',
  'round off',
  'qty',
  'quantity',
  'unit price',
  'rate',
  'mrp',
];

const _merchantExcludeKeywords = [
  'receipt',
  'tax invoice',
  'invoice',
  'bill',
  'gstin',
  'cin',
  'phone',
  'mobile',
  'tel',
  'email',
  'www',
  'http',
  'address',
  'cashier',
  'counter',
  'table',
  'token',
  'duplicate',
  'copy',
  'date',
  'time',
  'order',
  'item',
  'qty',
  'total',
  'subtotal',
  'payment',
  'card',
  'upi',
];

const _months = <String, int>{
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

Future<ReceiptPhotoFields> extractReceiptFieldsFromPhoto(
  String imagePath,
  ReceiptPhotoOptions options,
) async {
  try {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();
    return parseReceiptText(recognizedText.text, options);
  } catch (error) {
    return _emptyReceiptFields(
      ReceiptOcrStatus.failed,
      options,
      errorMessage: error.toString(),
    );
  }
}

ReceiptPhotoFields parseReceiptText(String text, ReceiptPhotoOptions options) {
  final lines = _receiptLines(text);
  final currencyFallback = options.fallbackCurrency.toUpperCase();
  final amount = _extractReceiptAmount(lines, currencyFallback);
  final merchant = _extractReceiptMerchant(lines);
  final occurredAt = _extractReceiptDate(
    lines,
    currencyFallback,
    options.fallbackOccurredAt,
  );
  final paymentMethod = _extractReceiptPaymentMethod(lines);

  final confidence = _receiptConfidence(
    hasText: text.trim().isNotEmpty,
    hasAmount: amount != null,
    hasMerchant: merchant != null,
    hasDate: occurredAt != null,
    hasPaymentMethod: paymentMethod != null,
  );

  return ReceiptPhotoFields(
    provider: kReceiptOcrProvider,
    status: text.trim().isNotEmpty
        ? ReceiptOcrStatus.parsed
        : ReceiptOcrStatus.failed,
    text: text.trim().isNotEmpty ? text.trim() : null,
    lines: lines,
    amountMinor: amount != null
        ? _toMinor(amount.amount, amount.currency)
        : null,
    currency: amount?.currency ?? currencyFallback,
    merchant: merchant,
    occurredAt: occurredAt,
    paymentMethod: paymentMethod,
    notes: options.fileName != null
        ? 'Receipt OCR: ${options.fileName}'
        : 'Receipt OCR',
    confidence: confidence,
  );
}

ReceiptPhotoFields _emptyReceiptFields(
  ReceiptOcrStatus status,
  ReceiptPhotoOptions options, {
  String? errorMessage,
}) {
  return ReceiptPhotoFields(
    provider: kReceiptOcrProvider,
    status: status,
    lines: const [],
    currency: options.fallbackCurrency.toUpperCase(),
    notes: options.fileName != null
        ? 'Receipt: ${options.fileName}'
        : 'Receipt',
    confidence: 0,
    errorMessage: errorMessage,
  );
}

List<String> _receiptLines(String text) {
  return text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .take(120)
      .toList();
}

AmountCandidate? _extractReceiptAmount(
  List<String> lines,
  String fallbackCurrency,
) {
  final candidates = <AmountCandidate>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fragments = [line];
    final previousLine = i > 0 ? lines[i - 1] : null;
    final nextLine = i < lines.length - 1 ? lines[i + 1] : null;

    if (previousLine != null && _amountKeywordScore(previousLine) > 0) {
      fragments.add('\$previousLine \$line');
    }
    if (nextLine != null && _amountKeywordScore(line) > 0) {
      fragments.add('\$line \$nextLine');
    }

    for (final fragment in fragments) {
      final keywordScore = _amountKeywordScore(fragment);
      final lowerFragment = fragment.toLowerCase();
      final excluded = _amountExcludeKeywords.any(
        (kw) => lowerFragment.contains(kw),
      );
      final matches = _amountMatches(fragment, fallbackCurrency);

      for (final match in matches) {
        if (excluded && keywordScore < 70) continue;
        if (!match.hasCurrency &&
            keywordScore == 0 &&
            _looksLikeDateOrReference(fragment, match.amount)) {
          continue;
        }

        final bottomScore =
            ((i / (lines.length > 1 ? lines.length - 1 : 1)) * 14).round();
        final score =
            keywordScore +
            bottomScore +
            (match.hasCurrency ? 16 : 0) +
            _valueScore(match.amount);
        candidates.add(
          AmountCandidate(
            amount: match.amount,
            currency: match.currency,
            score: score,
          ),
        );
      }
    }
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    if (b.score != a.score) return b.score.compareTo(a.score);
    return b.amount.compareTo(a.amount);
  });
  return candidates.first;
}

class _AmountMatch {
  final double amount;
  final String currency;
  final bool hasCurrency;

  const _AmountMatch(this.amount, this.currency, this.hasCurrency);
}

List<_AmountMatch> _amountMatches(String fragment, String fallbackCurrency) {
  final matches = <_AmountMatch>[];
  final amountPattern = RegExp(
    r'(?:(INR|Rs\.?|GBP|USD|EUR|AED|SGD|AUD|CAD|JPY|[\$\u20b9\u00a3\u20ac\u00a5])\s*)?((?:\d{1,3}(?:[, ]\d{2,3})+|\d+)(?:[.,]\d{1,2})?)(?:\s*(INR|GBP|USD|EUR|AED|SGD|AUD|CAD|JPY))?',
    caseSensitive: false,
  );

  for (final match in amountPattern.allMatches(fragment)) {
    final rawAmount = match.group(2);
    if (rawAmount == null || rawAmount.isEmpty) continue;

    final amount = _parseAmountValue(rawAmount);
    if (amount.isNaN ||
        amount.isInfinite ||
        amount <= 0 ||
        amount > 100000000) {
      continue;
    }

    final hasPrefix = match.group(1) != null;
    final hasSuffix = match.group(3) != null;
    if (!hasPrefix &&
        !hasSuffix &&
        amount % 1 == 0 &&
        amount >= 1900 &&
        amount <= 2100) {
      continue;
    }

    final currency =
        _currencyFromToken(match.group(1) ?? match.group(3)) ??
        fallbackCurrency;
    matches.add(_AmountMatch(amount, currency, hasPrefix || hasSuffix));
  }
  return matches;
}

double _parseAmountValue(String value) {
  final compactValue = value.replaceAll(RegExp(r'\s'), '');
  if (!compactValue.contains('.') && compactValue.contains(',')) {
    final parts = compactValue.split(',');
    final integerPart = parts[0];
    final decimalPart = parts[1];
    if (parts.length == 2 &&
        decimalPart.length == 2 &&
        integerPart.length <= 3) {
      return double.tryParse('\$integerPart.\$decimalPart') ?? double.nan;
    }
  }
  return double.tryParse(compactValue.replaceAll(',', '')) ?? double.nan;
}

String? _currencyFromToken(String? token) {
  if (token == null) return null;
  final normalizedToken = token.trim().toUpperCase();
  if (normalizedToken == '\u20b9' || normalizedToken.startsWith('RS')) {
    return 'INR';
  }
  if (normalizedToken == '\u00a3') return 'GBP';
  if (normalizedToken == '\$') return 'USD';
  if (normalizedToken == '\u20ac') return 'EUR';
  if (normalizedToken == '\u00a5') return 'JPY';
  return normalizedToken;
}

int _amountKeywordScore(String fragment) {
  final lowerFragment = fragment.toLowerCase();
  if (_preciseTotalKeywords.any((kw) => lowerFragment.contains(kw))) return 90;
  if (RegExp(r'\btotal\b').hasMatch(lowerFragment)) return 72;
  if (_looseTotalKeywords.any((kw) => lowerFragment.contains(kw))) return 44;
  return 0;
}

int _valueScore(double amount) {
  if (amount >= 50 && amount <= 500000) return 8;
  if (amount > 0 && amount < 50) return 2;
  return 0;
}

bool _looksLikeDateOrReference(String fragment, double amount) {
  if (RegExp(r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(fragment)) {
    return true;
  }
  if (RegExp(r'\d{4}[./-]\d{1,2}[./-]\d{1,2}').hasMatch(fragment)) return true;
  if (RegExp(
    r'\b(invoice|bill|receipt|gstin|phone|mobile|order|ref|terminal)\b',
    caseSensitive: false,
  ).hasMatch(fragment)) {
    return true;
  }
  return amount % 1 == 0 && amount.truncate().toString().length >= 6;
}

String? _extractReceiptMerchant(List<String> lines) {
  final labeledLines = lines.take(25).toList();
  for (final line in labeledLines) {
    final match = RegExp(
      r'\b(?:merchant|seller|store|outlet|vendor)\s*[:\-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) {
      final merchant = match.group(1);
      if (merchant != null && _isMerchantLine(merchant)) {
        return _cleanMerchantLine(merchant);
      }
    }
  }

  for (final line in lines.take(12)) {
    final cleanedLine = _cleanMerchantLine(line);
    if (_isMerchantLine(cleanedLine)) return cleanedLine;
  }
  return null;
}

String _cleanMerchantLine(String line) {
  var cleaned = line.replaceAll(
    RegExp(r'^m/s\.?\s+', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'^[#*\-:.,\s]+'), '');
  cleaned = cleaned.replaceAll(RegExp(r'[#*\-:.,\s]+$'), '');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.length > 80) cleaned = cleaned.substring(0, 80);
  return cleaned;
}

bool _isMerchantLine(String line) {
  final cleanedLine = _cleanMerchantLine(line);
  final lowerLine = cleanedLine.toLowerCase();
  if (cleanedLine.length < 2 || cleanedLine.length > 80) return false;
  if (_merchantExcludeKeywords.any((kw) => lowerLine.contains(kw))) {
    return false;
  }
  if (_amountMatches(cleanedLine, kDefaultCurrency).isNotEmpty) return false;
  if (RegExp(r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(cleanedLine)) {
    return false;
  }
  if (RegExp(r'^[\d\W_]+$').hasMatch(cleanedLine)) return false;

  final digitCount = RegExp(r'\d').allMatches(cleanedLine).length;
  return (digitCount / cleanedLine.length) < 0.35;
}

String? _extractReceiptDate(
  List<String> lines,
  String fallbackCurrency,
  String fallbackOccurredAt,
) {
  final fallbackDate = DateTime.tryParse(fallbackOccurredAt) ?? DateTime.now();
  final fallbackHour = fallbackDate.hour;
  final fallbackMinute = fallbackDate.minute;
  final candidates = <ParsedDateParts>[];
  final preferDayFirst = !['USD', 'CAD'].contains(fallbackCurrency);

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final timeParts = _extractTimeParts(line);
    candidates.addAll(
      _numericDateCandidates(line, preferDayFirst, i, timeParts),
    );
    candidates.addAll(_monthNameDateCandidates(line, i, timeParts));
  }

  final validCandidates = candidates
      .where((c) => _isValidDateParts(c.year, c.month, c.day))
      .toList();
  if (validCandidates.isEmpty) return null;

  validCandidates.sort((a, b) => b.score.compareTo(a.score));
  final selected = validCandidates.first;

  final date = DateTime(
    selected.year,
    selected.month,
    selected.day,
    selected.hour ?? fallbackHour,
    selected.minute ?? fallbackMinute,
  );
  return date.toUtc().toIso8601String();
}

class _TimeParts {
  final int hour;
  final int minute;
  const _TimeParts(this.hour, this.minute);
}

_TimeParts? _extractTimeParts(String line) {
  final match = RegExp(
    r'\b(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?\b',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final meridiem = match.group(3)?.toUpperCase();
  if (meridiem == 'PM' && hour < 12) hour += 12;
  if (meridiem == 'AM' && hour == 12) hour = 0;
  if (hour > 23 || minute > 59) return null;
  return _TimeParts(hour, minute);
}

List<ParsedDateParts> _numericDateCandidates(
  String line,
  bool preferDayFirst,
  int lineIndex,
  _TimeParts? timeParts,
) {
  final candidates = <ParsedDateParts>[];
  final isoPattern = RegExp(
    r'\b(19\d{2}|20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b',
  );

  for (final match in isoPattern.allMatches(line)) {
    candidates.add(
      ParsedDateParts(
        year: int.parse(match.group(1)!),
        month: int.parse(match.group(2)!),
        day: int.parse(match.group(3)!),
        hour: timeParts?.hour,
        minute: timeParts?.minute,
        score: _dateLineScore(line, lineIndex),
      ),
    );
  }

  final datePattern = RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b');
  for (final match in datePattern.allMatches(line)) {
    final firstPart = int.parse(match.group(1)!);
    final secondPart = int.parse(match.group(2)!);
    final year = _normalizeYear(int.parse(match.group(3)!));
    final dayFirst = firstPart > 12 || (secondPart <= 12 && preferDayFirst);
    candidates.add(
      ParsedDateParts(
        year: year,
        month: dayFirst ? secondPart : firstPart,
        day: dayFirst ? firstPart : secondPart,
        hour: timeParts?.hour,
        minute: timeParts?.minute,
        score: _dateLineScore(line, lineIndex),
      ),
    );
  }
  return candidates;
}

List<ParsedDateParts> _monthNameDateCandidates(
  String line,
  int lineIndex,
  _TimeParts? timeParts,
) {
  final candidates = <ParsedDateParts>[];
  final dayMonthPattern = RegExp(
    r'\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s*,?\s*(\d{2,4})\b',
    caseSensitive: false,
  );

  for (final match in dayMonthPattern.allMatches(line)) {
    final monthToken = match.group(2)?.toLowerCase();
    final month = monthToken != null ? _months[monthToken] : null;
    if (month == null) continue;
    candidates.add(
      ParsedDateParts(
        year: _normalizeYear(int.parse(match.group(3)!)),
        month: month,
        day: int.parse(match.group(1)!),
        hour: timeParts?.hour,
        minute: timeParts?.minute,
        score: _dateLineScore(line, lineIndex),
      ),
    );
  }

  final monthDayPattern = RegExp(
    r'\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\s*,?\s*(\d{2,4})\b',
    caseSensitive: false,
  );
  for (final match in monthDayPattern.allMatches(line)) {
    final monthToken = match.group(1)?.toLowerCase();
    final month = monthToken != null ? _months[monthToken] : null;
    if (month == null) continue;
    candidates.add(
      ParsedDateParts(
        year: _normalizeYear(int.parse(match.group(3)!)),
        month: month,
        day: int.parse(match.group(2)!),
        hour: timeParts?.hour,
        minute: timeParts?.minute,
        score: _dateLineScore(line, lineIndex),
      ),
    );
  }
  return candidates;
}

int _dateLineScore(String line, int lineIndex) {
  final lowerLine = line.toLowerCase();
  final labelScore =
      RegExp(
        r'\b(date|time|bill date|invoice date|txn date)\b',
      ).hasMatch(lowerLine)
      ? 40
      : 0;
  return 80 + labelScore - (lineIndex < 25 ? lineIndex : 25);
}

int _normalizeYear(int year) {
  if (year < 100) return year >= 70 ? 1900 + year : 2000 + year;
  return year;
}

bool _isValidDateParts(int year, int month, int day) {
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > 31) return false;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

String? _extractReceiptPaymentMethod(List<String> lines) {
  final text = lines.join(' ').toLowerCase();
  if (RegExp(r'\b(upi|gpay|google pay|phonepe|paytm|bhim)\b').hasMatch(text)) {
    return 'UPI';
  }
  if (RegExp(
    r'\b(visa|mastercard|master card|amex|credit card|debit card|card)\b',
  ).hasMatch(text)) {
    return 'Card';
  }
  if (RegExp(r'\bcash\b').hasMatch(text)) return 'Cash';
  if (RegExp(r'\bwallet\b').hasMatch(text)) return 'Wallet';
  return null;
}

int _receiptConfidence({
  required bool hasText,
  required bool hasAmount,
  required bool hasMerchant,
  required bool hasDate,
  required bool hasPaymentMethod,
}) {
  if (!hasText) return 0;
  var confidence = 34;
  if (hasAmount) confidence += 34;
  if (hasMerchant) confidence += 14;
  if (hasDate) confidence += 14;
  if (hasPaymentMethod) confidence += 4;
  return confidence > 92 ? 92 : confidence;
}

int _toMinor(double amount, String currencyCode) {
  // We mimic the TS `toMinor` from @1wallet/domain/money here.
  // Generally, most currencies have 2 decimal places.
  // JPY has 0.
  final isZeroDecimal = [
    'JPY',
    'VND',
    'KRW',
  ].contains(currencyCode.toUpperCase());
  if (isZeroDecimal) {
    return amount.round();
  }
  return (amount * 100).round();
}
