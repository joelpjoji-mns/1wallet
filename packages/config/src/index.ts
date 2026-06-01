export const APP_NAME = '1wallet';

export const FEATURE_FLAGS = {
  notificationCapture: true,
  smsCapture: false,
  emailCapture: false,
  receiptOcr: false,
  sharedWorkspace: false,
  investments: false,
} as const;

export const DEFAULTS = {
  baseCurrency: 'INR',
  locale: 'en-IN',
  startDayOfWeek: 1,
  startDayOfMonth: 1,
} as const;
