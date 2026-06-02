import type { ThemePreference } from '@1wallet/ledger';
import * as FileSystem from 'expo-file-system/legacy';

const THEME_PREFERENCE_FILE = `${FileSystem.documentDirectory ?? FileSystem.cacheDirectory}1wallet-theme-preference.json`;

type CachedThemePreference = {
  theme?: ThemePreference;
};

export async function loadCachedThemePreference(): Promise<ThemePreference | undefined> {
  if (!THEME_PREFERENCE_FILE.startsWith('file://')) return undefined;
  const info = await FileSystem.getInfoAsync(THEME_PREFERENCE_FILE).catch(() => null);
  if (!info?.exists) return undefined;

  try {
    const parsed = JSON.parse(
      await FileSystem.readAsStringAsync(THEME_PREFERENCE_FILE),
    ) as Partial<CachedThemePreference>;
    return normalizeThemePreference(parsed.theme);
  } catch {
    return undefined;
  }
}

export async function saveCachedThemePreference(theme: ThemePreference | undefined): Promise<void> {
  if (!THEME_PREFERENCE_FILE.startsWith('file://')) return;
  const normalized = normalizeThemePreference(theme) ?? 'system';
  await FileSystem.writeAsStringAsync(
    THEME_PREFERENCE_FILE,
    JSON.stringify({ theme: normalized } satisfies CachedThemePreference),
  );
}

function normalizeThemePreference(value: unknown): ThemePreference | undefined {
  if (value === 'system' || value === 'light' || value === 'dark' || value === 'amoled') {
    return value;
  }
  return undefined;
}
