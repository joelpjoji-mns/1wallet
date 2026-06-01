import { normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { CurrencyCode } from '@1wallet/domain/money';
import TextRecognition, {
    TextRecognitionScript,
    type TextRecognitionResult,
} from '@react-native-ml-kit/text-recognition';
import type { ReceiptCaptureAsset } from './receiptCapture';

export const RECEIPT_OCR_PROVIDER = 'mlkit-text-recognition';

export type ReceiptOcrStatus = 'parsed' | 'skipped' | 'failed';

export interface ReceiptPhotoFields {
  provider: string;
  status: ReceiptOcrStatus;
  text?: string;
  lines: string[];
  amountMinor?: number;
  currency?: CurrencyCode;
  merchant?: string;
  occurredAt?: string;
  paymentMethod?: string;
  notes?: string;
  confidence: number;
  warnings: string[];
  errorMessage?: string;
}

export interface ReceiptPhotoOptions {
  fallbackCurrency: CurrencyCode;
  fallbackOccurredAt: string;
  fileName?: string;
}

interface AmountCandidate {
  amount: number;
  currency: CurrencyCode;
  score: number;
}

interface ParsedDateParts {
  year: number;
  month: number;
  day: number;
  hour?: number;
  minute?: number;
  score: number;
}

const PRECISE_TOTAL_KEYWORDS = [
  'grand total',
  'amount paid',
  'amount payable',
  'net payable',
  'total paid',
  'total due',
  'balance due',
  'final total',
];

const LOOSE_TOTAL_KEYWORDS = ['total', 'paid', 'payable', 'due'];

const AMOUNT_EXCLUDE_KEYWORDS = [
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

const MERCHANT_EXCLUDE_KEYWORDS = [
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

const MONTHS: Record<string, number> = {
  jan: 1,
  january: 1,
  feb: 2,
  february: 2,
  mar: 3,
  march: 3,
  apr: 4,
  april: 4,
  may: 5,
  jun: 6,
  june: 6,
  jul: 7,
  july: 7,
  aug: 8,
  august: 8,
  sep: 9,
  sept: 9,
  september: 9,
  oct: 10,
  october: 10,
  nov: 11,
  november: 11,
  dec: 12,
  december: 12,
};

export async function extractReceiptFieldsFromPhoto(
  asset: ReceiptCaptureAsset,
  options: ReceiptPhotoOptions,
): Promise<ReceiptPhotoFields> {
  if (!isImageReceiptAsset(asset)) {
    return emptyReceiptFields('skipped', options, ['receipt OCR supports image photos only']);
  }

  try {
    const result = await TextRecognition.recognize(asset.uri, TextRecognitionScript.LATIN);
    return parseReceiptText(result, options);
  } catch (error) {
    return emptyReceiptFields(
      'failed',
      options,
      ['receipt OCR unavailable; review fields manually'],
      (error as Error).message,
    );
  }
}

export function parseReceiptText(
  recognition: Pick<TextRecognitionResult, 'text'> | string,
  options: ReceiptPhotoOptions,
): ReceiptPhotoFields {
  const text = typeof recognition === 'string' ? recognition : recognition.text;
  const lines = receiptLines(text);
  const currencyFallback = normalizeCurrencyCode(options.fallbackCurrency);
  const amount = extractReceiptAmount(lines, currencyFallback);
  const merchant = extractReceiptMerchant(lines);
  const occurredAt = extractReceiptDate(lines, currencyFallback, options.fallbackOccurredAt);
  const paymentMethod = extractReceiptPaymentMethod(lines);
  const warnings: string[] = [];

  if (!text.trim()) warnings.push('receipt OCR returned no text');
  if (!amount) warnings.push('receipt amount needs review');
  if (!merchant) warnings.push('receipt merchant needs review');
  if (!occurredAt) warnings.push('receipt date needs review');

  const confidence = receiptConfidence({
    hasText: Boolean(text.trim()),
    hasAmount: Boolean(amount),
    hasMerchant: Boolean(merchant),
    hasDate: Boolean(occurredAt),
    hasPaymentMethod: Boolean(paymentMethod),
  });

  return {
    provider: RECEIPT_OCR_PROVIDER,
    status: text.trim() ? 'parsed' : 'failed',
    text: text.trim() || undefined,
    lines,
    amountMinor: amount ? toMinor(amount.amount, amount.currency) : undefined,
    currency: amount?.currency ?? currencyFallback,
    merchant,
    occurredAt,
    paymentMethod,
    notes: options.fileName ? `Receipt OCR: ${options.fileName}` : 'Receipt OCR',
    confidence,
    warnings,
  };
}

function emptyReceiptFields(
  status: ReceiptOcrStatus,
  options: ReceiptPhotoOptions,
  warnings: string[],
  errorMessage?: string,
): ReceiptPhotoFields {
  return {
    provider: RECEIPT_OCR_PROVIDER,
    status,
    lines: [],
    currency: normalizeCurrencyCode(options.fallbackCurrency),
    notes: options.fileName ? `Receipt: ${options.fileName}` : 'Receipt',
    confidence: 0,
    warnings,
    errorMessage,
  };
}

function isImageReceiptAsset(asset: ReceiptCaptureAsset): boolean {
  if (asset.mimeType?.toLowerCase().startsWith('image/')) return true;
  if (asset.mimeType?.toLowerCase().includes('pdf')) return false;
  if (/\.pdf(?:\?|$)/i.test(asset.uri) || /\.pdf$/i.test(asset.name)) return false;
  return (
    asset.source === 'camera' ||
    asset.source === 'library' ||
    /\.(jpe?g|png|webp)$/i.test(asset.name)
  );
}

function receiptLines(text: string): string[] {
  return text
    .split(/\r?\n/g)
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .slice(0, 120);
}

function extractReceiptAmount(
  lines: string[],
  fallbackCurrency: CurrencyCode,
): AmountCandidate | undefined {
  const candidates: AmountCandidate[] = [];

  lines.forEach((line, lineIndex) => {
    const fragments = [line];
    const previousLine = lines[lineIndex - 1];
    const nextLine = lines[lineIndex + 1];
    if (previousLine && amountKeywordScore(previousLine) > 0)
      fragments.push(`${previousLine} ${line}`);
    if (nextLine && amountKeywordScore(line) > 0) fragments.push(`${line} ${nextLine}`);

    fragments.forEach((fragment) => {
      const keywordScore = amountKeywordScore(fragment);
      const lowerFragment = fragment.toLowerCase();
      const excluded = AMOUNT_EXCLUDE_KEYWORDS.some((keyword) => lowerFragment.includes(keyword));
      const matches = amountMatches(fragment, fallbackCurrency);
      matches.forEach((match) => {
        if (excluded && keywordScore < 70) return;
        if (
          !match.hasCurrency &&
          keywordScore === 0 &&
          looksLikeDateOrReference(fragment, match.amount)
        ) {
          return;
        }
        const bottomScore = Math.round((lineIndex / Math.max(lines.length - 1, 1)) * 14);
        const score =
          keywordScore + bottomScore + (match.hasCurrency ? 16 : 0) + valueScore(match.amount);
        candidates.push({ amount: match.amount, currency: match.currency, score });
      });
    });
  });

  return candidates.sort(
    (first, second) => second.score - first.score || second.amount - first.amount,
  )[0];
}

function amountMatches(fragment: string, fallbackCurrency: CurrencyCode) {
  const matches: { amount: number; currency: CurrencyCode; hasCurrency: boolean }[] = [];
  const amountPattern =
    /(?:(INR|Rs\.?|GBP|USD|EUR|AED|SGD|AUD|CAD|JPY|[$\u20b9\u00a3\u20ac\u00a5])\s*)?((?:\d{1,3}(?:[, ]\d{2,3})+|\d+)(?:[.,]\d{1,2})?)(?:\s*(INR|GBP|USD|EUR|AED|SGD|AUD|CAD|JPY))?/gi;
  let amountMatch: RegExpExecArray | null;
  while ((amountMatch = amountPattern.exec(fragment)) !== null) {
    const rawAmount = amountMatch[2];
    if (!rawAmount) continue;
    const amount = parseAmountValue(rawAmount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 100000000) continue;
    if (
      !amountMatch[1] &&
      !amountMatch[3] &&
      Number.isInteger(amount) &&
      amount >= 1900 &&
      amount <= 2100
    ) {
      continue;
    }
    const currency = currencyFromToken(amountMatch[1] ?? amountMatch[3]) ?? fallbackCurrency;
    matches.push({ amount, currency, hasCurrency: Boolean(amountMatch[1] ?? amountMatch[3]) });
  }
  return matches;
}

function parseAmountValue(value: string): number {
  const compactValue = value.replace(/\s/g, '');
  if (!compactValue.includes('.') && compactValue.includes(',')) {
    const parts = compactValue.split(',');
    const integerPart = parts[0];
    const decimalPart = parts[1];
    if (
      parts.length === 2 &&
      integerPart !== undefined &&
      decimalPart !== undefined &&
      decimalPart.length === 2 &&
      integerPart.length <= 3
    ) {
      return Number(`${integerPart}.${decimalPart}`);
    }
  }
  return Number(compactValue.replace(/,/g, ''));
}

function currencyFromToken(token?: string): CurrencyCode | undefined {
  if (!token) return undefined;
  const normalizedToken = token.trim().toUpperCase();
  if (normalizedToken === '\u20b9' || normalizedToken.startsWith('RS')) return 'INR';
  if (normalizedToken === '\u00a3') return 'GBP';
  if (normalizedToken === '$') return 'USD';
  if (normalizedToken === '\u20ac') return 'EUR';
  if (normalizedToken === '\u00a5') return 'JPY';
  return normalizeCurrencyCode(normalizedToken);
}

function amountKeywordScore(fragment: string): number {
  const lowerFragment = fragment.toLowerCase();
  if (PRECISE_TOTAL_KEYWORDS.some((keyword) => lowerFragment.includes(keyword))) return 90;
  if (/\btotal\b/.test(lowerFragment)) return 72;
  if (LOOSE_TOTAL_KEYWORDS.some((keyword) => lowerFragment.includes(keyword))) return 44;
  return 0;
}

function valueScore(amount: number): number {
  if (amount >= 50 && amount <= 500000) return 8;
  if (amount > 0 && amount < 50) return 2;
  return 0;
}

function looksLikeDateOrReference(fragment: string, amount: number): boolean {
  if (/\d{1,2}[./-]\d{1,2}[./-]\d{2,4}/.test(fragment)) return true;
  if (/\d{4}[./-]\d{1,2}[./-]\d{1,2}/.test(fragment)) return true;
  if (/\b(invoice|bill|receipt|gstin|phone|mobile|order|ref|terminal)\b/i.test(fragment))
    return true;
  return Number.isInteger(amount) && String(Math.trunc(amount)).length >= 6;
}

function extractReceiptMerchant(lines: string[]): string | undefined {
  const labeledMerchant = lines
    .slice(0, 25)
    .map((line) => line.match(/\b(?:merchant|seller|store|outlet|vendor)\s*[:\-]\s*(.+)$/i)?.[1])
    .find((line): line is string => Boolean(line && isMerchantLine(line)));
  if (labeledMerchant) return cleanMerchantLine(labeledMerchant);

  return lines
    .slice(0, 12)
    .map(cleanMerchantLine)
    .find((line) => isMerchantLine(line));
}

function cleanMerchantLine(line: string): string {
  return line
    .replace(/^m\/s\.?\s+/i, '')
    .replace(/^[#*\-:.,\s]+/, '')
    .replace(/[#*\-:.,\s]+$/, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80);
}

function isMerchantLine(line: string): boolean {
  const cleanedLine = cleanMerchantLine(line);
  const lowerLine = cleanedLine.toLowerCase();
  if (cleanedLine.length < 2 || cleanedLine.length > 80) return false;
  if (MERCHANT_EXCLUDE_KEYWORDS.some((keyword) => lowerLine.includes(keyword))) return false;
  if (amountMatches(cleanedLine, 'INR').length > 0) return false;
  if (/\d{1,2}[./-]\d{1,2}[./-]\d{2,4}/.test(cleanedLine)) return false;
  if (/^[\d\W_]+$/.test(cleanedLine)) return false;
  const digitCount = (cleanedLine.match(/\d/g) ?? []).length;
  return digitCount / cleanedLine.length < 0.35;
}

function extractReceiptDate(
  lines: string[],
  fallbackCurrency: CurrencyCode,
  fallbackOccurredAt: string,
): string | undefined {
  const fallbackDate = new Date(fallbackOccurredAt);
  const fallbackHour = Number.isFinite(fallbackDate.getTime()) ? fallbackDate.getHours() : 12;
  const fallbackMinute = Number.isFinite(fallbackDate.getTime()) ? fallbackDate.getMinutes() : 0;
  const candidates: ParsedDateParts[] = [];
  const preferDayFirst = !['USD', 'CAD'].includes(normalizeCurrencyCode(fallbackCurrency));

  lines.forEach((line, lineIndex) => {
    const timeParts = extractTimeParts(line);
    candidates.push(
      ...numericDateCandidates(line, preferDayFirst, lineIndex, timeParts),
      ...monthNameDateCandidates(line, lineIndex, timeParts),
    );
  });

  const selected = candidates
    .filter((candidate) => isValidDateParts(candidate.year, candidate.month, candidate.day))
    .sort((first, second) => second.score - first.score)[0];
  if (!selected) return undefined;

  return new Date(
    selected.year,
    selected.month - 1,
    selected.day,
    selected.hour ?? fallbackHour,
    selected.minute ?? fallbackMinute,
  ).toISOString();
}

function numericDateCandidates(
  line: string,
  preferDayFirst: boolean,
  lineIndex: number,
  timeParts?: Pick<ParsedDateParts, 'hour' | 'minute'>,
): ParsedDateParts[] {
  const candidates: ParsedDateParts[] = [];
  const isoPattern = /\b(19\d{2}|20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b/g;
  let isoMatch: RegExpExecArray | null;
  while ((isoMatch = isoPattern.exec(line)) !== null) {
    candidates.push({
      year: Number(isoMatch[1]),
      month: Number(isoMatch[2]),
      day: Number(isoMatch[3]),
      ...timeParts,
      score: dateLineScore(line, lineIndex),
    });
  }

  const datePattern = /\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b/g;
  let dateMatch: RegExpExecArray | null;
  while ((dateMatch = datePattern.exec(line)) !== null) {
    const firstPart = Number(dateMatch[1]);
    const secondPart = Number(dateMatch[2]);
    const year = normalizeYear(Number(dateMatch[3]));
    const dayFirst = firstPart > 12 || (secondPart <= 12 && preferDayFirst);
    candidates.push({
      year,
      month: dayFirst ? secondPart : firstPart,
      day: dayFirst ? firstPart : secondPart,
      ...timeParts,
      score: dateLineScore(line, lineIndex),
    });
  }

  return candidates;
}

function monthNameDateCandidates(
  line: string,
  lineIndex: number,
  timeParts?: Pick<ParsedDateParts, 'hour' | 'minute'>,
): ParsedDateParts[] {
  const candidates: ParsedDateParts[] = [];
  const dayMonthPattern =
    /\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s*,?\s*(\d{2,4})\b/gi;
  let dayMonthMatch: RegExpExecArray | null;
  while ((dayMonthMatch = dayMonthPattern.exec(line)) !== null) {
    const monthToken = dayMonthMatch[2]?.toLowerCase();
    const month = monthToken ? MONTHS[monthToken] : undefined;
    if (!month) continue;
    candidates.push({
      year: normalizeYear(Number(dayMonthMatch[3])),
      month,
      day: Number(dayMonthMatch[1]),
      ...timeParts,
      score: dateLineScore(line, lineIndex),
    });
  }

  const monthDayPattern =
    /\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\s*,?\s*(\d{2,4})\b/gi;
  let monthDayMatch: RegExpExecArray | null;
  while ((monthDayMatch = monthDayPattern.exec(line)) !== null) {
    const monthToken = monthDayMatch[1]?.toLowerCase();
    const month = monthToken ? MONTHS[monthToken] : undefined;
    if (!month) continue;
    candidates.push({
      year: normalizeYear(Number(monthDayMatch[3])),
      month,
      day: Number(monthDayMatch[2]),
      ...timeParts,
      score: dateLineScore(line, lineIndex),
    });
  }

  return candidates;
}

function extractTimeParts(line: string): Pick<ParsedDateParts, 'hour' | 'minute'> | undefined {
  const timeMatch = line.match(/\b(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?\b/i);
  if (!timeMatch) return undefined;
  let hour = Number(timeMatch[1]);
  const minute = Number(timeMatch[2]);
  const meridiem = timeMatch[3]?.toUpperCase();
  if (meridiem === 'PM' && hour < 12) hour += 12;
  if (meridiem === 'AM' && hour === 12) hour = 0;
  if (hour > 23 || minute > 59) return undefined;
  return { hour, minute };
}

function dateLineScore(line: string, lineIndex: number): number {
  const lowerLine = line.toLowerCase();
  const labelScore = /\b(date|time|bill date|invoice date|txn date)\b/.test(lowerLine) ? 40 : 0;
  return 80 + labelScore - Math.min(lineIndex, 25);
}

function normalizeYear(year: number): number {
  if (year < 100) return year >= 70 ? 1900 + year : 2000 + year;
  return year;
}

function isValidDateParts(year: number, month: number, day: number): boolean {
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
}

function extractReceiptPaymentMethod(lines: string[]): string | undefined {
  const text = lines.join(' ').toLowerCase();
  if (/\b(upi|gpay|google pay|phonepe|paytm|bhim)\b/.test(text)) return 'UPI';
  if (/\b(visa|mastercard|master card|amex|credit card|debit card|card)\b/.test(text))
    return 'Card';
  if (/\bcash\b/.test(text)) return 'Cash';
  if (/\bwallet\b/.test(text)) return 'Wallet';
  return undefined;
}

function receiptConfidence({
  hasText,
  hasAmount,
  hasMerchant,
  hasDate,
  hasPaymentMethod,
}: {
  hasText: boolean;
  hasAmount: boolean;
  hasMerchant: boolean;
  hasDate: boolean;
  hasPaymentMethod: boolean;
}): number {
  if (!hasText) return 0;
  let confidence = 34;
  if (hasAmount) confidence += 34;
  if (hasMerchant) confidence += 14;
  if (hasDate) confidence += 14;
  if (hasPaymentMethod) confidence += 4;
  return Math.min(confidence, 92);
}
