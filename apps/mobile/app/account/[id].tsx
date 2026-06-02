import { formatMoney } from '@1wallet/domain/money';
import type { Account } from '@1wallet/domain/types';
import {
  buildAccountMatchIdentifiers,
  buildAccountMessageSourceHints,
} from '@1wallet/ledger/capture/messages';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
} from 'react-native';
import { Appbar, HelperText, useTheme } from 'react-native-paper';
import {
  ACCOUNT_COLOR_OPTIONS,
  ACCOUNT_ICON_OPTIONS,
  ACCOUNT_TYPE_OPTIONS,
  accountIconForType,
  accountTypeLabel,
  DEFAULT_ACCOUNT_COLOR,
  resolveAccountIconVisual,
} from '../../src/accountOptions';
import { goBackOrHome, PremiumTextInput, resolveAppIconName } from '../../src/components/AppKit';
import {
  ColorPickerIconPreview,
  ColorPickerOverlay,
} from '../../src/components/ColorPickerOverlay';
import { OptionListOverlay, OptionSelectorRow } from '../../src/components/OptionListOverlay';
import { loanCadenceLabel } from '../../src/loans/loanUtils';
import { useAutoSaveDraft } from '../../src/useAutoSaveDraft';

type AccountPicker = 'type' | 'icon' | 'color' | null;
type AccountProfileDraft = { name: string; institution: string };
type AccountAutomationDraft = {
  lastFour: string;
  upiIds: string;
  smsSenderIds: string;
  emailDomains: string;
};
type NormalizedAccountAutomationDraft = {
  lastFour: string;
  upiIds: string[];
  smsSenderIds: string[];
  emailDomains: string[];
};

export default function AccountDetail() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, indexes, selectors, editAccount, removeAccount, saveError } = useLedger();
  const acct = id ? indexes.accountsById.get(id) : undefined;
  const [picker, setPicker] = useState<AccountPicker>(null);
  const [nameDraft, setNameDraft] = useState('');
  const [institutionDraft, setInstitutionDraft] = useState('');
  const [profileTouched, setProfileTouched] = useState(false);
  const profileAccountIdRef = useRef<string | null>(null);
  const savedProfileDraft = useMemo<AccountProfileDraft>(
    () => ({ name: acct?.name ?? nameDraft, institution: acct?.institution ?? institutionDraft }),
    [acct?.institution, acct?.name, institutionDraft, nameDraft],
  );
  const profileDraft = useMemo<AccountProfileDraft>(
    () => ({ name: nameDraft, institution: institutionDraft }),
    [institutionDraft, nameDraft],
  );
  const saveAccountProfile = useCallback(
    async (nextProfile: AccountProfileDraft) => {
      if (!acct) return;
      await editAccount(acct.id, nextProfile);
    },
    [acct, editAccount],
  );
  const profileAutosave = useAutoSaveDraft<AccountProfileDraft>({
    value: profileDraft,
    savedValue: savedProfileDraft,
    sourceKey: acct?.id,
    save: saveAccountProfile,
    disabled: !acct || !profileTouched,
    normalize: normalizeAccountProfileDraft,
    validate: (draft) => Boolean(draft.name),
    isEqual: accountProfileDraftsEqual,
  });
  const accountBalance = acct ? indexedAccountBalance(indexes, acct) : undefined;

  useEffect(() => {
    if (!acct) return;
    if (profileAccountIdRef.current !== acct.id) {
      profileAccountIdRef.current = acct.id;
      setNameDraft(acct.name);
      setInstitutionDraft(acct.institution ?? '');
      setProfileTouched(false);
      return;
    }
    if (!profileTouched) {
      setNameDraft(acct.name);
      setInstitutionDraft(acct.institution ?? '');
    }
  }, [acct, profileTouched]);

  useEffect(() => {
    if (!acct || !profileTouched) return;
    const normalizedDraft = normalizeAccountProfileDraft(profileDraft);
    if (accountProfileDraftsEqual(normalizedDraft, savedProfileDraft)) {
      setProfileTouched(false);
    }
  }, [acct, profileDraft, profileTouched, savedProfileDraft]);

  if (!acct) {
    return (
      <View style={s.empty}>
        <Text style={{ color: theme.colors.onSurfaceVariant }}>Account not found.</Text>
      </View>
    );
  }
  const balance = accountBalance ?? indexedAccountBalance(indexes, acct);
  const viewCurrency = selectors.displayCurrency(state);
  const displayBalance = selectors.convertMoneyForDisplay(state, balance, viewCurrency);
  const hasTransactions = (indexes.transactionsByAccountId.get(acct.id)?.length ?? 0) > 0;
  const isLoanLike = acct.type === 'loan' || acct.type === 'overdraft' || acct.type === 'lent';
  const selectedIcon = resolveAppIconName(acct.icon, accountIconForType(acct.type));
  const typeVisual = resolveAccountIconVisual({
    type: acct.type,
    icon: accountIconForType(acct.type),
    color: acct.color,
  });
  const selectedVisual = resolveAccountIconVisual({
    type: acct.type,
    icon: selectedIcon,
    color: acct.color,
  });
  const profileStatusLabel = accountProfileStatusLabel(profileAutosave.status);
  const profileError =
    profileAutosave.status === 'error'
      ? autosaveErrorMessage(profileAutosave.error, 'Could not update account details')
      : saveError;

  const confirmDelete = () => {
    const title = hasTransactions ? 'Archive account?' : 'Delete account?';
    const message = hasTransactions
      ? `${acct.name} has transactions, so it will be archived instead of permanently deleted.`
      : `${acct.name} has no transactions and will be permanently deleted.`;
    Alert.alert(title, message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: hasTransactions ? 'Archive' : 'Delete',
        style: 'destructive',
        onPress: async () => {
          await removeAccount(acct.id);
          goBackOrHome();
        },
      },
    ]);
  };

  return (
    <View style={[s.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <Appbar.BackAction onPress={goBackOrHome} />
        <Appbar.Content title={acct.name} titleStyle={s.appbarTitle} />
        <Appbar.Action
          icon={acct.isArchived ? 'archive-arrow-up-outline' : 'archive-outline'}
          accessibilityLabel={acct.isArchived ? 'Unarchive account' : 'Archive account'}
          onPress={() => void editAccount(acct.id, { isArchived: !acct.isArchived })}
        />
      </Appbar.Header>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={s.fill}>
        <ScrollView
          style={{ backgroundColor: theme.colors.background }}
          contentContainerStyle={s.content}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
        >
          <View
            style={[
              s.card,
              {
                backgroundColor: theme.colors.elevation.level1,
                borderColor: theme.colors.outlineVariant,
              },
            ]}
          >
            <View style={s.profileHeader}>
              <View style={[s.accountAvatar, { backgroundColor: selectedVisual.backgroundColor }]}>
                <MaterialCommunityIcons
                  name={selectedVisual.icon}
                  size={26}
                  color={selectedVisual.iconColor}
                />
              </View>
              <View style={s.fill}>
                <Text style={[s.sectionTitle, { color: theme.colors.onSurface }]}>
                  Manage account
                </Text>
                <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
                  {accountTypeLabel(acct.type)} · {acct.currency}
                </Text>
              </View>
            </View>

            <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>Name</Text>
            <PremiumTextInput
              value={nameDraft}
              onChangeText={(value) => {
                setProfileTouched(true);
                setNameDraft(value);
              }}
              placeholder="Account name"
            />
            <HelperText type="error" visible={profileTouched && !nameDraft.trim()}>
              Enter an account name.
            </HelperText>

            <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>Institution</Text>
            <PremiumTextInput
              value={institutionDraft}
              onChangeText={(value) => {
                setProfileTouched(true);
                setInstitutionDraft(value);
              }}
              placeholder="Bank, wallet, issuer"
            />

            <OptionSelectorRow
              label="Type"
              value={accountTypeLabel(acct.type)}
              description="Account behavior and reporting group"
              icon={typeVisual.icon}
              iconBackgroundColor={typeVisual.backgroundColor}
              iconColor={typeVisual.iconColor}
              onPress={() => setPicker('type')}
            />
            <OptionSelectorRow
              label="Icon"
              value={optionLabel(ACCOUNT_ICON_OPTIONS, selectedIcon)}
              description="Shown in account lists and widgets"
              icon={selectedVisual.icon}
              iconBackgroundColor={selectedVisual.backgroundColor}
              iconColor={selectedVisual.iconColor}
              onPress={() => setPicker('icon')}
            />

            <OptionSelectorRow
              label="Color"
              value="Selected color"
              description="Icon accent"
              icon={selectedVisual.icon}
              iconBackgroundColor={selectedVisual.backgroundColor}
              iconColor={selectedVisual.iconColor}
              onPress={() => setPicker('color')}
            />
            {profileStatusLabel ? (
              <Text style={[s.helperText, { color: theme.colors.onSurfaceVariant }]}>
                {profileStatusLabel}
              </Text>
            ) : null}
            <HelperText type="error" visible={Boolean(profileError)}>
              {profileError ?? ' '}
            </HelperText>
          </View>

          {isLoanLike ? (
            <View
              style={[
                s.card,
                {
                  backgroundColor: theme.colors.elevation.level1,
                  borderColor: theme.colors.outlineVariant,
                },
              ]}
            >
              <Text style={[s.sectionTitle, { color: theme.colors.onSurface }]}>Loan plan</Text>
              <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
                Configure interest, recurrence, repayment source, and payoff forecasts in Loans.
              </Text>
              <LoanDetailRow label="Loan type" value={loanKindLabel(acct)} />
              <LoanDetailRow
                label="Principal"
                value={
                  acct.loanDetails?.principal
                    ? formatMoney(acct.loanDetails.principal, state.preferences.locale)
                    : 'Not set'
                }
              />
              <LoanDetailRow
                label="EMI principal"
                value={
                  acct.loanDetails?.repaymentAmount
                    ? formatMoney(acct.loanDetails.repaymentAmount, state.preferences.locale)
                    : 'Not scheduled'
                }
              />
              <LoanDetailRow
                label="Repeat"
                value={loanCadenceLabel(acct.loanDetails, state.preferences.locale)}
              />
              <Pressable
                style={[s.saveButton, { backgroundColor: theme.colors.secondaryContainer }]}
                onPress={() =>
                  router.push({ pathname: '/loans', params: { loanId: acct.id } } as never)
                }
              >
                <Text style={[s.saveButtonText, { color: theme.colors.onSecondaryContainer }]}>
                  Configure loan plan
                </Text>
              </Pressable>
            </View>
          ) : null}

          <View
            style={[
              s.card,
              {
                backgroundColor: theme.colors.elevation.level1,
                borderColor: theme.colors.outlineVariant,
              },
            ]}
          >
            <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>Balance</Text>
            <Text style={[s.hero, { color: theme.colors.onSurface }]}>
              {formatMoney(balance, state.preferences.locale)}
            </Text>
            {balance.currency !== displayBalance.currency ? (
              <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
                {formatMoney(displayBalance, state.preferences.locale)} in display currency
              </Text>
            ) : null}
            <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
              {accountTypeLabel(acct.type)} · {acct.currency}
            </Text>
          </View>

          <View
            style={[
              s.card,
              {
                backgroundColor: theme.colors.elevation.level1,
                borderColor: theme.colors.outlineVariant,
              },
            ]}
          >
            <ToggleRow
              label="Archived"
              value={acct.isArchived}
              onChange={(v) => editAccount(acct.id, { isArchived: v })}
            />
            <ToggleRow
              label="Show on Home"
              value={acct.showOnHome}
              onChange={(v) => editAccount(acct.id, { showOnHome: v })}
            />
            <ToggleRow
              label="Include in totals"
              value={acct.includeInTotals}
              onChange={(v) => editAccount(acct.id, { includeInTotals: v })}
            />
            <ToggleRow
              label="Include in budgets"
              value={acct.includeInBudgets}
              onChange={(v) => editAccount(acct.id, { includeInBudgets: v })}
            />
            <ToggleRow
              label="Include in reports"
              value={acct.includeInReports}
              onChange={(v) => editAccount(acct.id, { includeInReports: v })}
            />
            <ToggleRow
              label="Include in net worth"
              value={acct.includeInNetWorth}
              onChange={(v) => editAccount(acct.id, { includeInNetWorth: v })}
            />
          </View>

          <AccountAutomationDetails
            account={acct}
            onSave={(patch) => editAccount(acct.id, patch)}
          />

          <Pressable
            style={[s.danger, { backgroundColor: theme.colors.errorContainer }]}
            onPress={confirmDelete}
          >
            <Text style={[s.dangerText, { color: theme.colors.onErrorContainer }]}>
              {hasTransactions ? 'Archive account' : 'Delete account'}
            </Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
      <OptionListOverlay
        visible={picker === 'type'}
        title="Account type"
        options={ACCOUNT_TYPE_OPTIONS}
        selectedValue={acct.type}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          void editAccount(acct.id, { type: option.value });
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'icon'}
        title="Account icon"
        options={ACCOUNT_ICON_OPTIONS}
        selectedValue={selectedIcon}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          void editAccount(acct.id, { icon: option.value });
          setPicker(null);
        }}
      />
      <ColorPickerOverlay
        visible={picker === 'color'}
        title="Account color"
        selectedColor={selectedVisual.backgroundColor}
        fallbackColor={DEFAULT_ACCOUNT_COLOR}
        swatches={ACCOUNT_COLOR_OPTIONS}
        saveLabel="Apply account color"
        accessibilityLabelPrefix="Account color"
        onDismiss={() => setPicker(null)}
        onSave={(color) => {
          void editAccount(acct.id, { color });
          setPicker(null);
        }}
        renderPreview={(color) => (
          <ColorPickerIconPreview
            color={color}
            icon={selectedIcon}
            title={nameDraft.trim() || acct.name}
            subtitle={accountTypeLabel(acct.type)}
          />
        )}
      />
    </View>
  );
}

function AccountAutomationDetails({
  account,
  onSave,
}: {
  account: Account;
  onSave: (patch: {
    matchIdentifiers?: Account['matchIdentifiers'];
    messageSourceHints?: Account['messageSourceHints'];
  }) => Promise<void> | void;
}) {
  const theme = useTheme();
  const [lastFour, setLastFour] = useState(lastFourFromAccount(account));
  const [upiIds, setUpiIds] = useState(identifierValues(account, 'upi_vpa').join(', '));
  const [smsSenderIds, setSmsSenderIds] = useState(
    (account.messageSourceHints?.smsSenderIds ?? []).join(', '),
  );
  const [emailDomains, setEmailDomains] = useState(
    (account.messageSourceHints?.emailDomains ?? []).join(', '),
  );
  const [automationTouched, setAutomationTouched] = useState(false);
  const automationAccountIdRef = useRef<string | null>(null);
  const savedAutomationDraft = useMemo(() => accountAutomationDraftFromAccount(account), [account]);
  const automationDraft = useMemo<AccountAutomationDraft>(
    () => ({ lastFour, upiIds, smsSenderIds, emailDomains }),
    [emailDomains, lastFour, smsSenderIds, upiIds],
  );
  const saveAutomation = useCallback(
    async (draft: NormalizedAccountAutomationDraft) => {
      const matchIdentifiers = buildAccountMatchIdentifiers({
        accountType: account.type,
        lastFour: draft.lastFour,
        upiVpas: draft.upiIds,
        existing: account.matchIdentifiers,
      });
      const messageSourceHints = buildAccountMessageSourceHints({
        smsSenderIds: draft.smsSenderIds,
        emailDomains: draft.emailDomains,
        keywords: [account.institution, account.name].filter((value): value is string =>
          Boolean(value),
        ),
      });
      await onSave({
        matchIdentifiers: matchIdentifiers.length ? matchIdentifiers : undefined,
        messageSourceHints,
      });
    },
    [account, onSave],
  );
  const automationAutosave = useAutoSaveDraft<
    AccountAutomationDraft,
    NormalizedAccountAutomationDraft
  >({
    value: automationDraft,
    savedValue: savedAutomationDraft,
    sourceKey: account.id,
    save: saveAutomation,
    disabled: !automationTouched,
    normalize: normalizeAccountAutomationDraft,
    isEqual: accountAutomationDraftsEqual,
  });
  const automationStatusLabel = accountProfileStatusLabel(automationAutosave.status);
  const automationError =
    automationAutosave.status === 'error'
      ? autosaveErrorMessage(automationAutosave.error, 'Could not update matching details')
      : null;

  useEffect(() => {
    if (automationAccountIdRef.current !== account.id) {
      automationAccountIdRef.current = account.id;
      setLastFour(savedAutomationDraft.lastFour);
      setUpiIds(savedAutomationDraft.upiIds);
      setSmsSenderIds(savedAutomationDraft.smsSenderIds);
      setEmailDomains(savedAutomationDraft.emailDomains);
      setAutomationTouched(false);
      return;
    }
    if (!automationTouched) {
      setLastFour(savedAutomationDraft.lastFour);
      setUpiIds(savedAutomationDraft.upiIds);
      setSmsSenderIds(savedAutomationDraft.smsSenderIds);
      setEmailDomains(savedAutomationDraft.emailDomains);
    }
  }, [account.id, automationTouched, savedAutomationDraft]);

  useEffect(() => {
    if (!automationTouched) return;
    if (
      accountAutomationDraftsEqual(
        normalizeAccountAutomationDraft(automationDraft),
        normalizeAccountAutomationDraft(savedAutomationDraft),
      )
    ) {
      setAutomationTouched(false);
    }
  }, [automationDraft, automationTouched, savedAutomationDraft]);

  return (
    <View
      style={[
        s.card,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      <Text style={[s.sectionTitle, { color: theme.colors.onSurface }]}>Message matching</Text>
      <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
        Card or account last 4
      </Text>
      <PremiumTextInput
        value={lastFour}
        onChangeText={(value) => {
          setAutomationTouched(true);
          setLastFour(value);
        }}
        keyboardType="number-pad"
        placeholder="1234"
      />
      <Text style={[s.helperText, { color: theme.colors.onSurfaceVariant }]}>
        Used to route SMS, email, and notification captures when a message mentions this ending.
      </Text>
      <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>UPI IDs from alerts</Text>
      <PremiumTextInput
        value={upiIds}
        onChangeText={(value) => {
          setAutomationTouched(true);
          setUpiIds(value);
        }}
        autoCapitalize="none"
        placeholder="name@bank, phone@upi"
      />
      <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>Saved SMS senders</Text>
      <PremiumTextInput
        value={smsSenderIds}
        onChangeText={(value) => {
          setAutomationTouched(true);
          setSmsSenderIds(value);
        }}
        autoCapitalize="characters"
        placeholder="HDFCBK, MONZO"
      />
      <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>Saved email domains</Text>
      <PremiumTextInput
        value={emailDomains}
        onChangeText={(value) => {
          setAutomationTouched(true);
          setEmailDomains(value);
        }}
        autoCapitalize="none"
        placeholder="alerts.bank.co.uk"
      />
      {automationStatusLabel ? (
        <View style={s.autosaveStatusRow}>
          <MaterialCommunityIcons
            name={automationAutosave.status === 'saved' ? 'check' : 'sync'}
            size={16}
            color={theme.colors.onSurfaceVariant}
          />
          <Text style={[s.helperText, { color: theme.colors.onSurfaceVariant }]}>
            {automationStatusLabel}
          </Text>
        </View>
      ) : null}
      <HelperText type="error" visible={Boolean(automationError)}>
        {automationError ?? ' '}
      </HelperText>
    </View>
  );
}

function ToggleRow({
  label,
  value,
  onChange,
}: {
  label: string;
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  const theme = useTheme();
  return (
    <View style={s.toggleRow}>
      <Text style={[s.toggleLabel, { color: theme.colors.onSurface }]}>{label}</Text>
      <Switch value={value} onValueChange={onChange} />
    </View>
  );
}

function LoanDetailRow({ label, value }: { label: string; value: string }) {
  const theme = useTheme();
  return (
    <View style={s.detailRow}>
      <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>{label}</Text>
      <Text style={[s.detailValue, { color: theme.colors.onSurface }]}>{value}</Text>
    </View>
  );
}

function loanKindLabel(account: Account): string {
  const kind = account.loanDetails?.loanKind;
  if (kind === 'home') return 'Home loan';
  if (kind === 'vehicle') return 'Vehicle loan';
  if (kind === 'education') return 'Education loan';
  if (kind === 'business') return 'Business loan';
  if (kind === 'gold') return 'Gold loan';
  if (kind === 'bnpl') return 'BNPL / EMI card';
  if (kind === 'overdraft') return 'Overdraft';
  if (kind === 'lent') return 'Money lent';
  if (kind === 'other') return 'Other loan';
  return account.type === 'overdraft'
    ? 'Overdraft'
    : account.type === 'lent'
      ? 'Money lent'
      : 'Personal loan';
}

function lastFourFromAccount(account: Account): string {
  return (
    identifierValues(account, 'card_last4')[0] ??
    identifierValues(account, 'account_last4')[0] ??
    identifierValues(account, 'masked_number')[0] ??
    ''
  );
}

function identifierValues(
  account: Account,
  kind: NonNullable<Account['matchIdentifiers']>[number]['kind'],
) {
  return (account.matchIdentifiers ?? [])
    .filter((identifier) => identifier.kind === kind)
    .map((identifier) => identifier.value);
}

function splitList(value: string): string[] {
  return value
    .split(/[,\n;]/g)
    .map((item) => item.trim())
    .filter(Boolean);
}

function accountAutomationDraftFromAccount(account: Account): AccountAutomationDraft {
  return {
    lastFour: lastFourFromAccount(account),
    upiIds: identifierValues(account, 'upi_vpa').join(', '),
    smsSenderIds: (account.messageSourceHints?.smsSenderIds ?? []).join(', '),
    emailDomains: (account.messageSourceHints?.emailDomains ?? []).join(', '),
  };
}

function normalizeAccountAutomationDraft(
  draft: AccountAutomationDraft,
): NormalizedAccountAutomationDraft {
  return {
    lastFour: normalizeLastFourDraft(draft.lastFour),
    upiIds: normalizeUniqueList(draft.upiIds, (value) => value.toLowerCase()),
    smsSenderIds: normalizeUniqueList(draft.smsSenderIds, (value) =>
      value.toUpperCase().replace(/[^A-Z0-9]/g, ''),
    ),
    emailDomains: normalizeUniqueList(draft.emailDomains, normalizeEmailDomainDraft),
  };
}

function normalizeLastFourDraft(value: string): string {
  const digits = value.replace(/\D/g, '');
  return digits.length >= 4 ? digits.slice(-4) : '';
}

function normalizeUniqueList(value: string, normalize: (item: string) => string): string[] {
  return Array.from(new Set(splitList(value).map(normalize).filter(Boolean)));
}

function normalizeEmailDomainDraft(value: string): string {
  const normalized = value.trim().toLowerCase();
  const [, domain = normalized] = normalized.split('@');
  return domain.replace(/^www\./, '');
}

function accountAutomationDraftsEqual(
  left: NormalizedAccountAutomationDraft,
  right: NormalizedAccountAutomationDraft,
) {
  return (
    left.lastFour === right.lastFour &&
    stringArraysEqual(left.upiIds, right.upiIds) &&
    stringArraysEqual(left.smsSenderIds, right.smsSenderIds) &&
    stringArraysEqual(left.emailDomains, right.emailDomains)
  );
}

function stringArraysEqual(left: string[], right: string[]) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function optionLabel<TValue extends string>(
  options: readonly { value: TValue; label: string }[],
  value: TValue,
) {
  return options.find((option) => option.value === value)?.label ?? value;
}

function normalizeAccountProfileDraft(draft: AccountProfileDraft): AccountProfileDraft {
  return {
    name: draft.name.trim(),
    institution: draft.institution.trim(),
  };
}

function accountProfileDraftsEqual(left: AccountProfileDraft, right: AccountProfileDraft) {
  return left.name === right.name && left.institution === right.institution;
}

function accountProfileStatusLabel(status: string) {
  if (status === 'saving') return 'Saving...';
  if (status === 'saved') return 'Saved';
  return '';
}

function autosaveErrorMessage(error: unknown, fallback: string) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string' && error.trim()) return error;
  return fallback;
}

const s = StyleSheet.create({
  screen: { flex: 1 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: tokens.space.xl },
  appbarTitle: { fontWeight: '700' },
  content: { padding: tokens.space.lg, gap: tokens.space.md, paddingBottom: 112 },
  card: {
    borderRadius: tokens.radius.lg,
    padding: tokens.space.lg,
    borderWidth: 1,
    gap: tokens.space.sm,
  },
  profileHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    marginBottom: tokens.space.sm,
  },
  accountAvatar: {
    width: 52,
    height: 52,
    borderRadius: tokens.radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fill: { flex: 1 },
  hero: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    fontSize: tokens.font.size.hero,
    fontWeight: '800',
  },
  muted: { fontFamily: tokens.font.nativeFamily.regular },
  helperText: {
    fontFamily: tokens.font.nativeFamily.regular,
    fontSize: tokens.font.size.sm,
    marginTop: -tokens.space.sm,
  },
  autosaveStatusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    minHeight: 20,
  },
  label: {
    fontFamily: tokens.font.nativeFamily.medium,
    fontSize: tokens.font.size.sm,
    fontWeight: '600',
  },
  sectionTitle: {
    fontFamily: tokens.font.nativeFamily.medium,
    fontWeight: '700',
    marginBottom: tokens.space.xs,
  },
  input: {
    fontFamily: tokens.font.nativeFamily.regular,
    borderWidth: 1,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
    fontSize: tokens.font.size.md,
  },
  saveButton: {
    padding: tokens.space.md,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
  },
  saveButtonText: { fontFamily: tokens.font.nativeFamily.medium, fontWeight: '700' },
  toggleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: tokens.space.sm,
  },
  toggleLabel: { fontFamily: tokens.font.nativeFamily.regular, fontSize: tokens.font.size.md },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingVertical: tokens.space.xs,
  },
  detailValue: {
    fontFamily: tokens.font.nativeFamily.medium,
    fontWeight: '700',
    flexShrink: 1,
    textAlign: 'right',
  },
  danger: {
    padding: tokens.space.md,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
  },
  dangerText: { fontFamily: tokens.font.nativeFamily.medium, fontWeight: '700' },
});
