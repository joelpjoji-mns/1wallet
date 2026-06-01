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
import { goBackOrHome, PremiumTextInput } from '../../src/components/AppKit';

export default function NewGoal() {
  const theme = useTheme();
  const { state, mutate } = useLedger();
  const [name, setName] = useState('');
  const [target, setTarget] = useState('');
  const [targetDate, setTargetDate] = useState('');

  const save = async () => {
    const n = Number(target.replace(/,/g, ''));
    if (!name.trim()) return Alert.alert('Enter a name');
    if (!n || n <= 0) return Alert.alert('Enter a target amount');
    const base = state.preferences.baseCurrency;
    await mutate((s) => {
      s.goals.push({
        id: uid(),
        userId: s.userId,
        name: name.trim(),
        kind: 'save_up',
        targetAmount: { amountMinor: toMinor(n, base), currency: base },
        targetDate: targetDate || undefined,
        priority: 'medium',
        isPaused: false,
        isCompleted: false,
      });
    });
    goBackOrHome();
  };

  return (
    <>
      <View style={{ backgroundColor: theme.colors.background }}>
        <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
          <Appbar.BackAction onPress={goBackOrHome} />
          <Appbar.Content title="New goal" titleStyle={s.appbarTitle} />
          <Appbar.Action icon="check" accessibilityLabel="Save goal" onPress={() => void save()} />
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
          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>Goal name</Text>
          <PremiumTextInput value={name} onChangeText={setName} placeholder="Emergency fund" />

          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>
            Target amount ({state.preferences.baseCurrency})
          </Text>
          <PremiumTextInput
            value={target}
            onChangeText={setTarget}
            keyboardType="numeric"
            placeholder="0"
          />

          <Text style={[s.label, { color: theme.colors.onSurfaceVariant }]}>
            Target date (YYYY-MM-DD, optional)
          </Text>
          <PremiumTextInput
            value={targetDate}
            onChangeText={setTargetDate}
            placeholder="2026-12-31"
            autoCapitalize="none"
          />

          <Pressable style={[s.save, { backgroundColor: theme.colors.primary }]} onPress={save}>
            <Text style={[s.saveText, { color: theme.colors.onPrimary }]}>Save goal</Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
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
    fontFamily: tokens.font.nativeFamily.regular,
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
