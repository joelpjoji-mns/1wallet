import { toMinor } from '@1wallet/domain/money';
import type { AccountType } from '@1wallet/domain/types';
import { buildAccountMatchIdentifiers } from '@1wallet/ledger/capture/messages';
import { enabledCurrencies } from '@1wallet/ledger/services';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useMemo, useState } from 'react';
import {
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
    DEFAULT_ACCOUNT_COLOR,
    resolveAccountIconVisual,
} from '../../src/accountOptions';
import { goBackOrHome, PremiumTextInput } from '../../src/components/AppKit';
import {
    ColorPickerIconPreview,
    ColorPickerOverlay,
} from '../../src/components/ColorPickerOverlay';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../../src/components/OptionListOverlay';
import { buildEnabledCurrencyOptions, currencyOptionIcon } from '../../src/currencyOptions';
import { normalizeHexColor } from '../../src/theme';

type AccountPicker = 'type' | 'currency' | 'icon' | 'color' | null;

export default function NewAccount() {
  const theme = useTheme();
  const { state, addAccount } = useLedger();
  const [name, setName] = useState('');
  const [type, setType] = useState<AccountType>('bank');
  const [icon, setIcon] = useState(accountIconForType('bank'));
  const [color, setColor] = useState<string>(DEFAULT_ACCOUNT_COLOR);
  const [currency, setCurrency] = useState(state.preferences.baseCurrency);
  const [picker, setPicker] = useState<AccountPicker>(null);
  const [opening, setOpening] = useState('0');
  const [institution, setInstitution] = useState('');
  const [lastFour, setLastFour] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const [includeInTotals, setIncludeInTotals] = useState(true);
  const [includeInBudgets, setIncludeInBudgets] = useState(true);
  const [includeInNetWorth, setIncludeInNetWorth] = useState(true);
  const currencyOptions = useMemo(
    () =>
      buildEnabledCurrencyOptions(enabledCurrencies(state), [
        currency,
        state.preferences.baseCurrency,
      ]),
    [currency, state],
  );
  const isBorrowedLoan = type === 'loan' || type === 'overdraft';
  const isLoanLike = isBorrowedLoan || type === 'lent';
  const typeVisual = resolveAccountIconVisual({ type, icon: accountIconForType(type), color });
  const iconVisual = resolveAccountIconVisual({ type, icon, color });

  const save = async () => {
    setSubmitted(true);
    if (!name.trim()) return;
    const amount = Number(opening.replace(/,/g, '')) || 0;
    const principalMinor = Math.abs(toMinor(amount, currency));
    const accountColor = normalizeHexColor(color) ?? DEFAULT_ACCOUNT_COLOR;
    const matchIdentifiers = buildAccountMatchIdentifiers({
      accountType: type,
      lastFour,
    });
    await addAccount({
      name: name.trim(),
      type,
      currency,
      openingBalanceMinor: isBorrowedLoan ? -principalMinor : toMinor(amount, currency),
      institution: institution.trim() || undefined,
      icon,
      color: accountColor,
      loanDetails: isLoanLike
        ? {
            loanKind: type === 'overdraft' ? 'overdraft' : type === 'lent' ? 'lent' : 'personal',
            principal: { amountMinor: principalMinor, currency },
            interestRatePercent: 0,
            interestRatePeriod: 'annual',
            interestMethod: 'reducing_balance',
            repaymentFrequency: 'monthly',
            repaymentInterval: 1,
            repaymentDayOfMonth: new Date().getDate(),
            autoCreateScheduledRecords: true,
          }
        : undefined,
      matchIdentifiers: matchIdentifiers.length ? matchIdentifiers : undefined,
      includeInTotals,
      includeInBudgets,
      includeInReports: true,
      includeInNetWorth,
    });
    goBackOrHome();
  };

  return (
    <>
      <View style={{ backgroundColor: theme.colors.background }}>
        <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
          <Appbar.BackAction onPress={goBackOrHome} />
          <Appbar.Content title="New account" titleStyle={s.appbarTitle} />
          <Appbar.Action icon="check" accessibilityLabel="Save account" onPress={save} />
        </Appbar.Header>
      </View>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={s.keyboardArea}
      >
        <ScrollView
          style={{ backgroundColor: theme.colors.background }}
          contentContainerStyle={s.container}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
        >
          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>Name</Text>
          <PremiumTextInput value={name} onChangeText={setName} placeholder="HDFC savings" />
          <HelperText type="error" visible={submitted && !name.trim()}>
            Enter an account name.
          </HelperText>

          <OptionSelectorRow
            label="Type"
            value={optionLabel(ACCOUNT_TYPE_OPTIONS, type)}
            description="Account behavior and reporting group"
            icon={typeVisual.icon}
            iconBackgroundColor={typeVisual.backgroundColor}
            iconColor={typeVisual.iconColor}
            onPress={() => setPicker('type')}
          />

          <OptionSelectorRow
            label="Icon"
            value={optionLabel(ACCOUNT_ICON_OPTIONS, icon)}
            description="Shown in account lists and widgets"
            icon={iconVisual.icon}
            iconBackgroundColor={iconVisual.backgroundColor}
            iconColor={iconVisual.iconColor}
            onPress={() => setPicker('icon')}
          />

          <OptionSelectorRow
            label="Color"
            value="Selected color"
            description="Icon accent"
            icon={iconVisual.icon}
            iconBackgroundColor={iconVisual.backgroundColor}
            iconColor={iconVisual.iconColor}
            onPress={() => setPicker('color')}
          />

          <OptionSelectorRow
            label="Currency"
            value={optionLabel(currencyOptions, currency)}
            description="Money unit for this account"
            icon={currencyOptionIcon(currency)}
            onPress={() => setPicker('currency')}
          />

          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>
            {isBorrowedLoan ? 'Outstanding principal' : 'Opening balance'}
          </Text>
          <PremiumTextInput value={opening} onChangeText={setOpening} keyboardType="numeric" />
          {isBorrowedLoan ? (
            <Text style={[s.helper, { color: theme.colors.onSurfaceVariant }]}>
              Enter the amount left to repay as a positive number; 1wallet tracks it as a liability.
            </Text>
          ) : null}

          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>
            Card or account last 4
          </Text>
          <PremiumTextInput
            value={lastFour}
            onChangeText={setLastFour}
            keyboardType="number-pad"
            placeholder="1234"
          />
          <Text style={[s.helper, { color: theme.colors.onSurfaceVariant }]}>
            Used to route SMS, email, and notification captures when a message mentions this ending.
          </Text>

          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>
            Institution (optional)
          </Text>
          <PremiumTextInput value={institution} onChangeText={setInstitution} />

          <View style={s.switchRow}>
            <Text style={[s.switchLabel, { color: theme.colors.onSurface }]}>
              Include in totals
            </Text>
            <Switch value={includeInTotals} onValueChange={setIncludeInTotals} />
          </View>
          <View style={s.switchRow}>
            <Text style={[s.switchLabel, { color: theme.colors.onSurface }]}>
              Include in budgets
            </Text>
            <Switch value={includeInBudgets} onValueChange={setIncludeInBudgets} />
          </View>
          <View style={s.switchRow}>
            <Text style={[s.switchLabel, { color: theme.colors.onSurface }]}>
              Include in net worth
            </Text>
            <Switch value={includeInNetWorth} onValueChange={setIncludeInNetWorth} />
          </View>

          <Pressable style={[s.save, { backgroundColor: theme.colors.primary }]} onPress={save}>
            <Text style={[s.saveText, { color: theme.colors.onPrimary }]}>Save account</Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
      <OptionListOverlay
        visible={picker === 'type'}
        title="Account type"
        options={ACCOUNT_TYPE_OPTIONS}
        selectedValue={type}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setIcon((currentIcon) =>
            currentIcon === accountIconForType(type)
              ? accountIconForType(option.value)
              : currentIcon,
          );
          setType(option.value);
          if (option.value === 'loan' || option.value === 'overdraft' || option.value === 'lent') {
            setIncludeInBudgets(false);
            setIncludeInTotals(true);
            setIncludeInNetWorth(true);
          }
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'icon'}
        title="Account icon"
        options={ACCOUNT_ICON_OPTIONS}
        selectedValue={icon}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setIcon(option.value);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'currency'}
        title="Currency"
        options={currencyOptions}
        selectedValue={currency}
        searchPlaceholder="Search currencies"
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setCurrency(option.value);
          setPicker(null);
        }}
      />
      <ColorPickerOverlay
        visible={picker === 'color'}
        title="Account color"
        selectedColor={color}
        fallbackColor={DEFAULT_ACCOUNT_COLOR}
        swatches={ACCOUNT_COLOR_OPTIONS}
        saveLabel="Apply account color"
        accessibilityLabelPrefix="Account color"
        onDismiss={() => setPicker(null)}
        onSave={(nextColor) => {
          setColor(nextColor);
          setPicker(null);
        }}
        renderPreview={(nextColor) => (
          <ColorPickerIconPreview
            color={nextColor}
            icon={icon}
            title={name.trim() || 'New account'}
            subtitle={optionLabel(ACCOUNT_TYPE_OPTIONS, type)}
          />
        )}
      />
    </>
  );
}

function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
) {
  return options.find((option) => option.value === value)?.label ?? value;
}

const s = StyleSheet.create({
  appbarTitle: { fontWeight: '700' },
  keyboardArea: { flex: 1 },
  container: { padding: tokens.space.lg, gap: tokens.space.md, paddingBottom: 112 },
  label: {
    fontFamily: tokens.font.nativeFamily.medium,
    fontSize: tokens.font.size.sm,
    marginTop: tokens.space.sm,
    fontWeight: '600',
  },
  input: {
    fontFamily: tokens.font.nativeFamily.regular,
    borderWidth: 1,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
    fontSize: tokens.font.size.md,
  },
  switchRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: tokens.space.sm,
  },
  switchLabel: { fontFamily: tokens.font.nativeFamily.regular, fontSize: tokens.font.size.md },
  helper: {
    fontFamily: tokens.font.nativeFamily.regular,
    fontSize: tokens.font.size.sm,
    marginTop: -tokens.space.xs,
  },
  save: {
    marginTop: tokens.space.lg,
    padding: tokens.space.lg,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
  },
  saveText: {
    fontFamily: tokens.font.nativeFamily.medium,
    fontSize: tokens.font.size.lg,
    fontWeight: '700',
  },
});
