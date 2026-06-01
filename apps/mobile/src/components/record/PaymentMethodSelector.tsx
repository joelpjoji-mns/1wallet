import type { Account, TransactionType } from '@1wallet/domain/types';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { AppIconName } from '../AppKit';
import { OptionListOverlay, type OptionListItem } from '../OptionListOverlay';
import { RecordSelectorRow } from './RecordSelectorRow';

type PaymentMethodAutoFill = 'empty' | 'suggested' | 'off';
type PaymentMethodDefinition = {
  value: string;
  description: string;
  icon: AppIconName;
};

const PAYMENT_METHODS: PaymentMethodDefinition[] = [
  {
    value: 'Bank transfer',
    description: 'Bank account, transfer, IMPS or NEFT',
    icon: 'bank-transfer',
  },
  { value: 'UPI', description: 'UPI app, QR or VPA payment', icon: 'qrcode-scan' },
  {
    value: 'Debit card',
    description: 'Debit card swipe, tap or online',
    icon: 'credit-card-outline',
  },
  {
    value: 'Credit card',
    description: 'Credit card swipe, tap or online',
    icon: 'credit-card-outline',
  },
  {
    value: 'Card payment',
    description: 'Credit card bill or card-to-card payment',
    icon: 'card-bulleted-outline',
  },
  { value: 'Cash', description: 'Physical cash', icon: 'cash-multiple' },
  { value: 'Wallet', description: 'Mobile wallet or stored balance', icon: 'wallet-outline' },
  {
    value: 'Prepaid card',
    description: 'Forex, gift or prepaid card',
    icon: 'card-account-details-outline',
  },
  { value: 'Net banking', description: 'Online banking payment', icon: 'web' },
  {
    value: 'Auto debit',
    description: 'Standing instruction or automatic debit',
    icon: 'calendar-sync-outline',
  },
  { value: 'Cheque', description: 'Cheque payment or deposit', icon: 'script-text-outline' },
  { value: 'Loan payment', description: 'EMI or loan repayment', icon: 'hand-coin-outline' },
  {
    value: 'Investment transfer',
    description: 'Broker, investment or crypto transfer',
    icon: 'chart-line',
  },
  { value: 'Other', description: 'Another payment method', icon: 'dots-horizontal' },
];

const BASE_METHOD_ORDER = [
  'Bank transfer',
  'UPI',
  'Debit card',
  'Credit card',
  'Cash',
  'Wallet',
  'Net banking',
  'Auto debit',
  'Other',
];

const ACCOUNT_METHOD_ORDER: Record<Account['type'], string[]> = {
  cash: ['Cash', 'UPI', 'Other'],
  bank: ['Bank transfer', 'UPI', 'Debit card', 'Net banking', 'Cheque', 'Auto debit'],
  debit_card: ['Debit card', 'UPI', 'Bank transfer', 'Net banking'],
  credit_card: ['Credit card', 'Card payment', 'Auto debit', 'Bank transfer'],
  wallet: ['Wallet', 'UPI', 'Bank transfer'],
  prepaid: ['Prepaid card', 'Wallet', 'Bank transfer'],
  loan: ['Loan payment', 'Bank transfer', 'Auto debit'],
  lent: ['Bank transfer', 'Cash', 'UPI'],
  investment: ['Investment transfer', 'Bank transfer'],
  savings_goal: ['Bank transfer', 'Auto debit'],
  overdraft: ['Bank transfer', 'Auto debit', 'Loan payment'],
  crypto: ['Investment transfer', 'Bank transfer'],
  other: ['Other', 'Bank transfer', 'UPI'],
};

export function PaymentMethodSelector({
  account,
  transactionType,
  value,
  onChange,
  autoFill = 'empty',
}: {
  account?: Pick<Account, 'type'>;
  transactionType: TransactionType;
  value: string;
  onChange: (value: string) => void;
  autoFill?: PaymentMethodAutoFill;
}) {
  const [visible, setVisible] = useState(false);
  const lastSuggestionRef = useRef<string | undefined>(undefined);
  const suggestedMethod = defaultPaymentMethodForAccount(account, transactionType);
  const trimmedValue = value.trim();

  useEffect(() => {
    if (autoFill === 'off' || !suggestedMethod) {
      lastSuggestionRef.current = suggestedMethod;
      return;
    }

    const shouldAutofill =
      autoFill === 'suggested'
        ? !trimmedValue || trimmedValue === lastSuggestionRef.current
        : !trimmedValue;
    if (shouldAutofill && trimmedValue !== suggestedMethod) onChange(suggestedMethod);
    lastSuggestionRef.current = suggestedMethod;
  }, [autoFill, onChange, suggestedMethod, trimmedValue]);

  const options = useMemo(
    () => paymentMethodOptionsForAccount(account, transactionType, trimmedValue),
    [account, transactionType, trimmedValue],
  );
  const selectedValue = trimmedValue || suggestedMethod;
  const selectedOption = options.find((option) => option.value === selectedValue) ?? options[0];

  return (
    <>
      <RecordSelectorRow
        icon={selectedOption?.icon ?? 'credit-card-outline'}
        label="Payment method"
        value={selectedOption?.label ?? 'Choose method'}
        supporting={selectedOption?.description ?? 'Choose how this was paid'}
        onPress={() => setVisible(true)}
      />
      <OptionListOverlay
        visible={visible}
        title="Choose payment method"
        options={options}
        selectedValue={selectedValue}
        searchable={false}
        onDismiss={() => setVisible(false)}
        onSelect={(option) => {
          onChange(option.value);
          setVisible(false);
        }}
      />
    </>
  );
}

function paymentMethodOptionsForAccount(
  account: Pick<Account, 'type'> | undefined,
  transactionType: TransactionType,
  currentValue: string,
): OptionListItem<string>[] {
  const preferred = defaultPaymentMethodForAccount(account, transactionType);
  const accountMethods = account ? ACCOUNT_METHOD_ORDER[account.type] : [];
  const values = uniqueValues([preferred, ...accountMethods, ...BASE_METHOD_ORDER, currentValue]);
  return values.map((method) => {
    const definition = methodDefinition(method);
    return {
      value: method,
      label: definition.value,
      description: definition.description,
      icon: definition.icon,
    };
  });
}

function defaultPaymentMethodForAccount(
  account: Pick<Account, 'type'> | undefined,
  transactionType: TransactionType,
): string {
  if (
    transactionType === 'transfer' ||
    transactionType === 'card_payment' ||
    transactionType === 'loan_repayment'
  ) {
    return 'Bank transfer';
  }

  switch (account?.type) {
    case 'cash':
      return 'Cash';
    case 'credit_card':
      return 'Credit card';
    case 'debit_card':
      return 'Debit card';
    case 'wallet':
      return 'Wallet';
    case 'prepaid':
      return 'Prepaid card';
    case 'loan':
    case 'overdraft':
      return 'Loan payment';
    case 'investment':
    case 'crypto':
      return 'Investment transfer';
    case 'bank':
    case 'lent':
    case 'savings_goal':
      return 'Bank transfer';
    default:
      return 'Other';
  }
}

function methodDefinition(value: string): PaymentMethodDefinition {
  return (
    PAYMENT_METHODS.find((method) => method.value.toLowerCase() === value.toLowerCase()) ?? {
      value,
      description: 'Custom payment method',
      icon: 'credit-card-outline',
    }
  );
}

function uniqueValues(values: (string | undefined)[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const normalized = value?.trim();
    if (!normalized) continue;
    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(normalized);
  }
  return result;
}
