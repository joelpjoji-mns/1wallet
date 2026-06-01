import { toMinor } from '@1wallet/domain/money';
import { uid } from '@1wallet/ledger/id';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useState } from 'react';
import {
    Alert,
    KeyboardAvoidingView,
    Platform,
    Pressable,
    ScrollView,
    StyleSheet,
    Text,
    View,
} from 'react-native';
import { Appbar, useTheme } from 'react-native-paper';
import { resolveCategoryIcon, resolveCategoryIconVisual } from '../../src/categoryIcons';
import { categoryBreadcrumb } from '../../src/categoryTree';
import { goBackOrHome, PremiumTextInput } from '../../src/components/AppKit';
import { OptionSelectorRow } from '../../src/components/OptionListOverlay';
import { CategoryPickerOverlay as RecordCategoryPickerOverlay } from '../../src/components/record/RecordPickers';

export default function NewBudget() {
  const theme = useTheme();
  const { state, mutate } = useLedger();
  const expenseCats = state.categories.filter((c) => c.kind === 'expense' && !c.isArchived);
  const [categoryId, setCategoryId] = useState<string | undefined>(expenseCats[0]?.id);
  const [categoryPickerVisible, setCategoryPickerVisible] = useState(false);
  const [amount, setAmount] = useState('');
  const selectedCategory = expenseCats.find((c) => c.id === categoryId);
  const selectedCategoryVisual = selectedCategory
    ? resolveCategoryIconVisual(selectedCategory, state.categories)
    : undefined;

  const save = async () => {
    const cat = expenseCats.find((c) => c.id === categoryId);
    if (!cat) return Alert.alert('Pick a category');
    const n = Number(amount.replace(/,/g, ''));
    if (!n || n <= 0) return Alert.alert('Enter an amount');
    const baseCurrency = state.preferences.baseCurrency;
    await mutate((s) => {
      s.budgets.push({
        id: uid(),
        userId: s.userId,
        name: cat.name,
        period: 'monthly',
        startsOn: new Date().toISOString().slice(0, 10),
        amount: { amountMinor: toMinor(n, baseCurrency), currency: baseCurrency },
        rolloverUnused: false,
        carryOverspend: false,
        isPaused: false,
        alertThresholds: [50, 80, 100],
      });
    });
    goBackOrHome();
  };

  return (
    <>
      <View style={{ backgroundColor: theme.colors.background }}>
        <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
          <Appbar.BackAction onPress={goBackOrHome} />
          <Appbar.Content title="New budget" titleStyle={s.appbarTitle} />
          <Appbar.Action
            icon="check"
            accessibilityLabel="Save budget"
            onPress={() => void save()}
          />
        </Appbar.Header>
      </View>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={s.keyboardArea}
      >
        <ScrollView
          style={{ backgroundColor: theme.colors.background }}
          contentContainerStyle={s.content}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
        >
          <OptionSelectorRow
            label="Category"
            value={selectedCategory?.name ?? 'Choose category'}
            description={
              categoryId ? categoryBreadcrumb(state.categories, categoryId) : 'Budget category'
            }
            icon={resolveCategoryIcon(selectedCategory, state.categories)}
            iconBackgroundColor={selectedCategoryVisual?.backgroundColor}
            iconColor={selectedCategoryVisual?.iconColor}
            onPress={() => setCategoryPickerVisible(true)}
          />

          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>
            Monthly limit ({state.preferences.baseCurrency})
          </Text>
          <PremiumTextInput
            value={amount}
            onChangeText={setAmount}
            keyboardType="numeric"
            placeholder="0"
          />

          <Pressable style={[s.save, { backgroundColor: theme.colors.primary }]} onPress={save}>
            <Text style={[s.saveText, { color: theme.colors.onPrimary }]}>Save budget</Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
      <RecordCategoryPickerOverlay
        visible={categoryPickerVisible}
        kind="expense"
        categories={state.categories}
        selectedId={categoryId}
        onDismiss={() => setCategoryPickerVisible(false)}
        onClear={() => {
          setCategoryId(undefined);
          setCategoryPickerVisible(false);
        }}
        onSelect={(category) => {
          setCategoryId(category.id);
          setCategoryPickerVisible(false);
        }}
      />
    </>
  );
}

const s = StyleSheet.create({
  appbarTitle: { fontWeight: '700' },
  keyboardArea: { flex: 1 },
  content: { padding: tokens.space.lg, gap: tokens.space.md, paddingBottom: 112 },
  label: {
    fontFamily: tokens.font.nativeFamily.medium,
    fontSize: tokens.font.size.sm,
    marginTop: tokens.space.sm,
    fontWeight: '600',
  },
  input: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    borderWidth: 1,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
    fontSize: tokens.font.size.lg,
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
