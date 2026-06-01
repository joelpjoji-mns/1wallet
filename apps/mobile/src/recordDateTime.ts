export type LocalDateTimeParts = { date: string; time: string };

export function localDateTimeParts(value: Date): LocalDateTimeParts {
  return {
    date: `${value.getFullYear()}-${pad2(value.getMonth() + 1)}-${pad2(value.getDate())}`,
    time: `${pad2(value.getHours())}:${pad2(value.getMinutes())}`,
  };
}

export function localDateTimePartsFromIso(value: string): LocalDateTimeParts {
  const parsed = new Date(value);
  return localDateTimeParts(Number.isNaN(parsed.getTime()) ? new Date() : parsed);
}

export function dateTimeToIso(date: string, time: string, fallback: Date = new Date()): string {
  const parsedDate = parseDateParts(date);
  const parsedTime = parseTimeParts(time);
  if (!parsedDate || !parsedTime) return fallback.toISOString();

  const combined = new Date(
    parsedDate.year,
    parsedDate.month - 1,
    parsedDate.day,
    parsedTime.hours,
    parsedTime.minutes,
    0,
    0,
  );

  if (
    combined.getFullYear() !== parsedDate.year ||
    combined.getMonth() !== parsedDate.month - 1 ||
    combined.getDate() !== parsedDate.day ||
    combined.getHours() !== parsedTime.hours ||
    combined.getMinutes() !== parsedTime.minutes
  ) {
    return fallback.toISOString();
  }

  return combined.toISOString();
}

export function isValidLocalDate(value: string): boolean {
  return Boolean(parseDateParts(value));
}

export function isValidLocalTime(value: string): boolean {
  return Boolean(parseTimeParts(value));
}

export function shiftLocalDate(value: string, days: number): string {
  const parsedDate = parseDateParts(value);
  const base = parsedDate
    ? new Date(parsedDate.year, parsedDate.month - 1, parsedDate.day)
    : new Date();
  base.setDate(base.getDate() + days);
  return localDateTimeParts(base).date;
}

export function formatOrdinalDateLabel(value: string): string {
  const date = parseDateValue(value);
  if (!date) return value.slice(0, 10);
  return `${ordinal(date.getDate())} ${MONTH_NAMES[date.getMonth()]} ${date.getFullYear()}`;
}

export function formatCompactDateLabel(value: string): string {
  const date = parseDateValue(value);
  if (!date) return value.slice(0, 10);
  return `${date.getDate()} ${SHORT_MONTH_NAMES[date.getMonth()]} ${date.getFullYear()}`;
}

export function formatRecordDateLabel(value: string, now: Date = new Date()): string {
  const date = parseDateValue(value);
  if (!date) return value.slice(0, 10);

  const today = startOfLocalDay(now);
  const diffDays = Math.round((today.getTime() - date.getTime()) / 86_400_000);
  if (diffDays === 0) return 'today';
  if (diffDays === 1) return 'yesterday';
  if (diffDays === -1) return 'tomorrow';
  return formatOrdinalDateLabel(localDateTimeParts(date).date);
}

export function formatLocalTime12(value: string): string {
  const parsedTime = parseTimeParts(value);
  if (!parsedTime) return value;
  const period = parsedTime.hours >= 12 ? 'PM' : 'AM';
  const hour = parsedTime.hours % 12 || 12;
  return `${hour}:${pad2(parsedTime.minutes)} ${period}`;
}

const MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const SHORT_MONTH_NAMES = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

function parseDateValue(value: string): Date | null {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    const parsed = parseDateParts(value);
    return parsed ? new Date(parsed.year, parsed.month - 1, parsed.day) : null;
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return startOfLocalDay(parsed);
}

function startOfLocalDay(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function ordinal(value: number): string {
  const mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) return `${value}th`;
  switch (value % 10) {
    case 1:
      return `${value}st`;
    case 2:
      return `${value}nd`;
    case 3:
      return `${value}rd`;
    default:
      return `${value}th`;
  }
}

function parseDateParts(value: string): { year: number; month: number; day: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return null;
  }
  return { year, month, day };
}

function parseTimeParts(value: string): { hours: number; minutes: number } | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return { hours, minutes };
}

function pad2(value: number): string {
  return String(value).padStart(2, '0');
}
