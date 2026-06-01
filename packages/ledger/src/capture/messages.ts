import { toMinor } from '@1wallet/domain/money';
import type {
    Account,
    AccountMatchIdentifier,
    AccountMatchIdentifierKind,
    AccountMessageHint,
    AccountMessageSourceHints,
    AccountType,
    CaptureCandidate,
    Category,
    CategoryKind,
    TransactionSource,
    TransactionType,
    UUID,
} from '@1wallet/domain/types';
import { nowIso, uid } from '../id';
import {
    approveCaptureCandidate,
    createCaptureCandidate,
    type CreateCaptureCandidateInput,
} from '../services/index';
import {
    DEFAULT_AUTO_CAPTURE_TRIGGER_KEYWORDS,
    type LedgerState,
    type MessageCategoryKeywordRule,
} from '../store/types';

export type TransactionMessageSource = Extract<TransactionSource, 'notification' | 'sms' | 'email'>;

export interface TransactionMessageInput {
  body: string;
  source?: TransactionMessageSource;
  sender?: string;
  subject?: string;
  receivedAt?: string;
  localeHint?: 'IN' | 'UK' | 'GB' | string;
}

export type TransactionMessageTriggerIgnoredReason =
  | 'security'
  | 'balance_only'
  | 'ignored_sender'
  | 'no_trigger_keyword';

export interface TransactionMessageTriggerOptions {
  triggerKeywords?: readonly string[];
  ignoredSenderIds?: readonly string[];
}

export interface TransactionMessageTriggerResult {
  matched: boolean;
  matchedKeywords: string[];
  ignoredReason?: TransactionMessageTriggerIgnoredReason;
}

export interface TransactionMessageCaptureOptions extends TransactionMessageTriggerOptions {
  autoPost?: boolean;
  autoPostConfidence?: number;
  smsInboxId?: string;
}

export type TransactionMessageCaptureOutcome =
  | 'ignored'
  | 'unrecognized'
  | 'duplicate'
  | 'queued'
  | 'posted';

export interface TransactionMessageCaptureResult {
  outcome: TransactionMessageCaptureOutcome;
  trigger: TransactionMessageTriggerResult;
  parseResult?: TransactionMessageParseResult;
  candidate?: CaptureCandidate;
  postedTransactionId?: UUID;
  error?: string;
}

export interface ExtractedAccountFragment {
  kind: AccountMatchIdentifierKind;
  value: string;
  label?: string;
}

export interface AccountMessageMatchCandidate {
  accountId: UUID;
  accountName: string;
  score: number;
  matchedBy: string[];
}

export interface AccountMessageMatch {
  accountId?: UUID;
  confidence: number;
  ambiguous: boolean;
  matchedBy: string[];
  candidates: AccountMessageMatchCandidate[];
}

export interface MessageCategoryMatchCandidate {
  categoryId: UUID;
  categoryName: string;
  score: number;
  matchedBy: string[];
  ruleId?: UUID;
}

export interface MessageCategoryMatch {
  categoryId?: UUID;
  categoryName?: string;
  confidence: number;
  ambiguous: boolean;
  matchedBy: string[];
  candidates: MessageCategoryMatchCandidate[];
}

export interface TransactionMessageParseResult {
  recognized: boolean;
  candidateInput?: CreateCaptureCandidateInput;
  amountMinor?: number;
  currency?: string;
  merchant?: string;
  occurredAt?: string;
  paymentMethod?: string;
  reference?: string;
  suggestedType?: TransactionType;
  categoryMatch: MessageCategoryMatch;
  fragments: ExtractedAccountFragment[];
  match: AccountMessageMatch;
  confidence: number;
  warnings: string[];
}

type RawMessagePayload = {
  kind?: unknown;
  source?: unknown;
  sender?: unknown;
  fragments?: unknown;
};

type AmountMatch = { amountMinor: number; currency: string; raw: string; index: number };
type MessageCategoryKind = Extract<CategoryKind, 'expense' | 'income'>;

type MessageCategoryLookup = {
  activeById: Map<UUID, Category>;
  activeByKind: Record<MessageCategoryKind, Category[]>;
  activeNamesByKind: Record<MessageCategoryKind, Map<string, Category>>;
  sortedRules: MessageCategoryKeywordRule[];
};

export interface CreateMessageCategoryRuleInput {
  name?: string;
  keywords: string[];
  categoryId: UUID;
  enabled?: boolean;
  priority?: number;
}

export interface UpdateMessageCategoryRuleInput {
  name?: string;
  keywords?: string[];
  categoryId?: UUID;
  enabled?: boolean;
  priority?: number;
}

const MESSAGE_PARSER_VERSION = '1wallet-message-v1';
const DEFAULT_AUTO_POST_CONFIDENCE = 82;
const TRANSFER_LIKE_MESSAGE_TYPES = new Set<TransactionType>([
  'transfer',
  'card_payment',
  'loan_repayment',
]);

const EXPENSE_TERMS = [
  'debited',
  'debit',
  'dr ',
  'dr.',
  'spent',
  'spend',
  'purchase',
  'purchased',
  'paid',
  'paid to',
  'sent',
  'transferred',
  'transfer to',
  'withdrawn',
  'withdrawal',
  'charged',
  'charge',
  'deducted',
  'deduction',
  'used',
  'payment made',
  'payment of',
  'pos txn',
  'pos transaction',
  'card transaction',
  'auto debit',
  'autopay',
  'upi payment',
  'upi txn',
];

const INCOME_TERMS = [
  'credited',
  'credit',
  'cr ',
  'cr.',
  'received',
  'received from',
  'deposited',
  'deposit',
  'refund',
  'refunded',
  'reversed',
  'reversal',
  'cashback',
  'salary',
  'payroll',
  'wages',
  'paid in',
  'payment received',
  'added to',
  'inward',
];

const SECURITY_TERMS = [
  'otp',
  'one time password',
  'one-time password',
  'verification code',
  'login code',
  'do not share',
  'never share',
];

const BALANCE_ONLY_TERMS = ['available balance', 'avl bal', 'statement balance', 'min due'];
const LOAN_REPAYMENT_TERMS = ['emi', 'loan repayment', 'loan emi', 'installment', 'instalment'];
const CARD_PAYMENT_TERMS = [
  'credit card payment',
  'card payment',
  'credit card bill',
  'card bill',
  'statement payment',
];

const INDIAN_RAIL_TERMS = ['upi', 'imps', 'neft', 'rtgs', 'pos', 'atm'];
const UK_RAIL_TERMS = ['faster payment', 'direct debit', 'standing order', 'contactless'];

const DEFAULT_MESSAGE_CATEGORY_RULES: Array<{
  categoryName: string;
  kind: Extract<CategoryKind, 'expense' | 'income'>;
  keywords: string[];
}> = [
  {
    categoryName: 'Food delivery',
    kind: 'expense',
    keywords: [
      'swiggy',
      'zomato',
      'ubereats',
      'uber eats',
      'deliveroo',
      'just eat',
      'takeaway',
      'food delivery',
      'fast food',
    ],
  },
  {
    categoryName: 'Groceries',
    kind: 'expense',
    keywords: [
      'bigbasket',
      'bbnow',
      'blinkit',
      'zepto',
      'dmart',
      'd mart',
      'tesco',
      'sainsbury',
      'asda',
      'aldi',
      'lidl',
      'morrisons',
      'waitrose',
      'supermarket',
      'grocery',
      'groceries',
      'grocer',
      'food market',
    ],
  },
  {
    categoryName: 'Dining out',
    kind: 'expense',
    keywords: [
      'restaurant',
      'cafe',
      'caffe',
      'mcdonald',
      'kfc',
      'dominos',
      'pizza',
      'burger',
      'barista',
      'starbucks',
      'dining',
      'dine',
      'lunch',
      'dinner',
      'meal',
    ],
  },
  {
    categoryName: 'Taxi & rides',
    kind: 'expense',
    keywords: ['uber', 'ola', 'rapido', 'cab', 'taxi', 'ride share', 'bolt'],
  },
  {
    categoryName: 'Public transport',
    kind: 'expense',
    keywords: ['metro', 'bus', 'train', 'tube', 'tfl', 'railway', 'irctc', 'oyster'],
  },
  {
    categoryName: 'Parking & tolls',
    kind: 'expense',
    keywords: ['parking', 'toll', 'fastag', 'dart charge'],
  },
  {
    categoryName: 'Fuel',
    kind: 'expense',
    keywords: [
      'fuel',
      'petrol',
      'diesel',
      'shell',
      'bpcl',
      'hpcl',
      'iocl',
      'indianoil',
      'bharat petroleum',
      'esso',
    ],
  },
  {
    categoryName: 'Online shopping',
    kind: 'expense',
    keywords: ['amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'ebay', 'etsy'],
  },
  {
    categoryName: 'Electricity',
    kind: 'expense',
    keywords: [
      'electricity',
      'power bill',
      'bescom',
      'tneb',
      'energy bill',
      'octopus energy',
      'bulb energy',
    ],
  },
  {
    categoryName: 'Internet & phone',
    kind: 'expense',
    keywords: [
      'broadband',
      'internet bill',
      'phone bill',
      'airtel',
      'jio',
      'vodafone',
      'vi bill',
      'ee mobile',
      'o2 mobile',
      'three mobile',
      'bt broadband',
    ],
  },
  {
    categoryName: 'Mobile recharge',
    kind: 'expense',
    keywords: ['recharge', 'top up', 'mobile topup', 'prepaid'],
  },
  {
    categoryName: 'Subscriptions',
    kind: 'expense',
    keywords: [
      'netflix',
      'spotify',
      'prime video',
      'amazon prime',
      'hotstar',
      'disney',
      'youtube premium',
      'subscription',
      'icloud',
      'google storage',
    ],
  },
  {
    categoryName: 'Rent',
    kind: 'expense',
    keywords: ['rent', 'landlord', 'letting'],
  },
  {
    categoryName: 'EMI',
    kind: 'expense',
    keywords: ['emi', 'loan emi', 'installment', 'instalment', 'loan repayment'],
  },
  {
    categoryName: 'Credit card bill',
    kind: 'expense',
    keywords: ['credit card payment', 'card bill', 'statement payment', 'minimum due'],
  },
  {
    categoryName: 'Charges & fees',
    kind: 'expense',
    keywords: ['fee', 'fees', 'charge', 'charges', 'annual fee', 'late fee', 'service charge'],
  },
  {
    categoryName: 'Tax',
    kind: 'expense',
    keywords: ['income tax', 'self assessment', 'hmrc', 'tds', 'tax payment'],
  },
  {
    categoryName: 'Salary',
    kind: 'income',
    keywords: ['salary', 'payroll', 'wages', 'pay credited'],
  },
  {
    categoryName: 'Refund',
    kind: 'income',
    keywords: ['refund', 'refunded', 'reversal', 'reversed'],
  },
  {
    categoryName: 'Cashback',
    kind: 'income',
    keywords: ['cashback', 'cash back', 'reward credited', 'rewards credited'],
  },
  {
    categoryName: 'Interest',
    kind: 'income',
    keywords: ['interest credited', 'savings interest', 'bank interest'],
  },
  {
    categoryName: 'Dividend',
    kind: 'income',
    keywords: ['dividend', 'dividend credited'],
  },
];

export function parseTransactionMessage(
  state: LedgerState,
  input: TransactionMessageInput,
): TransactionMessageParseResult {
  const source = input.source ?? inferSource(input);
  const body = normalizeWhitespace(input.body);
  const subject = normalizeWhitespace(input.subject ?? '');
  const fullText = normalizeWhitespace([subject, body].filter(Boolean).join(' '));
  const warnings: string[] = [];
  const amount = extractAmount(fullText, state.preferences.baseCurrency);
  const suggestedType = inferTransactionType(fullText);
  const fragments = extractAccountFragments(fullText);
  const merchant = extractMerchant(fullText, suggestedType);
  const categoryMatch = matchMessageCategory(state, { text: fullText, merchant, suggestedType });
  const occurredAt = extractOccurredAt(fullText, input.receivedAt);
  const paymentMethod = extractPaymentMethod(fullText);
  const reference = extractReference(fullText);
  const match = matchMessageAccount(state.accounts, {
    text: fullText,
    source,
    sender: input.sender,
    currency: amount?.currency,
    fragments,
  });

  if (containsAny(fullText, SECURITY_TERMS)) warnings.push('security message ignored');
  if (!amount) warnings.push('amount missing');
  if (!suggestedType) warnings.push('transaction direction needs review');
  if (!occurredAt) warnings.push('date needs review');
  if (!match.accountId) {
    warnings.push(match.ambiguous ? 'ambiguous account match' : 'account needs matching detail');
  }
  if (!merchant && suggestedType === 'expense') warnings.push('merchant needs review');
  if (messageTypeNeedsCategory(suggestedType) && !categoryMatch.categoryId) {
    warnings.push('category needs review');
  }
  if (isBalanceOnlyMessage(fullText) && !suggestedType) warnings.push('balance-only message');

  const recognized = Boolean(
    amount && suggestedType && !warnings.includes('security message ignored'),
  );
  const confidence = scoreMessage({
    amount,
    suggestedType,
    occurredAt,
    merchant,
    reference,
    categoryMatch,
    match,
  });
  const candidateInput =
    amount && suggestedType && recognized
      ? buildCandidateInput({
          source,
          input,
          body,
          subject,
          amount,
          suggestedType,
          merchant,
          occurredAt,
          paymentMethod,
          reference,
          categoryMatch,
          fragments,
          match,
          confidence,
          warnings,
        })
      : undefined;

  return {
    recognized,
    candidateInput,
    amountMinor: amount?.amountMinor,
    currency: amount?.currency,
    merchant,
    occurredAt,
    paymentMethod,
    reference,
    suggestedType,
    categoryMatch,
    fragments,
    match,
    confidence,
    warnings,
  };
}

export function shouldProcessTransactionMessage(
  input: TransactionMessageInput,
  options: TransactionMessageTriggerOptions = {},
): TransactionMessageTriggerResult {
  const source = input.source ?? inferSource(input);
  const body = normalizeWhitespace(input.body);
  const subject = normalizeWhitespace(input.subject ?? '');
  const fullText = normalizeWhitespace([subject, body].filter(Boolean).join(' '));

  if (source === 'sms' && input.sender) {
    const sender = normalizeSenderId(input.sender);
    const ignoredSenders = (options.ignoredSenderIds ?? [])
      .map(normalizeSenderId)
      .filter((value) => value.length > 0);
    if (sender && ignoredSenders.some((ignored) => sender.includes(ignored))) {
      return { matched: false, matchedKeywords: [], ignoredReason: 'ignored_sender' };
    }
  }

  if (containsAny(fullText, SECURITY_TERMS)) {
    return { matched: false, matchedKeywords: [], ignoredReason: 'security' };
  }
  if (isBalanceOnlyMessage(fullText)) {
    return { matched: false, matchedKeywords: [], ignoredReason: 'balance_only' };
  }

  const matchedKeywords = matchingTriggerKeywords(
    fullText,
    normalizeTransactionMessageTriggerKeywords(options.triggerKeywords),
  );
  if (matchedKeywords.length === 0) {
    return { matched: false, matchedKeywords: [], ignoredReason: 'no_trigger_keyword' };
  }
  return { matched: true, matchedKeywords };
}

export function processTransactionMessageCapture(
  state: LedgerState,
  input: TransactionMessageInput,
  options: TransactionMessageCaptureOptions = {},
): TransactionMessageCaptureResult {
  const trigger = shouldProcessTransactionMessage(input, options);
  if (!trigger.matched) return { outcome: 'ignored', trigger };

  const parseResult = parseTransactionMessage(state, input);
  if (!parseResult.candidateInput) return { outcome: 'unrecognized', trigger, parseResult };

  const candidateInput: CreateCaptureCandidateInput = {
    ...parseResult.candidateInput,
    rawPayload: {
      ...parseResult.candidateInput.rawPayload,
      triggerMatchedBy: trigger.matchedKeywords,
      ...(options.smsInboxId ? { smsInboxId: options.smsInboxId } : {}),
    },
  };
  const before = state.captureCandidates.length;
  const candidate = createCaptureCandidate(state, candidateInput);
  if (state.captureCandidates.length === before) {
    return { outcome: 'duplicate', trigger, parseResult, candidate };
  }

  if (options.autoPost && canAutoPostCaptureCandidate(state, candidate, options)) {
    try {
      const transaction = approveCaptureCandidate(state, candidate.id);
      return {
        outcome: 'posted',
        trigger,
        parseResult,
        candidate,
        postedTransactionId: transaction.id,
      };
    } catch (error) {
      return {
        outcome: 'queued',
        trigger,
        parseResult,
        candidate,
        error: error instanceof Error ? error.message : 'Auto-post failed',
      };
    }
  }

  return { outcome: 'queued', trigger, parseResult, candidate };
}

export function canAutoPostCaptureCandidate(
  state: LedgerState,
  candidate: CaptureCandidate,
  options: Pick<TransactionMessageCaptureOptions, 'autoPostConfidence'> = {},
): boolean {
  return autoPostCaptureCandidateBlockers(state, candidate, options).length === 0;
}

export function autoPostCaptureCandidateBlockers(
  state: LedgerState,
  candidate: CaptureCandidate,
  options: Pick<TransactionMessageCaptureOptions, 'autoPostConfidence'> = {},
): string[] {
  const blockers: string[] = [];
  const threshold = clampAutoPostConfidence(options.autoPostConfidence);
  if (candidate.confidence < threshold) blockers.push(`confidence below ${threshold}%`);
  if (!candidate.parsedAmount || candidate.parsedAmount.amountMinor <= 0) blockers.push('amount');
  if (!candidate.suggestedAccountId) blockers.push('account');
  if (!candidate.suggestedType) blockers.push('type');
  if (candidate.suggestedType && TRANSFER_LIKE_MESSAGE_TYPES.has(candidate.suggestedType)) {
    blockers.push('transfer-like type');
  }
  if (!candidate.suggestedCategoryId) blockers.push('category');
  if (!candidate.parsedOccurredAt || Number.isNaN(new Date(candidate.parsedOccurredAt).getTime())) {
    blockers.push('date');
  }
  if (
    candidate.externalRef &&
    state.transactions.some((transaction) => transaction.externalRef === candidate.externalRef)
  ) {
    blockers.push('duplicate transaction');
  }
  const blockingWarnings = new Set([
    'security message ignored',
    'amount missing',
    'transaction direction needs review',
    'date needs review',
    'ambiguous account match',
    'account needs matching detail',
    'merchant needs review',
    'category needs review',
    'balance-only message',
  ]);
  for (const warning of candidate.warnings ?? []) {
    if (blockingWarnings.has(warning)) blockers.push(warning);
  }
  return Array.from(new Set(blockers));
}

export function normalizeTransactionMessageTriggerKeywords(
  values: readonly string[] | undefined,
): string[] {
  const source = values && values.length > 0 ? values : DEFAULT_AUTO_CAPTURE_TRIGGER_KEYWORDS;
  const seen = new Set<string>();
  const keywords: string[] = [];
  for (const value of source) {
    const keyword = normalizeWhitespace(value).slice(0, 64);
    const key = normalizeSearchText(keyword) || keyword.toLowerCase();
    if (!keyword || seen.has(key)) continue;
    seen.add(key);
    keywords.push(keyword);
  }
  return keywords.length > 0 ? keywords : [...DEFAULT_AUTO_CAPTURE_TRIGGER_KEYWORDS];
}

export function createCaptureCandidateFromMessage(
  state: LedgerState,
  input: TransactionMessageInput,
): { result: TransactionMessageParseResult; candidate?: CaptureCandidate } {
  const result = parseTransactionMessage(state, input);
  if (!result.candidateInput) return { result };
  return { result, candidate: createCaptureCandidate(state, result.candidateInput) };
}

export function messageHintSuggestionsForAccount(
  account: Account | undefined,
  input: TransactionMessageInput,
  result: Pick<TransactionMessageParseResult, 'fragments'>,
): AccountMessageHint[] {
  const source = input.source ?? inferSource(input);
  const suggestions: AccountMessageHint[] = [];
  const add = (suggestion: AccountMessageHint) => {
    const id = messageHintId(suggestion);
    if (suggestions.some((item) => item.id === id)) return;
    suggestions.push({ ...suggestion, id });
  };

  const sender = input.sender?.trim();
  if (source === 'sms' && sender) {
    const value = normalizeSenderId(sender);
    if (value) {
      add({
        kind: 'sms_sender_id',
        target: 'source_hint',
        value,
        label: 'SMS sender',
        source: 'sender',
        existing: accountHasSourceHint(account, 'sms_sender_id', value),
      });
    }
  }

  if (source === 'email' && sender?.includes('@')) {
    const value = normalizeEmailDomain(sender);
    if (value) {
      add({
        kind: 'email_domain',
        target: 'source_hint',
        value,
        label: 'Email domain',
        source: 'email',
        existing: accountHasSourceHint(account, 'email_domain', value),
      });
    }
  }

  for (const fragment of result.fragments) {
    const kind = normalizedHintKindForAccount(account, fragment.kind);
    add({
      kind,
      target: 'match_identifier',
      value: normalizeIdentifierValue(kind, fragment.value),
      label: fragment.label ?? hintLabel(kind),
      source: 'message',
      verified: false,
      existing: accountHasIdentifier(account, kind, fragment.value),
    });
  }

  return suggestions.filter((suggestion) => suggestion.value.length > 0);
}

export function messageHintSuggestionsFromCapturePayload(
  account: Account | undefined,
  rawPayload: Record<string, unknown>,
): AccountMessageHint[] {
  const payload = rawPayload as RawMessagePayload;
  if (payload.kind !== 'transaction_message') return [];
  const source = transactionMessageSourceFromRaw(payload.source);
  const sender = typeof payload.sender === 'string' ? payload.sender : undefined;
  const fragments = Array.isArray(payload.fragments)
    ? payload.fragments.filter(isExtractedAccountFragment)
    : [];
  return messageHintSuggestionsForAccount(account, { source, sender, body: '' }, { fragments });
}

export function buildAccountMatchIdentifiers(input: {
  accountType: AccountType;
  lastFour?: string;
  upiVpas?: string[];
  sortCode?: string;
  existing?: AccountMatchIdentifier[];
}): AccountMatchIdentifier[] {
  const existing = (input.existing ?? []).filter(
    (identifier) =>
      identifier.kind !== 'account_last4' &&
      identifier.kind !== 'card_last4' &&
      identifier.kind !== 'upi_vpa' &&
      identifier.kind !== 'sort_code',
  );
  const identifiers: AccountMatchIdentifier[] = [...existing];
  const lastFour = lastFourDigits(input.lastFour);
  if (lastFour) {
    identifiers.push({
      kind: isCardAccount(input.accountType) ? 'card_last4' : 'account_last4',
      value: lastFour,
      label: 'Last 4 digits',
      verified: false,
    });
  }
  for (const vpa of uniqueStrings(input.upiVpas ?? []).map((value) => value.toLowerCase())) {
    identifiers.push({ kind: 'upi_vpa', value: vpa, label: 'UPI ID', verified: false });
  }
  const sortCode = normalizeSortCode(input.sortCode);
  if (sortCode) {
    identifiers.push({ kind: 'sort_code', value: sortCode, label: 'Sort code', verified: false });
  }
  return identifiers;
}

export function buildAccountMessageSourceHints(input: {
  smsSenderIds?: string[];
  emailDomains?: string[];
  keywords?: string[];
  existing?: AccountMessageSourceHints;
}): AccountMessageSourceHints | undefined {
  const smsSenderIds = uniqueStrings([
    ...(input.existing?.smsSenderIds ?? []),
    ...(input.smsSenderIds ?? []),
  ]).map(normalizeSenderId);
  const emailDomains = uniqueStrings([
    ...(input.existing?.emailDomains ?? []),
    ...(input.emailDomains ?? []),
  ]).map(normalizeEmailDomain);
  const keywords = uniqueStrings([
    ...(input.existing?.keywords ?? []),
    ...(input.keywords ?? []),
  ]).map((value) => value.trim());

  const hints: AccountMessageSourceHints = {};
  if (smsSenderIds.length > 0) hints.smsSenderIds = smsSenderIds;
  if (emailDomains.length > 0) hints.emailDomains = emailDomains;
  if (keywords.length > 0) hints.keywords = keywords;
  return Object.keys(hints).length > 0 ? hints : undefined;
}

export function createMessageCategoryRule(
  state: LedgerState,
  input: CreateMessageCategoryRuleInput,
): MessageCategoryKeywordRule {
  const category = findUsableRuleCategory(state, input.categoryId);
  const keywords = normalizeKeywordList(input.keywords);
  if (keywords.length === 0) throw new Error('createMessageCategoryRule: keywords are required');

  const rules = ensureMessageCategoryRules(state);
  const now = nowIso();
  const rule: MessageCategoryKeywordRule = {
    id: uid(),
    name: cleanRuleName(input.name) ?? `${category.name} messages`,
    enabled: input.enabled ?? true,
    keywords,
    categoryId: category.id,
    priority: input.priority ?? nextMessageRulePriority(rules),
    createdAt: now,
    updatedAt: now,
  };
  rules.push(rule);
  return rule;
}

export function updateMessageCategoryRule(
  state: LedgerState,
  id: UUID,
  patch: UpdateMessageCategoryRuleInput,
): MessageCategoryKeywordRule | undefined {
  const rules = ensureMessageCategoryRules(state);
  const rule = rules.find((item) => item.id === id);
  if (!rule) return undefined;

  if (patch.categoryId !== undefined) {
    rule.categoryId = findUsableRuleCategory(state, patch.categoryId).id;
  }
  if (patch.keywords !== undefined) {
    const keywords = normalizeKeywordList(patch.keywords);
    if (keywords.length === 0) throw new Error('updateMessageCategoryRule: keywords are required');
    rule.keywords = keywords;
  }
  if (patch.name !== undefined) {
    const category = state.categories.find((item) => item.id === rule.categoryId);
    rule.name = cleanRuleName(patch.name) ?? `${category?.name ?? 'Category'} messages`;
  }
  if (patch.enabled !== undefined) rule.enabled = patch.enabled;
  if (patch.priority !== undefined) rule.priority = Math.max(0, Math.round(patch.priority));
  rule.updatedAt = nowIso();
  return rule;
}

export function deleteMessageCategoryRule(state: LedgerState, id: UUID): boolean {
  const rules = ensureMessageCategoryRules(state);
  const before = rules.length;
  state.preferences.messageCategoryRules = rules.filter((rule) => rule.id !== id);
  return state.preferences.messageCategoryRules.length < before;
}

function buildCandidateInput(input: {
  source: TransactionMessageSource;
  input: TransactionMessageInput;
  body: string;
  subject: string;
  amount: AmountMatch;
  suggestedType: TransactionType;
  merchant: string | undefined;
  occurredAt: string | undefined;
  paymentMethod: string | undefined;
  reference: string | undefined;
  categoryMatch: MessageCategoryMatch;
  fragments: ExtractedAccountFragment[];
  match: AccountMessageMatch;
  confidence: number;
  warnings: string[];
}): CreateCaptureCandidateInput {
  return {
    source: input.source,
    rawPayload: {
      kind: 'transaction_message',
      parserVersion: MESSAGE_PARSER_VERSION,
      source: input.source,
      sender: input.input.sender,
      subject: input.subject || undefined,
      body: input.body,
      receivedAt: input.input.receivedAt,
      localeHint: input.input.localeHint,
      fragments: input.fragments,
      matchedBy: input.match.matchedBy,
      categoryMatchedBy: input.categoryMatch.matchedBy,
    },
    parsedAmountMinor: input.amount.amountMinor,
    parsedCurrency: input.amount.currency,
    parsedMerchant: input.merchant,
    parsedNotes: input.body,
    parsedPaymentMethod: input.paymentMethod,
    parsedTags: ['message-capture', input.source],
    parsedOccurredAt: input.occurredAt,
    suggestedAccountId: input.match.accountId,
    suggestedCategoryId: input.categoryMatch.categoryId,
    suggestedType: input.suggestedType,
    confidence: input.confidence,
    externalRef: input.reference,
    warnings: input.warnings.length > 0 ? input.warnings : undefined,
  };
}

function inferSource(input: TransactionMessageInput): TransactionMessageSource {
  if (input.subject || input.sender?.includes('@')) return 'email';
  return 'sms';
}

function extractAmount(text: string, fallbackCurrency: string): AmountMatch | undefined {
  const amountPatterns: Array<{ currency?: string; regex: RegExp }> = [
    {
      currency: 'INR',
      regex: /(?:\bINR\b|\bRs\.?|\brupees?\b)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i,
    },
    { currency: 'INR', regex: /\u20B9\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i },
    { currency: 'GBP', regex: /(?:\bGBP\b|\bpounds?\b)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i },
    { currency: 'GBP', regex: /\u00A3\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i },
    { currency: 'USD', regex: /(?:\bUSD\b|\bdollars?\b)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i },
    { currency: 'USD', regex: /\$\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i },
    { currency: 'INR', regex: /([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:\bINR\b|\brupees?\b)/i },
    { currency: 'GBP', regex: /([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:\bGBP\b|\bpounds?\b)/i },
    { currency: 'USD', regex: /([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:\bUSD\b|\bdollars?\b)/i },
  ];

  const matches = amountPatterns
    .map((pattern) => {
      const match = pattern.regex.exec(text);
      const rawAmount = match?.[1];
      if (!match || !rawAmount) return undefined;
      const amount = Number(rawAmount.replace(/,/g, ''));
      if (!Number.isFinite(amount) || amount <= 0) return undefined;
      const currency = pattern.currency ?? fallbackCurrency;
      return {
        amountMinor: toMinor(amount, currency),
        currency,
        raw: match[0],
        index: match.index,
      } satisfies AmountMatch;
    })
    .filter((match): match is AmountMatch => Boolean(match))
    .sort((left, right) => left.index - right.index);

  return matches[0];
}

function inferTransactionType(text: string): TransactionType | undefined {
  const lower = text.toLowerCase();
  const hasIncome = containsAny(lower, INCOME_TERMS);
  const hasExpense = containsAny(lower, EXPENSE_TERMS);
  if (hasExpense && containsAny(lower, LOAN_REPAYMENT_TERMS)) return 'loan_repayment';
  if (hasExpense && containsAny(lower, CARD_PAYMENT_TERMS)) return 'card_payment';
  if (hasIncome && !hasExpense) return 'income';
  if (hasExpense && !hasIncome) return 'expense';
  if (hasIncome && hasExpense) {
    const incomeIndex = firstTermIndex(lower, INCOME_TERMS);
    const expenseIndex = firstTermIndex(lower, EXPENSE_TERMS);
    return incomeIndex < expenseIndex ? 'income' : 'expense';
  }
  return undefined;
}

function extractAccountFragments(text: string): ExtractedAccountFragment[] {
  const fragments: ExtractedAccountFragment[] = [];
  const add = (kind: AccountMatchIdentifierKind, value: string, label?: string) => {
    const normalized = normalizeIdentifierValue(kind, value);
    if (!normalized) return;
    if (fragments.some((fragment) => fragment.kind === kind && fragment.value === normalized)) {
      return;
    }
    fragments.push({ kind, value: normalized, label });
  };

  collectRegex(
    text,
    /\b(?:card|cc|credit card|debit card|visa|mastercard|amex|rupay)[^0-9]{0,28}(?:ending(?: in)?|ends? in|last\s*4|no\.?|number|x{2,4}|\*{2,4})?[^0-9]{0,10}(\d{4})\b/gi,
    (value) => add('card_last4', value, 'Card last 4'),
  );
  collectRegex(
    text,
    /\b(?:a\/c|acct|account|acc(?:ount)?(?: no\.?)?)[^0-9]{0,28}(?:ending(?: in)?|ends? in|last\s*4|no\.?|number|x{2,4}|\*{2,4})?[^0-9]{0,10}(\d{4})\b/gi,
    (value) => add('account_last4', value, 'Account last 4'),
  );
  collectRegex(text, /\b(?:iban)[^A-Z0-9]{0,16}[A-Z0-9*X]{4,}\s?(\d{4})\b/gi, (value) =>
    add('iban_last4', value, 'IBAN last 4'),
  );
  collectRegex(text, /\b(?:ending(?: in)?|ends? in)\s+(\d{4})\b/gi, (value) =>
    add('masked_number', value, 'Masked number'),
  );
  collectRegex(text, /\b([a-z0-9._-]{2,}@[a-z][a-z0-9._-]{1,})\b/gi, (value) =>
    add('upi_vpa', value.toLowerCase(), 'UPI ID'),
  );
  collectRegex(text, /\bsort\s*code\s*[:\-]?\s*(\d{2}[- ]?\d{2}[- ]?\d{2})\b/gi, (value) =>
    add('sort_code', value, 'Sort code'),
  );

  return fragments;
}

function matchMessageAccount(
  accounts: Account[],
  input: {
    text: string;
    source: TransactionMessageSource;
    sender?: string;
    currency?: string;
    fragments: ExtractedAccountFragment[];
  },
): AccountMessageMatch {
  const normalizedText = normalizeSearchText(input.text);
  const normalizedSender = input.sender ? normalizeSenderId(input.sender) : undefined;
  const emailDomain = input.sender?.includes('@') ? normalizeEmailDomain(input.sender) : undefined;
  const candidates: AccountMessageMatchCandidate[] = [];

  for (const account of accounts) {
    if (account.isArchived) continue;
    let score = 0;
    const matchedBy: string[] = [];

    if (input.currency && account.currency === input.currency) {
      score += 4;
      matchedBy.push('currency');
    }

    for (const fragment of input.fragments) {
      const fragmentScore = scoreIdentifierMatch(account, fragment);
      if (fragmentScore > 0) {
        score += fragmentScore;
        matchedBy.push(`${fragment.kind}:${fragment.value}`);
      }
    }

    const hintScore = scoreSourceHints(account, {
      source: input.source,
      normalizedSender,
      emailDomain,
      normalizedText,
    });
    if (hintScore > 0) {
      score += hintScore;
      matchedBy.push('source hint');
    }

    const institutionScore = scoreInstitutionMatch(account, normalizedSender, normalizedText);
    if (institutionScore > 0) {
      score += institutionScore;
      matchedBy.push('institution');
    }

    if (score > 0) {
      candidates.push({ accountId: account.id, accountName: account.name, score, matchedBy });
    }
  }

  candidates.sort((left, right) => right.score - left.score);

  const [best, second] = candidates;
  const ambiguous = Boolean(best && second && best.score - second.score < 12);
  const accountId = best && best.score >= 36 && !ambiguous ? best.accountId : undefined;
  return {
    accountId,
    confidence: best ? Math.min(100, best.score) : 0,
    ambiguous,
    matchedBy: accountId && best ? best.matchedBy : [],
    candidates: candidates.slice(0, 5),
  };
}

function matchMessageCategory(
  state: LedgerState,
  input: { text: string; merchant?: string; suggestedType?: TransactionType },
): MessageCategoryMatch {
  const kind = categoryKindForMessageType(input.suggestedType);
  if (!kind) return emptyCategoryMatch();

  const lookup = buildMessageCategoryLookup(state);
  const normalizedText = normalizeSearchText([input.text, input.merchant ?? ''].join(' '));
  const candidatesById = new Map<UUID, MessageCategoryMatchCandidate>();
  const pushCandidate = (candidate: MessageCategoryMatchCandidate) => {
    const existing = candidatesById.get(candidate.categoryId);
    if (!existing || candidate.score > existing.score) {
      candidatesById.set(candidate.categoryId, candidate);
      return;
    }
    if (candidate.score === existing.score) {
      existing.matchedBy = uniqueStrings([...existing.matchedBy, ...candidate.matchedBy]);
    }
  };

  for (const rule of lookup.sortedRules) {
    if (!rule.enabled) continue;
    const category = lookup.activeById.get(rule.categoryId);
    if (category?.kind !== kind) continue;
    if (!category) continue;
    const matches = matchingKeywords(normalizedText, rule.keywords);
    if (matches.length === 0) continue;
    pushCandidate({
      categoryId: category.id,
      categoryName: category.name,
      score: Math.min(99, 88 + matches.length * 3),
      matchedBy: matches.map((keyword) => `custom:${keyword}`),
      ruleId: rule.id,
    });
  }

  const merchantMatch = merchantDefaultCategoryMatch(state, lookup, kind, input.merchant);
  if (merchantMatch) pushCandidate(merchantMatch);

  for (const rule of DEFAULT_MESSAGE_CATEGORY_RULES) {
    if (rule.kind !== kind) continue;
    const category = findCategoryByName(lookup, rule.categoryName, kind);
    if (!category) continue;
    const matches = matchingKeywords(normalizedText, rule.keywords);
    if (matches.length === 0) continue;
    pushCandidate({
      categoryId: category.id,
      categoryName: category.name,
      score: Math.min(86, 66 + matches.length * 4),
      matchedBy: matches.map((keyword) => `default:${keyword}`),
    });
  }

  if (candidatesById.size === 0) {
    const foodFallback = genericFoodCategoryMatch(lookup, kind, normalizedText);
    if (foodFallback) pushCandidate(foodFallback);
  }

  for (const category of lookup.activeByKind[kind]) {
    const categoryName = normalizeSearchText(category.name);
    if (categoryName.length < 4 || !keywordMatches(normalizedText, categoryName)) continue;
    pushCandidate({
      categoryId: category.id,
      categoryName: category.name,
      score: 52,
      matchedBy: [`category:${category.name}`],
    });
  }

  const candidates = Array.from(candidatesById.values()).sort(
    (left, right) =>
      right.score - left.score || left.categoryName.localeCompare(right.categoryName),
  );
  const [best, second] = candidates;
  const ambiguous = Boolean(best && second && best.score - second.score < 8);
  const categoryId = best && best.score >= 50 && !ambiguous ? best.categoryId : undefined;
  return {
    categoryId,
    categoryName: categoryId ? best?.categoryName : undefined,
    confidence: best ? Math.min(100, best.score) : 0,
    ambiguous,
    matchedBy: categoryId && best ? best.matchedBy : [],
    candidates: candidates.slice(0, 5),
  };
}

function genericFoodCategoryMatch(
  lookup: MessageCategoryLookup,
  kind: MessageCategoryKind,
  normalizedText: string,
): MessageCategoryMatchCandidate | undefined {
  if (kind !== 'expense') return undefined;
  const matches = matchingKeywords(normalizedText, ['food', 'foods']);
  if (matches.length === 0) return undefined;
  const category = findCategoryByName(lookup, 'Food & dining', 'expense');
  if (!category) return undefined;
  return {
    categoryId: category.id,
    categoryName: category.name,
    score: 58,
    matchedBy: matches.map((keyword) => `fallback:${keyword}`),
  };
}

function merchantDefaultCategoryMatch(
  state: LedgerState,
  lookup: MessageCategoryLookup,
  kind: MessageCategoryKind,
  merchant?: string,
): MessageCategoryMatchCandidate | undefined {
  const normalizedMerchant = normalizeSearchText(merchant ?? '');
  if (normalizedMerchant.length < 3) return undefined;

  for (const knownMerchant of state.merchants) {
    if (!knownMerchant.defaultCategoryId) continue;
    const normalizedKnown = normalizeSearchText(knownMerchant.normalizedName || knownMerchant.name);
    if (!normalizedKnown) continue;
    const matches =
      keywordMatches(normalizedMerchant, normalizedKnown) ||
      keywordMatches(normalizedKnown, normalizedMerchant);
    if (!matches) continue;
    const category = lookup.activeById.get(knownMerchant.defaultCategoryId);
    if (category?.kind !== kind) continue;
    if (!category) continue;
    return {
      categoryId: category.id,
      categoryName: category.name,
      score: 92,
      matchedBy: [`merchant:${knownMerchant.name}`],
    };
  }
  return undefined;
}

function emptyCategoryMatch(): MessageCategoryMatch {
  return { confidence: 0, ambiguous: false, matchedBy: [], candidates: [] };
}

function scoreIdentifierMatch(account: Account, fragment: ExtractedAccountFragment): number {
  const identifiers = account.matchIdentifiers ?? [];
  let score = 0;
  for (const identifier of identifiers) {
    if (!identifierKindsCompatible(identifier.kind, fragment.kind)) continue;
    if (
      normalizeIdentifierValue(identifier.kind, identifier.value) ===
      normalizeIdentifierValue(fragment.kind, fragment.value)
    ) {
      score = Math.max(score, identifier.verified ? 62 : 54);
    }
  }

  if (score === 0) {
    const looseHaystack = normalizeDigits(
      [account.name, account.accountNickname, account.notes].filter(Boolean).join(' '),
    );
    if (fragment.value.length >= 4 && looseHaystack.includes(fragment.value)) score = 22;
  }

  if (score > 0 && fragment.kind === 'card_last4' && isCardAccount(account.type)) score += 6;
  if (score > 0 && fragment.kind === 'account_last4' && !isCardAccount(account.type)) score += 6;
  return score;
}

function scoreSourceHints(
  account: Account,
  input: {
    source: TransactionMessageSource;
    normalizedSender?: string;
    emailDomain?: string;
    normalizedText: string;
  },
): number {
  const hints = account.messageSourceHints;
  if (!hints) return 0;
  let score = 0;
  if (input.source === 'sms' && input.normalizedSender) {
    for (const sender of hints.smsSenderIds ?? []) {
      const normalized = normalizeSenderId(sender);
      if (normalized && input.normalizedSender.includes(normalized)) score = Math.max(score, 24);
    }
  }
  if (input.source === 'email' && input.emailDomain) {
    for (const domain of hints.emailDomains ?? []) {
      const normalized = normalizeEmailDomain(domain);
      if (normalized && input.emailDomain.endsWith(normalized)) score = Math.max(score, 24);
    }
  }
  for (const keyword of hints.keywords ?? []) {
    const normalized = normalizeSearchText(keyword);
    if (normalized.length >= 3 && input.normalizedText.includes(normalized)) {
      score = Math.max(score, 16);
    }
  }
  return score;
}

function scoreInstitutionMatch(
  account: Account,
  normalizedSender: string | undefined,
  normalizedText: string,
): number {
  const aliases = [account.institution, account.accountNickname, account.name]
    .filter((value): value is string => Boolean(value))
    .flatMap(significantTokens);
  let score = 0;
  for (const alias of aliases) {
    if (normalizedSender?.includes(alias)) score = Math.max(score, 12);
    if (normalizedText.includes(alias)) score = Math.max(score, 8);
  }
  return score;
}

function scoreMessage(input: {
  amount?: AmountMatch;
  suggestedType?: TransactionType;
  occurredAt?: string;
  merchant?: string;
  reference?: string;
  categoryMatch: MessageCategoryMatch;
  match: AccountMessageMatch;
}): number {
  let score = 0;
  if (input.amount) score += 28;
  if (input.suggestedType) score += 22;
  if (input.occurredAt) score += 10;
  if (input.merchant) score += 10;
  if (input.categoryMatch.categoryId)
    score += Math.min(12, Math.round(input.categoryMatch.confidence / 7));
  if (input.reference) score += 5;
  if (input.match.accountId) score += Math.min(25, Math.round(input.match.confidence / 3));
  else if (input.match.ambiguous) score += 8;
  return Math.min(95, score);
}

function extractMerchant(
  text: string,
  suggestedType: TransactionType | undefined,
): string | undefined {
  const patterns =
    suggestedType === 'income'
      ? [/\bfrom\s+([^.,;]+?)(?:\s+(?:into|to|on|via|ref|txn|transaction|a\/c|account)\b|[.,;]|$)/i]
      : [
          /\b(?:at|to|towards|for)\s+([^.,;]+?)(?:\s+(?:on|via|ref|txn|transaction|using|card|a\/c|account|from)\b|[.,;]|$)/i,
          /\b(?:spent|paid|purchase(?:d)?|used)\b[^.,;]*?\b(?:at|to)\s+([^.,;]+?)(?:\s+(?:on|via|ref|txn|transaction|using|card|a\/c|account|from)\b|[.,;]|$)/i,
        ];

  for (const pattern of patterns) {
    const match = pattern.exec(text);
    const merchant = cleanMerchant(match?.[1]);
    if (merchant) return merchant;
  }
  return undefined;
}

function extractPaymentMethod(text: string): string | undefined {
  const lower = text.toLowerCase();
  if (lower.includes('auto debit') || lower.includes('autopay')) return 'Auto debit';
  if (lower.includes('upi')) return 'UPI';
  if (lower.includes('imps')) return 'IMPS';
  if (lower.includes('neft')) return 'NEFT';
  if (lower.includes('rtgs')) return 'RTGS';
  if (lower.includes('atm')) return 'ATM';
  if (lower.includes('credit card')) return 'Credit card';
  if (lower.includes('debit card')) return 'Debit card';
  if (lower.includes('card') || lower.includes('contactless')) return 'Card';
  if (lower.includes('direct debit')) return 'Direct debit';
  if (lower.includes('standing order')) return 'Standing order';
  if (lower.includes('faster payment')) return 'Faster Payments';
  if (containsAny(lower, INDIAN_RAIL_TERMS) || containsAny(lower, UK_RAIL_TERMS))
    return 'Bank transfer';
  return undefined;
}

function extractReference(text: string): string | undefined {
  const patterns = [
    /\b(?:upi\s*ref(?:erence)?|utr|rrn|imps\s*ref|neft\s*ref|faster\s*payment\s*ref)\s*[:#-]?\s*([A-Z0-9-]{6,36})\b/i,
    /\b(?:txn|transaction|payment|ref(?:erence)?)(?:\s*(?:id|no|number))?\s*[:#-]?\s*([A-Z0-9-]{6,36})\b/i,
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match?.[1]) return match[1].toUpperCase();
  }
  return undefined;
}

function extractOccurredAt(text: string, receivedAt?: string): string | undefined {
  const fallback = validDate(receivedAt) ?? new Date();
  const patterns = [
    /\bon\s+(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\b/i,
    /\bon\s+(\d{1,2})[- ]([A-Za-z]{3,9})[- ](\d{2,4})\b/i,
    /\b(\d{1,2})[- ]([A-Za-z]{3,9})[- ](\d{2,4})\b/i,
  ];

  for (const pattern of patterns) {
    const match = pattern.exec(text);
    const parsed = match ? dateFromMatch(match, fallback) : undefined;
    if (parsed) return parsed.toISOString();
  }
  return fallback.toISOString();
}

function dateFromMatch(match: RegExpExecArray, fallback: Date): Date | undefined {
  const day = Number(match[1]);
  const monthValue = match[2];
  const yearValue = match[3];
  if (!day || !monthValue || !yearValue) return undefined;
  const month = /^\d+$/.test(monthValue) ? Number(monthValue) - 1 : monthIndex(monthValue);
  const yearNumber = Number(yearValue);
  const year = yearNumber < 100 ? 2000 + yearNumber : yearNumber;
  if (month < 0 || day < 1 || day > 31) return undefined;
  const date = new Date(fallback);
  date.setFullYear(year, month, day);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function monthIndex(value: string): number {
  const normalized = value.slice(0, 3).toLowerCase();
  return [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ].indexOf(normalized);
}

function validDate(value?: string): Date | undefined {
  if (!value) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function isBalanceOnlyMessage(text: string): boolean {
  const lower = text.toLowerCase();
  return (
    containsAny(lower, BALANCE_ONLY_TERMS) &&
    !containsAny(lower, EXPENSE_TERMS) &&
    !containsAny(lower, INCOME_TERMS)
  );
}

function identifierKindsCompatible(
  accountKind: AccountMatchIdentifierKind,
  fragmentKind: AccountMatchIdentifierKind,
): boolean {
  if (accountKind === fragmentKind) return true;
  const lastFourKinds: AccountMatchIdentifierKind[] = [
    'account_last4',
    'card_last4',
    'iban_last4',
    'masked_number',
  ];
  return lastFourKinds.includes(accountKind) && lastFourKinds.includes(fragmentKind);
}

function normalizedHintKindForAccount(
  account: Account | undefined,
  kind: AccountMatchIdentifierKind,
): AccountMatchIdentifierKind {
  if (kind === 'masked_number')
    return account && isCardAccount(account.type) ? 'card_last4' : 'account_last4';
  return kind;
}

function accountHasIdentifier(
  account: Account | undefined,
  kind: AccountMatchIdentifierKind,
  value: string,
): boolean {
  if (!account) return false;
  const normalizedValue = normalizeIdentifierValue(kind, value);
  return (account.matchIdentifiers ?? []).some(
    (identifier) =>
      identifierKindsCompatible(identifier.kind, kind) &&
      normalizeIdentifierValue(identifier.kind, identifier.value) === normalizedValue,
  );
}

function accountHasSourceHint(
  account: Account | undefined,
  kind: 'sms_sender_id' | 'email_domain' | 'keyword',
  value: string,
): boolean {
  if (!account?.messageSourceHints) return false;
  if (kind === 'sms_sender_id') {
    const normalized = normalizeSenderId(value);
    return (account.messageSourceHints.smsSenderIds ?? []).some(
      (sender) => normalizeSenderId(sender) === normalized,
    );
  }
  if (kind === 'email_domain') {
    const normalized = normalizeEmailDomain(value);
    return (account.messageSourceHints.emailDomains ?? []).some(
      (domain) => normalizeEmailDomain(domain) === normalized,
    );
  }
  const normalized = normalizeSearchText(value);
  return (account.messageSourceHints.keywords ?? []).some(
    (keyword) => normalizeSearchText(keyword) === normalized,
  );
}

function messageHintId(hint: AccountMessageHint): string {
  return `${hint.target}:${hint.kind}:${hint.value}`;
}

function hintLabel(kind: AccountMessageHint['kind']): string {
  switch (kind) {
    case 'account_last4':
      return 'Account last 4';
    case 'card_last4':
      return 'Card last 4';
    case 'iban_last4':
      return 'IBAN last 4';
    case 'sort_code':
      return 'Sort code';
    case 'upi_vpa':
      return 'UPI ID';
    case 'sms_sender_id':
      return 'SMS sender';
    case 'email_domain':
      return 'Email domain';
    case 'keyword':
      return 'Keyword';
    case 'phone_last4':
      return 'Phone last 4';
    case 'masked_number':
      return 'Masked number';
    case 'customer_ref':
      return 'Customer ref';
  }
}

function transactionMessageSourceFromRaw(value: unknown): TransactionMessageSource {
  if (value === 'sms' || value === 'email' || value === 'notification') return value;
  return 'sms';
}

function isExtractedAccountFragment(value: unknown): value is ExtractedAccountFragment {
  if (!value || typeof value !== 'object') return false;
  const item = value as Partial<ExtractedAccountFragment>;
  return typeof item.kind === 'string' && typeof item.value === 'string';
}

function ensureMessageCategoryRules(state: LedgerState): MessageCategoryKeywordRule[] {
  if (!state.preferences.messageCategoryRules) state.preferences.messageCategoryRules = [];
  return state.preferences.messageCategoryRules;
}

function findUsableRuleCategory(state: LedgerState, categoryId: UUID): Category {
  const category = state.categories.find((item) => item.id === categoryId && !item.isArchived);
  if (!category) throw new Error('message category rule category not found');
  if (category.kind !== 'expense' && category.kind !== 'income') {
    throw new Error('message category rule needs an expense or income category');
  }
  return category;
}

function cleanRuleName(value?: string): string | undefined {
  const name = normalizeWhitespace(value ?? '');
  return name ? name.slice(0, 80) : undefined;
}

function normalizeKeywordList(values: string[]): string[] {
  const seen = new Set<string>();
  const keywords: string[] = [];
  for (const value of values) {
    const keyword = normalizeWhitespace(value).slice(0, 64);
    const normalized = normalizeSearchText(keyword);
    if (normalized.length < 2 || seen.has(normalized)) continue;
    seen.add(normalized);
    keywords.push(keyword);
  }
  return keywords;
}

function nextMessageRulePriority(rules: MessageCategoryKeywordRule[]): number {
  return rules.reduce((max, rule) => Math.max(max, rule.priority), 0) + 10;
}

function messageTypeNeedsCategory(type: TransactionType | undefined): boolean {
  return Boolean(categoryKindForMessageType(type));
}

function categoryKindForMessageType(
  type: TransactionType | undefined,
): MessageCategoryKind | undefined {
  if (type === 'expense' || type === 'fee' || type === 'interest_out') return 'expense';
  if (type === 'income' || type === 'refund' || type === 'cashback' || type === 'interest_in') {
    return 'income';
  }
  return undefined;
}

function buildMessageCategoryLookup(state: LedgerState): MessageCategoryLookup {
  const activeById = new Map<UUID, Category>();
  const activeByKind: Record<MessageCategoryKind, Category[]> = { expense: [], income: [] };
  const activeNamesByKind: Record<MessageCategoryKind, Map<string, Category>> = {
    expense: new Map(),
    income: new Map(),
  };

  for (const category of state.categories) {
    if (category.isArchived || (category.kind !== 'expense' && category.kind !== 'income')) {
      continue;
    }

    activeById.set(category.id, category);
    activeByKind[category.kind].push(category);

    const normalizedName = normalizeSearchText(category.name);
    if (normalizedName && !activeNamesByKind[category.kind].has(normalizedName)) {
      activeNamesByKind[category.kind].set(normalizedName, category);
    }
  }

  return {
    activeById,
    activeByKind,
    activeNamesByKind,
    sortedRules: [...(state.preferences.messageCategoryRules ?? [])].sort(
      (left, right) => left.priority - right.priority,
    ),
  };
}

function findCategoryByName(
  lookup: MessageCategoryLookup,
  name: string,
  kind: MessageCategoryKind,
): Category | undefined {
  return lookup.activeNamesByKind[kind].get(normalizeSearchText(name));
}

function matchingKeywords(text: string, keywords: string[]): string[] {
  return keywords.filter((keyword) => {
    const normalized = normalizeSearchText(keyword);
    return normalized.length >= 2 && keywordMatches(text, normalized);
  });
}

function matchingTriggerKeywords(rawText: string, keywords: string[]): string[] {
  const normalizedText = normalizeSearchText(rawText);
  const rawLower = rawText.toLowerCase();
  return keywords.filter((keyword) => {
    const normalized = normalizeSearchText(keyword);
    if (normalized.length >= 2 && keywordMatches(normalizedText, normalized)) return true;
    return rawLower.includes(keyword.toLowerCase());
  });
}

function clampAutoPostConfidence(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_AUTO_POST_CONFIDENCE;
  return Math.max(0, Math.min(100, Math.round(value)));
}

function keywordMatches(text: string, keyword: string): boolean {
  const normalizedText = ` ${text} `;
  const normalizedKeyword = ` ${keyword} `;
  if (keyword.includes(' ')) return normalizedText.includes(normalizedKeyword);
  return normalizedText.includes(normalizedKeyword);
}

function normalizeIdentifierValue(kind: AccountMatchIdentifierKind, value: string): string {
  if (kind === 'upi_vpa') return value.trim().toLowerCase();
  if (kind === 'sort_code') return normalizeSortCode(value) ?? '';
  return normalizeDigits(value).slice(-4);
}

function normalizeDigits(value: string): string {
  return value.replace(/\D/g, '');
}

function lastFourDigits(value?: string): string | undefined {
  const digits = normalizeDigits(value ?? '');
  return digits.length >= 4 ? digits.slice(-4) : undefined;
}

function normalizeSortCode(value?: string): string | undefined {
  const digits = normalizeDigits(value ?? '');
  if (digits.length !== 6) return undefined;
  return `${digits.slice(0, 2)}-${digits.slice(2, 4)}-${digits.slice(4, 6)}`;
}

function normalizeSenderId(value: string): string {
  return value
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

function normalizeEmailDomain(value: string): string {
  const normalized = value.trim().toLowerCase();
  const [, domain = normalized] = normalized.split('@');
  return domain.replace(/^www\./, '');
}

function normalizeSearchText(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9@]+/g, ' ')
    .trim();
}

function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function cleanMerchant(value?: string): string | undefined {
  if (!value) return undefined;
  const merchant = normalizeWhitespace(value)
    .replace(/\b(?:rs\.?|inr|gbp|pounds?)\b.*$/i, '')
    .replace(/\b(?:ending|a\/c|account|card)\b.*$/i, '')
    .replace(/[.:,-]+$/g, '')
    .trim();
  if (merchant.length < 2) return undefined;
  if (/^(your|a\/c|account|card|upi|ref|txn)$/i.test(merchant)) return undefined;
  return merchant.slice(0, 120);
}

function containsAny(text: string, terms: readonly string[]): boolean {
  return terms.some((term) => text.toLowerCase().includes(term));
}

function firstTermIndex(text: string, terms: readonly string[]): number {
  return terms.reduce((best, term) => {
    const index = text.indexOf(term);
    return index >= 0 && index < best ? index : best;
  }, Number.MAX_SAFE_INTEGER);
}

function collectRegex(text: string, regex: RegExp, onMatch: (value: string) => void) {
  for (const match of text.matchAll(regex)) {
    const value = match[1];
    if (value) onMatch(value);
  }
}

function significantTokens(value: string): string[] {
  return normalizeSearchText(value)
    .split(' ')
    .filter(
      (token) =>
        token.length >= 3 && !['bank', 'card', 'account', 'credit', 'debit'].includes(token),
    );
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(
    new Set(values.map((value) => value.trim()).filter((value) => value.length > 0)),
  );
}

function isCardAccount(type: AccountType): boolean {
  return type === 'credit_card' || type === 'debit_card' || type === 'prepaid';
}
