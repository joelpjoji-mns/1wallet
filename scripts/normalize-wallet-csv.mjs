#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join } from 'node:path';

const OUTPUT_HEADERS = [
  'account',
  'category',
  'currency',
  'amount',
  'ref_currency_amount',
  'type',
  'payment_type',
  'note',
  'date',
  'transfer',
  'payee',
  'labels',
];

const HEADER_ALIASES = new Map([
  ['account', ['account', 'account_name', 'wallet', 'wallet_account']],
  ['category', ['category', 'category_name']],
  ['currency', ['currency', 'currency_code']],
  ['amount', ['amount', 'value']],
  [
    'ref_currency_amount',
    ['ref_currency_amount', 'reference_amount', 'base_amount', 'base_currency_amount'],
  ],
  ['type', ['type', 'transaction_type']],
  ['payment_type', ['payment_type', 'payment_method', 'method']],
  ['note', ['note', 'notes', 'description', 'memo']],
  ['date', ['date', 'datetime', 'occurred_at', 'created_at']],
  ['transfer', ['transfer', 'is_transfer']],
  ['payee', ['payee', 'merchant', 'person']],
  ['labels', ['labels', 'tags']],
]);

const [, , inputPath, outputPathArg] = process.argv;

if (!inputPath) {
  console.error('Usage: node scripts/normalize-wallet-csv.mjs <input.csv> [output.csv]');
  process.exit(1);
}

const source = readFileSync(inputPath, 'utf8').replace(/^\uFEFF/, '');
const lines = source.split(/\r?\n/).filter((line) => line.trim().length > 0);
if (lines.length === 0) {
  throw new Error(`No CSV rows found in ${inputPath}`);
}

const delimiter = detectDelimiter(lines[0]);
const inputHeaders = parseCsvLine(lines[0], delimiter).map(normalizeHeader);
const headerIndex = buildHeaderIndex(inputHeaders);
const missing = OUTPUT_HEADERS.filter((header) => !headerIndex.has(header));
if (missing.length > 0) {
  throw new Error(`Missing required Wallet CSV columns: ${missing.join(', ')}`);
}

const accepted = [];
const rejected = [];
for (const [lineIndex, line] of lines.slice(1).entries()) {
  const cells = parseCsvLine(line, delimiter);
  const raw = Object.fromEntries(
    OUTPUT_HEADERS.map((header) => [header, cells[headerIndex.get(header)] ?? '']),
  );
  const normalized = normalizeRow(raw);
  if (normalized.reason) {
    rejected.push({ line: lineIndex + 2, reason: normalized.reason, ...raw });
  } else {
    accepted.push(normalized.row);
  }
}

const parsedInput = parseOutputPath(inputPath, outputPathArg);
writeFileSync(parsedInput.outputPath, serializeRows(OUTPUT_HEADERS, accepted), 'utf8');
writeFileSync(
  parsedInput.rejectedPath,
  serializeRows(['line', 'reason', ...OUTPUT_HEADERS], rejected),
  'utf8',
);

console.log(`Normalized ${accepted.length} rows -> ${parsedInput.outputPath}`);
console.log(`Rejected ${rejected.length} rows -> ${parsedInput.rejectedPath}`);

function detectDelimiter(headerLine) {
  const semicolonCount = parseCsvLine(headerLine, ';').length;
  const commaCount = parseCsvLine(headerLine, ',').length;
  return semicolonCount >= commaCount ? ';' : ',';
}

function buildHeaderIndex(inputHeaders) {
  const index = new Map();
  for (const outputHeader of OUTPUT_HEADERS) {
    const aliases = HEADER_ALIASES.get(outputHeader) ?? [outputHeader];
    const matchIndex = inputHeaders.findIndex((header) => aliases.includes(header));
    if (matchIndex >= 0) index.set(outputHeader, matchIndex);
  }
  return index;
}

function normalizeRow(raw) {
  const account = clean(raw.account);
  const category = clean(raw.category);
  const currency = clean(raw.currency).toUpperCase();
  const amount = parseAmount(raw.amount);
  const refCurrencyAmount = parseAmount(raw.ref_currency_amount);
  const type = normalizeType(raw.type);
  const date = normalizeDate(raw.date);
  const transfer = normalizeBoolean(raw.transfer);

  if (!account) return { reason: 'missing account' };
  if (!category) return { reason: 'missing category' };
  if (!currency) return { reason: 'missing currency' };
  if (amount === undefined || amount <= 0) return { reason: 'invalid amount' };
  if (!type) return { reason: 'invalid type' };
  if (!date) return { reason: 'invalid date' };

  const referenceAmount = refCurrencyAmount ?? (currency === 'INR' ? amount : undefined);
  return {
    row: {
      account,
      category,
      currency,
      amount: formatDecimal(amount),
      ref_currency_amount: referenceAmount === undefined ? '' : formatDecimal(referenceAmount),
      type,
      payment_type: clean(raw.payment_type),
      note: clean(raw.note),
      date,
      transfer: transfer ? 'true' : 'false',
      payee: clean(raw.payee),
      labels: normalizeLabels(raw.labels),
    },
  };
}

function parseCsvLine(line, delimiter) {
  const cells = [];
  let value = '';
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];
    if (char === '"') {
      if (quoted && next === '"') {
        value += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
      continue;
    }
    if (char === delimiter && !quoted) {
      cells.push(value.trim());
      value = '';
      continue;
    }
    value += char;
  }
  cells.push(value.trim());
  return cells;
}

function serializeRows(headers, rows) {
  const output = [headers.join(';')];
  for (const row of rows) {
    output.push(headers.map((header) => quoteCell(String(row[header] ?? ''))).join(';'));
  }
  return `${output.join('\n')}\n`;
}

function quoteCell(value) {
  if (!/[;"\n\r]/.test(value)) return value;
  return `"${value.replace(/"/g, '""')}"`;
}

function parseOutputPath(sourcePath, requestedPath) {
  if (requestedPath) {
    return {
      outputPath: requestedPath,
      rejectedPath: rejectedPathFor(requestedPath),
    };
  }
  const extension = extname(sourcePath) || '.csv';
  const name = basename(sourcePath, extension);
  const folder = dirname(sourcePath);
  const outputPath = join(folder, `${name}.normalized${extension}`);
  return { outputPath, rejectedPath: rejectedPathFor(outputPath) };
}

function rejectedPathFor(outputPath) {
  const extension = extname(outputPath) || '.csv';
  return join(dirname(outputPath), `${basename(outputPath, extension)}.rejected${extension}`);
}

function normalizeHeader(value) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
}

function clean(value) {
  return String(value ?? '').trim();
}

function parseAmount(value) {
  const normalized = clean(value).replace(/,/g, '');
  if (!normalized) return undefined;
  const amount = Number(normalized);
  return Number.isFinite(amount) ? amount : undefined;
}

function normalizeType(value) {
  const normalized = clean(value).toLowerCase();
  if (normalized === 'expense' || normalized === 'debit' || normalized === 'spent')
    return 'Expense';
  if (normalized === 'income' || normalized === 'credit' || normalized === 'received')
    return 'Income';
  return undefined;
}

function normalizeDate(value) {
  const parsed = new Date(clean(value));
  return Number.isNaN(parsed.getTime()) ? undefined : parsed.toISOString();
}

function normalizeBoolean(value) {
  const normalized = clean(value).toLowerCase();
  return (
    normalized === 'true' || normalized === 'yes' || normalized === '1' || normalized === 'transfer'
  );
}

function normalizeLabels(value) {
  return clean(value)
    .split(/[|,]/)
    .map((label) => label.trim())
    .filter(Boolean)
    .join('|');
}

function formatDecimal(value) {
  return String(Number(value.toFixed(8))).replace(/\.0+$/, '');
}
