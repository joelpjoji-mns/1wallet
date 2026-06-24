import '../data/ledger_models.dart';

class ParsedWalletCsvRow {
  const ParsedWalletCsvRow({
    required this.rowNumber,
    required this.accountName,
    required this.amount,
    required this.type,
    this.categoryName,
    this.notes,
    this.occurredAt,
  });

  final int rowNumber;
  final String accountName;
  final Money amount;
  final String type;
  final String? categoryName;
  final String? notes;
  final DateTime? occurredAt;
}

class ParsedWalletCsvResult {
  const ParsedWalletCsvResult({required this.rows});

  final List<ParsedWalletCsvRow> rows;
}

class WalletCsvColumnMapping {
  const WalletCsvColumnMapping({
    this.hasHeader = false,
    this.dateColumn,
    this.accountColumn,
    this.amountColumn,
    this.categoryColumn,
    this.notesColumn,
    this.typeColumn,
    this.currencyColumn,
  });

  final bool hasHeader;
  final int? dateColumn;
  final int? accountColumn;
  final int? amountColumn;
  final int? categoryColumn;
  final int? notesColumn;
  final int? typeColumn;
  final int? currencyColumn;
}

ParsedWalletCsvResult parseWalletCsv(
  String rawCsv, {
  String fallbackCurrency = kDefaultCurrency,
  WalletCsvColumnMapping? mapping,
}) {
  final lines = rawCsv
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return const ParsedWalletCsvResult(rows: []);
  }

  final header = _splitCsvLine(lines.first).map(_normalizeHeader).toList();
  final hasHeader = mapping?.hasHeader ?? _hasKnownHeader(header);
  final startIndex = hasHeader ? 1 : 0;
  final indexes = mapping == null
      ? (hasHeader ? _headerIndexes(header) : _defaultIndexes())
      : _mappingIndexes(mapping);
  final rows = <ParsedWalletCsvRow>[];

  for (var index = startIndex; index < lines.length; index++) {
    final values = _splitCsvLine(lines[index]);
    final rowNumber = index + 1;
    final rawAmount = _value(values, indexes['amount']);
    final amountMinor = _parseAmountMinor(rawAmount);
    if (amountMinor == null) {
      continue;
    }

    final typeValue = _value(values, indexes['type']).toLowerCase();
    final inferredType = typeValue.contains('income') || amountMinor > 0
        ? 'income'
        : 'expense';
    final type = typeValue == 'transfer' ? 'transfer' : inferredType;
    final accountName = _value(values, indexes['account']);
    final currency = _value(values, indexes['currency']).isEmpty
        ? fallbackCurrency
        : _value(values, indexes['currency']).toUpperCase();
    final date = _parseDate(_value(values, indexes['date']));

    rows.add(
      ParsedWalletCsvRow(
        rowNumber: rowNumber,
        accountName: accountName,
        amount: Money(amountMinor: amountMinor.abs(), currency: currency),
        type: type,
        categoryName: _blankToNull(_value(values, indexes['category'])),
        notes: _blankToNull(_value(values, indexes['notes'])),
        occurredAt: date,
      ),
    );
  }

  return ParsedWalletCsvResult(rows: rows);
}

bool _hasKnownHeader(List<String> header) {
  return header.contains('amount') ||
      header.contains('account') ||
      header.contains('date');
}

Map<String, int> _headerIndexes(List<String> header) {
  int firstOf(List<String> names) {
    for (final name in names) {
      final index = header.indexOf(name);
      if (index != -1) return index;
    }
    return -1;
  }

  return {
    'date': firstOf(['date', 'occurredat', 'time']),
    'account': firstOf(['account', 'wallet', 'sourceaccount']),
    'amount': firstOf(['amount', 'value', 'money']),
    'category': firstOf(['category', 'label']),
    'notes': firstOf(['notes', 'note', 'description', 'memo']),
    'type': firstOf(['type', 'kind']),
    'currency': firstOf(['currency', 'ccy']),
  };
}

Map<String, int> _defaultIndexes() {
  return {
    'date': 0,
    'account': 1,
    'amount': 2,
    'category': 3,
    'notes': 4,
    'type': 5,
    'currency': 6,
  };
}

Map<String, int> _mappingIndexes(WalletCsvColumnMapping mapping) {
  return {
    'date': _columnToIndex(mapping.dateColumn),
    'account': _columnToIndex(mapping.accountColumn),
    'amount': _columnToIndex(mapping.amountColumn),
    'category': _columnToIndex(mapping.categoryColumn),
    'notes': _columnToIndex(mapping.notesColumn),
    'type': _columnToIndex(mapping.typeColumn),
    'currency': _columnToIndex(mapping.currencyColumn),
  };
}

int _columnToIndex(int? column) {
  if (column == null || column <= 0) return -1;
  return column - 1;
}

String _normalizeHeader(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

List<String> _splitCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == '"') {
      if (inQuotes && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char == ',' && !inQuotes) {
      values.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  values.add(buffer.toString().trim());
  return values;
}

String _value(List<String> values, int? index) {
  if (index == null || index < 0 || index >= values.length) return '';
  return values[index].trim();
}

int? _parseAmountMinor(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[^0-9.\-]'), '')
      .replaceAll(RegExp(r'(?<!^)-'), '');
  if (cleaned.isEmpty || cleaned == '-') return null;
  final parsed = double.tryParse(cleaned);
  if (parsed == null) return null;
  return (parsed * 100).round();
}

DateTime? _parseDate(String value) {
  if (value.trim().isEmpty) return null;
  final direct = DateTime.tryParse(value.trim());
  if (direct != null) return direct;

  // Replace slashes with dashes to help tryParse, or match manually
  var cleaned = value.trim().replaceAll('/', '-');
  final directCleaned = DateTime.tryParse(cleaned);
  if (directCleaned != null) return directCleaned;

  // Match DD-MM-YYYY or MM-DD-YYYY with optional time
  final match = RegExp(
    r'^(\d{1,2})[-](\d{1,2})[-](\d{2,4})(?:\s+.*)?$',
  ).firstMatch(cleaned);

  if (match == null) return null;
  final part1 = int.tryParse(match.group(1)!);
  final part2 = int.tryParse(match.group(2)!);
  final yearValue = int.tryParse(match.group(3)!);
  if (part1 == null || part2 == null || yearValue == null) return null;

  final year = yearValue < 100 ? 2000 + yearValue : yearValue;

  // Try to intelligently guess month vs day (if part2 > 12, it must be the day, so format is MM-DD)
  // Default to DD-MM
  var day = part1;
  var month = part2;
  if (part2 > 12) {
    month = part1;
    day = part2;
  }

  // Safe bounds check
  if (month > 12 || month < 1) return null;
  if (day > 31 || day < 1) return null;

  return DateTime(year, month, day);
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
