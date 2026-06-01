import type { Transaction } from '@1wallet/domain/types';
import type { HomeWidgetDatePreset } from './homeWidgetTypes';

export type DateRange = {
  start?: Date;
  end?: Date;
};

export function dateRangeForPreset(preset: HomeWidgetDatePreset, now = new Date()): DateRange {
  const today = startOfDay(now);
  switch (preset) {
    case 'today':
      return { start: today, end: addDays(today, 1) };
    case 'thisWeek': {
      const start = startOfWeek(today);
      return { start, end: addDays(start, 7) };
    }
    case 'thisMonth': {
      const start = new Date(today.getFullYear(), today.getMonth(), 1);
      return { start, end: new Date(today.getFullYear(), today.getMonth() + 1, 1) };
    }
    case 'lastMonth': {
      const start = new Date(today.getFullYear(), today.getMonth() - 1, 1);
      return { start, end: new Date(today.getFullYear(), today.getMonth(), 1) };
    }
    case 'thisYear': {
      const start = new Date(today.getFullYear(), 0, 1);
      return { start, end: new Date(today.getFullYear() + 1, 0, 1) };
    }
    case 'allTime':
    default:
      return {};
  }
}

export function filterTransactionsByPreset(
  transactions: Transaction[],
  preset: HomeWidgetDatePreset,
): Transaction[] {
  const range = dateRangeForPreset(preset);
  return transactions.filter((transaction) => timestampInRange(transaction.occurredAt, range));
}

export function timestampInRange(value: string, range: DateRange): boolean {
  const time = new Date(value).getTime();
  if (Number.isNaN(time)) return false;
  if (range.start && time < range.start.getTime()) return false;
  if (range.end && time >= range.end.getTime()) return false;
  return true;
}

export function dateRangeSubtitle(preset: HomeWidgetDatePreset): string | undefined {
  const range = dateRangeForPreset(preset);
  if (!range.start || !range.end) return undefined;
  return `${formatDate(range.start)} to ${formatDate(addDays(range.end, -1))}`;
}

function startOfDay(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function startOfWeek(value: Date): Date {
  const day = value.getDay();
  const mondayOffset = day === 0 ? -6 : 1 - day;
  return addDays(value, mondayOffset);
}

function addDays(value: Date, days: number): Date {
  const next = new Date(value);
  next.setDate(next.getDate() + days);
  return next;
}

function formatDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}
