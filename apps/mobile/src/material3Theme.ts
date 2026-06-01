import type {
    Material3Scheme,
    Material3Theme,
    SystemScheme,
} from '@pchmn/expo-material3-theme/build/ExpoMaterial3Theme.types';
import {
    createThemeFromSourceColor,
    createThemeFromSystemSchemes,
    type Material3ThemeOptions,
} from '@pchmn/expo-material3-theme/build/utils/createMaterial3Theme';
import { useMemo } from 'react';
import { Platform, TurboModuleRegistry } from 'react-native';

export type { Material3Scheme, Material3Theme, Material3ThemeOptions };

type ExpoGlobal = typeof globalThis & {
  expo?: {
    modules?: Record<string, unknown>;
  };
};

type ExpoModulesCore = {
  installModules?: () => void;
};

type ExpoMaterial3ThemeModule = {
  getSystemTheme?: () => { light: SystemScheme; dark: SystemScheme } | null;
};

export const isDynamicThemeSupported = Platform.OS === 'android' && Number(Platform.Version) >= 31;

export function createMaterial3Theme(
  sourceColor: string,
  options?: Material3ThemeOptions,
): Material3Theme {
  return createThemeFromSourceColor(sourceColor, options);
}

export function getMaterial3Theme(
  fallbackSourceColor = '#6750A4',
  options?: Material3ThemeOptions,
): Material3Theme {
  if (isDynamicThemeSupported) {
    const systemSchemes = getNativeMaterial3ThemeModule()?.getSystemTheme?.();

    if (systemSchemes) {
      return createThemeFromSystemSchemes(systemSchemes);
    }
  }

  return createThemeFromSourceColor(fallbackSourceColor, options);
}

export function useMaterial3Theme(
  options?: Material3ThemeOptions & { fallbackSourceColor?: string; sourceColor?: string },
) {
  const fallbackSourceColor = options?.fallbackSourceColor ?? '#6750A4';
  const sourceColor = options?.sourceColor;
  const colorFidelity = options?.colorFidelity;
  const theme = useMemo(() => {
    const themeOptions = { colorFidelity } satisfies Material3ThemeOptions;
    return sourceColor
      ? createThemeFromSourceColor(sourceColor, themeOptions)
      : getMaterial3Theme(fallbackSourceColor, themeOptions);
  }, [colorFidelity, fallbackSourceColor, sourceColor]);

  return { theme };
}

function getNativeMaterial3ThemeModule(): ExpoMaterial3ThemeModule | null {
  const expoGlobal = globalThis as ExpoGlobal;
  ensureExpoModulesInstalled(expoGlobal);

  const nativeModule = expoGlobal.expo?.modules?.ExpoMaterial3Theme;
  return nativeModule ? (nativeModule as ExpoMaterial3ThemeModule) : null;
}

function ensureExpoModulesInstalled(expoGlobal: ExpoGlobal) {
  if (expoGlobal.expo || Platform.OS === 'web') {
    return;
  }

  try {
    (TurboModuleRegistry.get('ExpoModulesCore') as ExpoModulesCore | null)?.installModules?.();
  } catch {
    // The caller will use the generated fallback palette when the native module is unavailable.
  }
}
