import { router } from 'expo-router';
import { useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Button, HelperText, Text, useTheme } from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useAuth } from '../src/auth';
import { AnimatedBrandScene, BrandedLoadingState } from '../src/components/Brand';

export default function Login() {
  const theme = useTheme();
  const { signInWithGoogle } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const submitGoogle = async () => {
    if (submitting) return;
    setError(null);
    setSubmitting(true);
    try {
      await signInWithGoogle();
      router.replace('/');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not sign in with Google.');
    } finally {
      setSubmitting(false);
    }
  };

  if (submitting) {
    return <BrandedLoadingState stage="session" message="Opening Google sign-in" />;
  }

  return (
    <SafeAreaView
      style={[s.safeArea, { backgroundColor: theme.colors.background }]}
      edges={['top', 'bottom']}
    >
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={s.scrollContent}>
        <View style={s.content}>
          <AnimatedBrandScene
            title="1wallet"
            message="Continue to your money dashboard"
            variant="compact"
          />

          <View style={s.copy}>
            <Text variant="headlineMedium" style={s.title}>
              Sign in
            </Text>
            <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
              Use your Google account to sync and restore your wallet.
            </Text>
          </View>

          <View style={s.form}>
            <HelperText type="error" visible={Boolean(error)}>
              {error}
            </HelperText>
            <Button
              mode="contained"
              icon="google"
              onPress={submitGoogle}
              contentStyle={s.buttonContent}
            >
              Continue with Google
            </Button>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safeArea: { flex: 1 },
  scrollContent: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 20,
  },
  content: {
    width: '100%',
    maxWidth: 440,
    alignSelf: 'center',
    gap: 18,
  },
  copy: { gap: 6 },
  title: { fontWeight: '800' },
  form: { gap: 12 },
  buttonContent: { minHeight: 48 },
});
