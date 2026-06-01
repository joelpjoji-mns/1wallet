import { z } from 'zod';

export const currencyCodeSchema = z
  .string()
  .length(3)
  .regex(/^[A-Z]{3}$/);

export const moneySchema = z.object({
  amountMinor: z.number().int(),
  currency: currencyCodeSchema,
});

export const accountTypeSchema = z.enum([
  'cash',
  'bank',
  'credit_card',
  'debit_card',
  'wallet',
  'prepaid',
  'loan',
  'lent',
  'investment',
  'savings_goal',
  'overdraft',
  'crypto',
  'other',
]);

export const transactionTypeSchema = z.enum([
  'expense',
  'income',
  'transfer',
  'refund',
  'adjustment',
  'card_payment',
  'loan_repayment',
  'lent',
  'borrowed',
  'investment_buy',
  'investment_sell',
  'fee',
  'interest_in',
  'interest_out',
  'cashback',
]);

export const transactionStatusSchema = z.enum(['cleared', 'pending', 'scheduled', 'void']);

export const transactionSourceSchema = z.enum([
  'manual',
  'recurring',
  'import',
  'notification',
  'sms',
  'email',
  'rule',
  'shared',
  'api',
]);

export const captureCandidateStatusSchema = z.enum([
  'pending',
  'approved',
  'rejected',
  'ignored',
  'auto_posted',
]);

export const captureSourceSchema = z.enum(['notification', 'sms', 'email', 'import', 'api']);

export const accountMatchIdentifierKindSchema = z.enum([
  'account_last4',
  'card_last4',
  'iban_last4',
  'sort_code',
  'upi_vpa',
  'phone_last4',
  'masked_number',
  'customer_ref',
]);

export const accountMatchIdentifierSchema = z.object({
  kind: accountMatchIdentifierKindSchema,
  value: z.string().min(1).max(96),
  label: z.string().max(80).optional(),
  verified: z.boolean().optional(),
});

export const accountMessageSourceHintsSchema = z.object({
  smsSenderIds: z.array(z.string().min(1).max(32)).max(24).optional(),
  emailDomains: z.array(z.string().min(1).max(96)).max(24).optional(),
  keywords: z.array(z.string().min(1).max(64)).max(24).optional(),
});

export const autoCaptureRunSummarySchema = z.object({
  ranAt: z.string(),
  scanned: z.number().int().nonnegative(),
  recognized: z.number().int().nonnegative(),
  posted: z.number().int().nonnegative(),
  queued: z.number().int().nonnegative(),
  duplicates: z.number().int().nonnegative(),
  ignored: z.number().int().nonnegative(),
});

export const autoCapturePreferencesSchema = z.object({
  enabled: z.boolean(),
  autoPost: z.boolean(),
  autoPostConfidence: z.number().int().min(0).max(100),
  sms: z.object({
    enabled: z.boolean(),
    backgroundEnabled: z.boolean(),
    scanLimit: z.number().int().min(25).max(1000),
    triggerKeywords: z.array(z.string().min(1).max(64)).max(80),
    ignoredSenderIds: z.array(z.string().min(1).max(64)).max(80),
    lastRun: autoCaptureRunSummarySchema.optional(),
  }),
});

export const loanKindSchema = z.enum([
  'personal',
  'home',
  'vehicle',
  'education',
  'business',
  'gold',
  'bnpl',
  'overdraft',
  'lent',
  'other',
]);

export const accountLoanDetailsSchema = z.object({
  loanKind: loanKindSchema.optional(),
  principal: moneySchema.optional(),
  disbursedOn: z.string().optional(),
  interestRatePercent: z.number().nonnegative().max(1000).optional(),
  interestRatePeriod: z.enum(['annual', 'monthly']).optional(),
  interestMethod: z.enum(['reducing_balance', 'flat', 'interest_only']).optional(),
  repaymentSourceAccountId: z.string().uuid().optional(),
  repaymentAmount: moneySchema.optional(),
  repaymentStartsOn: z.string().optional(),
  repaymentFrequency: z.enum(['daily', 'weekly', 'monthly', 'yearly']).optional(),
  repaymentInterval: z.number().int().positive().max(365).optional(),
  repaymentDayOfMonth: z.number().int().min(1).max(31).optional(),
  repaymentCount: z.number().int().positive().max(1200).optional(),
  repaymentEndsOn: z.string().optional(),
  autoCreateScheduledRecords: z.boolean().optional(),
  linkedPlannedPaymentRuleId: z.string().uuid().optional(),
  trackingStartsOn: z.string().optional(),
  paidInstallmentsBeforeTracking: z.number().int().nonnegative().max(1200).optional(),
  setupMode: z.enum(['track_from_next', 'backfill_paid']).optional(),
  notes: z.string().max(500).optional(),
});

export const accountCreateSchema = z.object({
  name: z.string().min(1).max(64),
  type: accountTypeSchema,
  currency: currencyCodeSchema,
  openingBalance: moneySchema,
  openingDate: z.string(),
  institution: z.string().max(64).optional(),
  accountNickname: z.string().max(32).optional(),
  loanDetails: accountLoanDetailsSchema.optional(),
  matchIdentifiers: z.array(accountMatchIdentifierSchema).max(32).optional(),
  messageSourceHints: accountMessageSourceHintsSchema.optional(),
  includeInTotals: z.boolean().default(true),
  includeInBudgets: z.boolean().default(true),
  includeInReports: z.boolean().default(true),
  includeInNetWorth: z.boolean().default(true),
  groupName: z.string().max(64).optional(),
  notes: z.string().max(500).optional(),
});

export const transactionCreateSchema = z
  .object({
    type: transactionTypeSchema,
    status: transactionStatusSchema.default('cleared'),
    source: transactionSourceSchema.default('manual'),
    accountId: z.string().uuid(),
    counterAccountId: z.string().uuid().optional(),
    amount: moneySchema.refine((m) => m.amountMinor > 0, {
      message: 'amount must be positive; sign is implied by type',
    }),
    originalAmount: moneySchema.optional(),
    originalFxRate: z.number().positive().optional(),
    counterAmount: moneySchema.optional(),
    counterFxRate: z.number().positive().optional(),
    categoryId: z.string().uuid().optional(),
    merchantId: z.string().uuid().optional(),
    occurredAt: z.string(),
    locationLabel: z.string().max(160).optional(),
    paymentMethod: z.string().max(32).optional(),
    notes: z.string().max(1000).optional(),
    attachments: z
      .array(
        z.object({
          id: z.string().min(1),
          name: z.string().min(1).max(180),
          uri: z.string().min(1),
          mimeType: z.string().max(120).optional(),
          size: z.number().int().nonnegative().optional(),
          width: z.number().int().positive().optional(),
          height: z.number().int().positive().optional(),
          source: z.enum(['camera', 'library', 'file', 'import']),
          createdAt: z.string(),
        }),
      )
      .max(20)
      .optional(),
    tags: z.array(z.string().min(1).max(32)).max(20).optional(),
    personId: z.string().uuid().optional(),
    projectId: z.string().uuid().optional(),
    tripId: z.string().uuid().optional(),
    isReimbursable: z.boolean().default(false),
    isTaxDeductible: z.boolean().default(false),
    isExcludedFromReports: z.boolean().default(false),
    fxRate: z.number().positive().optional(),
    externalRef: z.string().max(128).optional(),
  })
  .superRefine((tx, ctx) => {
    const isTransfer =
      tx.type === 'transfer' || tx.type === 'card_payment' || tx.type === 'loan_repayment';
    if (isTransfer) {
      if (!tx.counterAccountId) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['counterAccountId'],
          message: 'counterAccountId is required for transfer-type transactions',
        });
      } else if (tx.counterAccountId === tx.accountId) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['counterAccountId'],
          message: 'counterAccountId must differ from accountId',
        });
      }
    } else if (tx.counterAccountId) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['counterAccountId'],
        message: 'counterAccountId must be omitted for non-transfer transactions',
      });
    }
  });

export const captureCandidateCreateSchema = z.object({
  source: captureSourceSchema,
  rawPayload: z.record(z.unknown()),
  rawHash: z.string().min(1).max(160).optional(),
  parsedAmountMinor: z.number().int().positive().optional(),
  parsedCurrency: currencyCodeSchema.optional(),
  parsedFxRate: z.number().positive().optional(),
  parsedOriginalAmountMinor: z.number().int().positive().optional(),
  parsedOriginalCurrency: currencyCodeSchema.optional(),
  parsedOriginalFxRate: z.number().positive().optional(),
  parsedCounterAmountMinor: z.number().int().positive().optional(),
  parsedCounterCurrency: currencyCodeSchema.optional(),
  parsedCounterFxRate: z.number().positive().optional(),
  parsedMerchant: z.string().max(120).optional(),
  parsedLocationLabel: z.string().max(160).optional(),
  parsedOccurredAt: z.string().optional(),
  suggestedAccountId: z.string().uuid().optional(),
  suggestedCategoryId: z.string().uuid().optional(),
  suggestedType: transactionTypeSchema.optional(),
  suggestedRecurringTemplateId: z.string().uuid().optional(),
  confidence: z.number().min(0).max(100).optional(),
});

export type AccountCreateInput = z.infer<typeof accountCreateSchema>;
export type TransactionCreateInput = z.infer<typeof transactionCreateSchema>;
export type CaptureCandidateCreateInput = z.infer<typeof captureCandidateCreateSchema>;
