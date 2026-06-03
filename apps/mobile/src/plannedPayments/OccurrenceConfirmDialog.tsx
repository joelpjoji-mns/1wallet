import { formatMoney, fromMinor, toMinor } from '@1wallet/domain/money';
import type { Account } from '@1wallet/domain/types';
import { isLoanAccountType } from '@1wallet/ledger/loans';
import type {
  FutureRuleOccurrence,
  PostFutureRuleOccurrenceOverrides,
} from '@1wallet/ledger/rules/futureGeneration';
import { accountBalance } from '@1wallet/ledger/services';
import { indexedAccountBalance, type LedgerIndexes } from '@1wallet/ledger/services/indexes';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Button, Portal, Surface, Text, TextInput, useTheme } from 'react-native-paper';
import { resolveAccountIconVisual } from '../accountOptions';
import { useBackLayer } from '../components/AppBackLayer';
import { PremiumTextInput } from '../components/AppKit';
import { RecordDateTimeFields } from '../components/record/RecordDateTimeFields';
import { AccountPickerOverlay } from '../components/record/RecordPickers';
import { RecordSelectorRow } from '../components/record/RecordSelectorRow';
import {
  dateTimeToIso,
  isValidLocalDate,
  isValidLocalTime,
  localDateTimePartsFromIso,
} from '../recordDateTime';
import { dueLabel } from './display';

type PickerMode = 'account' | 'counter' | null;

type ConfirmDraft = {
  amountText: string;
  accountId?: string;
  counterAccountId?: string;
  date: string;
  time: string;
};

type InitialDateTime = 'occurrence' | 'now';

const TRANSFER_TYPES = new Set(['transfer', 'card_payment', 'loan_repayment']);

export function OccurrenceConfirmDialog({
  visible,
  rule,
  occurrence,
  state,
  indexes,
  title = 'Confirm payment',
  confirmLabel = 'Confirm record',
  initialDateTime = 'occurrence',
  onDismiss,
  onConfirm,
}: {
  visible: boolean;
  rule?: FutureGenerationRule | null;
  occurrence?: FutureRuleOccurrence;
  state: LedgerState;
  indexes?: LedgerIndexes;
  title?: string;
  confirmLabel?: string;
  initialDateTime?: InitialDateTime;
  onDismiss: () => void;
  onConfirm: (overrides: PostFutureRuleOccurrenceOverrides) => Promise<void> | void;
}) {
  const theme = useTheme();
  const [draft, setDraft] = useState<ConfirmDraft>(() => emptyDraft(occurrence, initialDateTime));
  const [pickerMode, setPickerMode] = useState<PickerMode>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (!visible) return;
    setDraft(emptyDraft(occurrence, initialDateTime));
    setPickerMode(null);
    setError(null);
    setBusy(false);
  }, [initialDateTime, occurrence, visible]);

  const isTransfer = Boolean(occurrence && TRANSFER_TYPES.has(occurrence.type));
  const currency = selectedCurrency(state, occurrence, draft.accountId);
  const totalMinor = toMinor(Math.max(0, parseAmount(draft.amountText)), currency);
  const split = occurrence ? loanSplit(occurrence, totalMinor) : undefined;
  const account = state.accounts.find((item) => item.id === draft.accountId);
  const counterAccount = state.accounts.find((item) => item.id === draft.counterAccountId);
  const accountVisual = account ? resolveAccountIconVisual(account) : undefined;
  const counterAccountVisual = counterAccount
    ? resolveAccountIconVisual(counterAccount)
    : undefined;
  const accounts = useMemo(
    () => accountChoices(state, currency, draft.accountId, draft.counterAccountId),
    [currency, draft.accountId, draft.counterAccountId, state],
  );
  const counterAccounts = accounts.filter((item) => item.id !== draft.accountId);

  if (!visible || !rule || !occurrence) return null;

  const update = (patch: Partial<ConfirmDraft>) =>
    setDraft((current) => ({ ...current, ...patch }));

  const confirm = async () => {
    const validation = validateDraft({
      rule,
      occurrence,
      draft,
      totalMinor,
      account,
      counterAccount,
      isTransfer,
    });
    if (!validation.ok) {
      setError(validation.message);
      return;
    }

    setBusy(true);
    setError(null);
    try {
      await onConfirm({
        accountId: draft.accountId,
        counterAccountId: isTransfer ? draft.counterAccountId : undefined,
        amountMinor: totalMinor,
        currency,
        occurredAt: dateTimeToIso(draft.date, draft.time, new Date(occurrence.occurredAt)),
      });
    } catch (caught) {
      setError((caught as Error).message);
      setBusy(false);
    }
  };

  return (
    <Portal>
      <Pressable style={styles.backdrop} onPress={onDismiss} />
      <Surface
        style={[
          styles.sheet,
          {
            backgroundColor: theme.colors.background,
            borderColor: theme.colors.outlineVariant,
          },
        ]}
        elevation={4}
      >
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.headerRow}>
            <View style={[styles.headerIcon, { backgroundColor: theme.colors.primaryContainer }]}>
              <MaterialCommunityIcons
                name="check-circle-outline"
                size={22}
                color={theme.colors.primary}
              />
            </View>
            <View style={styles.fill}>
              <Text variant="titleMedium" numberOfLines={1} style={styles.title}>
                {title}
              </Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {rule.name} · {dueLabel(occurrence.occurredAt, state.preferences.locale)}
              </Text>
            </View>
          </View>

          <PremiumTextInput
            mode="outlined"
            label={`Amount (${currency})`}
            value={draft.amountText}
            keyboardType="decimal-pad"
            onChangeText={(amountText) => update({ amountText })}
            left={<TextInput.Icon icon="cash-multiple" />}
          />

          <View style={styles.selectorGrid}>
            <RecordSelectorRow
              icon={accountVisual?.icon ?? 'wallet-outline'}
              iconBackgroundColor={accountVisual?.backgroundColor}
              iconColor={accountVisual?.iconColor}
              label={isTransfer ? 'From account' : 'Account'}
              value={account?.name ?? 'Choose account'}
              valueNumberOfLines={2}
              supporting={account ? accountSupporting(state, account, indexes) : 'Required'}
              onPress={() => setPickerMode('account')}
            />
            {isTransfer ? (
              <RecordSelectorRow
                icon={counterAccountVisual?.icon ?? 'swap-horizontal'}
                iconBackgroundColor={counterAccountVisual?.backgroundColor}
                iconColor={counterAccountVisual?.iconColor}
                label="To account"
                value={counterAccount?.name ?? 'Choose destination'}
                valueNumberOfLines={2}
                supporting={
                  counterAccount ? accountSupporting(state, counterAccount, indexes) : 'Required'
                }
                onPress={() => setPickerMode('counter')}
              />
            ) : null}
          </View>

          <RecordDateTimeFields
            date={draft.date}
            time={draft.time}
            onChangeDate={(date) => update({ date })}
            onChangeTime={(time) => update({ time })}
          />

          <View style={[styles.reviewBox, { borderColor: theme.colors.outlineVariant }]}>
            {split ? (
              <ReviewLine
                label="EMI"
                value={formatMoney(
                  { amountMinor: split.principalMinor, currency },
                  state.preferences.locale,
                )}
              />
            ) : null}
            {isTransfer && counterAccount ? (
              <ReviewLine label="Destination" value={counterAccount.name} />
            ) : null}
            {split ? (
              <>
                <ReviewLine
                  label="Interest debit"
                  value={formatMoney(
                    { amountMinor: split.interestMinor, currency },
                    state.preferences.locale,
                  )}
                />
                <ReviewLine
                  label="Total"
                  value={formatMoney(
                    { amountMinor: totalMinor, currency },
                    state.preferences.locale,
                  )}
                />
              </>
            ) : (
              <ReviewLine
                label="Total"
                value={formatMoney({ amountMinor: totalMinor, currency }, state.preferences.locale)}
              />
            )}
          </View>

          {error ? (
            <Text variant="bodySmall" style={{ color: theme.colors.error }}>
              {error}
            </Text>
          ) : null}

          <View style={styles.actionRow}>
            <Button mode="text" onPress={onDismiss} disabled={busy}>
              Cancel
            </Button>
            <Button
              mode="contained"
              icon="check-circle-outline"
              loading={busy}
              disabled={busy}
              onPress={() => void confirm()}
            >
              {confirmLabel}
            </Button>
          </View>
        </ScrollView>
      </Surface>

      <AccountPickerOverlay
        visible={pickerMode === 'account' || pickerMode === 'counter'}
        title={pickerMode === 'counter' ? 'Choose destination' : 'Choose account'}
        accounts={pickerMode === 'counter' ? counterAccounts : accounts}
        selectedId={pickerMode === 'counter' ? draft.counterAccountId : draft.accountId}
        balances={(item) => accountSupporting(state, item, indexes)}
        onDismiss={() => setPickerMode(null)}
        onCreate={() => {
          setPickerMode(null);
          router.push('/account/new' as never);
        }}
        onSelect={(item) => {
          if (pickerMode === 'counter') {
            update({ counterAccountId: item.id });
          } else {
            update({
              accountId: item.id,
              counterAccountId:
                draft.counterAccountId === item.id ? undefined : draft.counterAccountId,
            });
          }
          setPickerMode(null);
        }}
      />
    </Portal>
  );
}

function ReviewLine({ label, value }: { label: string; value: string }) {
  const theme = useTheme();
  return (
    <View style={styles.reviewLine}>
      <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
        {label}
      </Text>
      <Text variant="bodyMedium" numberOfLines={1} style={styles.reviewValue}>
        {value}
      </Text>
    </View>
  );
}

function emptyDraft(
  occurrence?: FutureRuleOccurrence,
  initialDateTime: InitialDateTime = 'occurrence',
): ConfirmDraft {
  const dateTime =
    occurrence && initialDateTime === 'occurrence'
      ? localDateTimePartsFromIso(occurrence.occurredAt)
      : localDateTimePartsFromIso(new Date().toISOString());
  return {
    amountText: occurrence ? String(fromMinor(occurrence.amountMinor, occurrence.currency)) : '',
    accountId: occurrence?.accountId,
    counterAccountId: occurrence?.counterAccountId,
    date: dateTime.date,
    time: dateTime.time,
  };
}

function validateDraft({
  occurrence,
  draft,
  totalMinor,
  account,
  counterAccount,
  isTransfer,
}: {
  rule: FutureGenerationRule;
  occurrence: FutureRuleOccurrence;
  draft: ConfirmDraft;
  totalMinor: number;
  account?: Account;
  counterAccount?: Account;
  isTransfer: boolean;
}): { ok: true } | { ok: false; message: string } {
  if (!account || !draft.accountId) return { ok: false, message: 'Choose an account' };
  if (totalMinor <= 0) return { ok: false, message: 'Enter a positive amount' };
  if (!isValidLocalDate(draft.date)) return { ok: false, message: 'Enter a valid date' };
  if (!isValidLocalTime(draft.time)) return { ok: false, message: 'Enter a valid time' };
  if (isTransfer && (!counterAccount || !draft.counterAccountId)) {
    return { ok: false, message: 'Choose a destination account' };
  }
  if (isTransfer && draft.counterAccountId === draft.accountId) {
    return { ok: false, message: 'Destination must differ from the source account' };
  }
  if (occurrence.type === 'loan_repayment') {
    const hasLoanAccount =
      isLoanAccountType(account.type) ||
      Boolean(counterAccount && isLoanAccountType(counterAccount.type));
    if (!hasLoanAccount) return { ok: false, message: 'Loan EMI needs a loan account' };
  }
  return { ok: true };
}

function loanSplit(
  occurrence: FutureRuleOccurrence,
  totalMinor: number,
): { principalMinor: number; interestMinor: number } | undefined {
  if (occurrence.type !== 'loan_repayment' || occurrence.principalAmountMinor === undefined) {
    return undefined;
  }
  const forecastInterestMinor = Math.max(
    0,
    occurrence.interestAmountMinor ??
      occurrence.amountMinor - Math.max(0, occurrence.principalAmountMinor),
  );
  const interestMinor = Math.min(totalMinor, forecastInterestMinor);
  return { principalMinor: Math.max(0, totalMinor - interestMinor), interestMinor };
}

function accountChoices(
  state: LedgerState,
  currency: string,
  accountId?: string,
  counterAccountId?: string,
): Account[] {
  return state.accounts
    .filter(
      (account) =>
        !account.isArchived || account.id === accountId || account.id === counterAccountId,
    )
    .filter((account) => account.currency === currency)
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

function selectedCurrency(
  state: LedgerState,
  occurrence: FutureRuleOccurrence | undefined,
  accountId?: string,
): string {
  const account = accountId ? state.accounts.find((item) => item.id === accountId) : undefined;
  return account?.currency ?? occurrence?.currency ?? state.preferences.baseCurrency;
}

function accountSupporting(state: LedgerState, account: Account, indexes?: LedgerIndexes): string {
  const balance = indexes
    ? indexedAccountBalance(indexes, account)
    : accountBalance(state, account.id);
  return formatMoney(balance, state.preferences.locale);
}

function parseAmount(value: string): number {
  return Number(value.replace(/,/g, '').trim()) || 0;
}

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(0,0,0,0.42)',
  },
  sheet: {
    position: 'absolute',
    left: tokens.space.md,
    right: tokens.space.md,
    bottom: tokens.space.lg,
    maxHeight: '88%',
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  content: {
    gap: tokens.space.md,
    padding: tokens.space.md,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
  },
  headerIcon: {
    width: 42,
    height: 42,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fill: { flex: 1, minWidth: 0 },
  title: { fontWeight: '800' },
  selectorGrid: { gap: tokens.space.sm },
  reviewBox: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    padding: tokens.space.sm,
    gap: tokens.space.xs,
  },
  reviewLine: {
    minHeight: 28,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
  },
  reviewValue: {
    flexShrink: 1,
    maxWidth: '58%',
    textAlign: 'right',
    fontWeight: '700',
  },
  actionRow: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: tokens.space.sm,
  },
});
