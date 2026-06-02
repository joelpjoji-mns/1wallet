import type { ThemeAccentPreference, ThemePreference } from '@1wallet/ledger';
import { tokens } from '@1wallet/ui';
import { configureFonts, MD3DarkTheme, MD3LightTheme, type MD3Theme } from 'react-native-paper';
import { withColorAlpha } from './colorAlpha';
import { mixHexColors, readableTextColorForBackground } from './colorContrast';
import { appFonts } from './fonts';
import type { Material3Scheme } from './material3Theme';

type ColorScheme = Pick<
  Material3Scheme,
  | 'primary'
  | 'onPrimary'
  | 'primaryContainer'
  | 'onPrimaryContainer'
  | 'secondary'
  | 'onSecondary'
  | 'secondaryContainer'
  | 'onSecondaryContainer'
  | 'tertiary'
  | 'onTertiary'
  | 'tertiaryContainer'
  | 'onTertiaryContainer'
  | 'error'
  | 'onError'
  | 'errorContainer'
  | 'onErrorContainer'
  | 'background'
  | 'onBackground'
  | 'surface'
  | 'onSurface'
  | 'surfaceVariant'
  | 'onSurfaceVariant'
  | 'outline'
  | 'outlineVariant'
  | 'inverseSurface'
  | 'inverseOnSurface'
  | 'inversePrimary'
  | 'shadow'
  | 'scrim'
  | 'surfaceDim'
  | 'surfaceBright'
  | 'surfaceContainerLowest'
  | 'surfaceContainerLow'
  | 'surfaceContainer'
  | 'surfaceContainerHigh'
  | 'surfaceContainerHighest'
>;

type AppMaterialTheme = {
  light: ColorScheme;
  dark: ColorScheme;
};

type AppPaperThemeOptions = {
  customAccentColor?: string;
};

export type ResolvedThemeMode = 'light' | 'dark' | 'amoled';

export const DEFAULT_THEME_SOURCE_COLOR = tokens.color.md3.light.primary;
export const DEFAULT_CUSTOM_ACCENT_COLOR = tokens.color.md3.light.primary;

const paperFonts = configureFonts({
  config: {
    displayLarge: { fontFamily: appFonts.semibold, fontWeight: '600' },
    displayMedium: { fontFamily: appFonts.semibold, fontWeight: '600' },
    displaySmall: { fontFamily: appFonts.medium, fontWeight: '500' },
    headlineLarge: { fontFamily: appFonts.semibold, fontWeight: '600' },
    headlineMedium: { fontFamily: appFonts.medium, fontWeight: '500' },
    headlineSmall: { fontFamily: appFonts.medium, fontWeight: '500' },
    titleLarge: { fontFamily: appFonts.semibold, fontWeight: '600' },
    titleMedium: { fontFamily: appFonts.semibold, fontWeight: '600' },
    titleSmall: { fontFamily: appFonts.semibold, fontWeight: '600' },
    labelLarge: { fontFamily: appFonts.semibold, fontWeight: '600' },
    labelMedium: { fontFamily: appFonts.semibold, fontWeight: '600' },
    labelSmall: { fontFamily: appFonts.medium, fontWeight: '500' },
    bodyLarge: { fontFamily: appFonts.regular, fontWeight: '400' },
    bodyMedium: { fontFamily: appFonts.regular, fontWeight: '400' },
    bodySmall: { fontFamily: appFonts.regular, fontWeight: '400' },
  },
});

function createPaperTheme(
  base: MD3Theme,
  scheme: ColorScheme,
  amoled = false,
  options?: AppPaperThemeOptions,
): MD3Theme {
  const baseScheme = amoled ? amoledScheme(scheme) : scheme;
  const appScheme = applyReadableThemeColors(baseScheme, base.dark || amoled, options);
  return {
    ...base,
    dark: base.dark || amoled,
    fonts: paperFonts,
    roundness: tokens.radius.sm,
    colors: {
      ...base.colors,
      primary: appScheme.primary,
      onPrimary: appScheme.onPrimary,
      primaryContainer: appScheme.primaryContainer,
      onPrimaryContainer: appScheme.onPrimaryContainer,
      secondary: appScheme.secondary,
      onSecondary: appScheme.onSecondary,
      secondaryContainer: appScheme.secondaryContainer,
      onSecondaryContainer: appScheme.onSecondaryContainer,
      tertiary: appScheme.tertiary,
      onTertiary: appScheme.onTertiary,
      tertiaryContainer: appScheme.tertiaryContainer,
      onTertiaryContainer: appScheme.onTertiaryContainer,
      error: appScheme.error,
      onError: appScheme.onError,
      errorContainer: appScheme.errorContainer,
      onErrorContainer: appScheme.onErrorContainer,
      background: appScheme.background,
      onBackground: appScheme.onBackground,
      surface: appScheme.surfaceContainerLow,
      onSurface: appScheme.onSurface,
      surfaceVariant: appScheme.surfaceContainerHighest,
      onSurfaceVariant: appScheme.onSurfaceVariant,
      surfaceDisabled: appScheme.surfaceContainer,
      onSurfaceDisabled: appScheme.onSurfaceVariant,
      outline: appScheme.outline,
      outlineVariant: appScheme.outlineVariant,
      inverseSurface: appScheme.inverseSurface,
      inverseOnSurface: appScheme.inverseOnSurface,
      inversePrimary: appScheme.inversePrimary,
      shadow: appScheme.shadow,
      scrim: appScheme.scrim,
      backdrop: 'rgba(0,0,0,0.52)',
      elevation: {
        level0: 'transparent',
        level1: appScheme.surfaceContainerLow,
        level2: appScheme.surfaceContainer,
        level3: appScheme.surfaceContainerHigh,
        level4: appScheme.surfaceContainerHighest,
        level5: appScheme.surfaceBright,
      },
    },
  };
}

function amoledScheme(scheme: ColorScheme): ColorScheme {
  return {
    ...scheme,
    background: '#000000',
    surface: '#000000',
    surfaceDim: '#000000',
    surfaceContainerLowest: '#000000',
    surfaceContainerLow: '#050505',
    surfaceContainer: '#090909',
    surfaceContainerHigh: '#101010',
    surfaceContainerHighest: '#171717',
    surfaceBright: '#202020',
    surfaceVariant: '#202124',
    outlineVariant: '#303236',
  };
}

function applyReadableThemeColors(
  scheme: ColorScheme,
  dark: boolean,
  options?: AppPaperThemeOptions,
): ColorScheme {
  const customAccent = normalizeHexColor(options?.customAccentColor);
  const primary = customAccent ?? scheme.primary;
  const primaryContainer = customAccent
    ? mixHexColors(
        primary,
        dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
        dark ? 0.34 : 0.16,
      )
    : scheme.primaryContainer;
  const outlineBase = readableTextColorForBackground(scheme.background);

  return {
    ...scheme,
    primary,
    onPrimary: readableTextColorForBackground(primary),
    primaryContainer,
    onPrimaryContainer: readableTextColorForBackground(primaryContainer),
    inversePrimary: customAccent ?? scheme.inversePrimary,
    outline: withColorAlpha(outlineBase, dark ? 0.62 : 0.46),
    outlineVariant: withColorAlpha(outlineBase, dark ? 0.34 : 0.22),
  };
}

export function createAppPaperTheme(
  mode: ResolvedThemeMode,
  materialTheme: AppMaterialTheme = fallbackMaterialTheme,
  options?: AppPaperThemeOptions,
): MD3Theme {
  if (mode === 'light') return createPaperTheme(MD3LightTheme, materialTheme.light, false, options);
  if (mode === 'amoled') return createPaperTheme(MD3DarkTheme, materialTheme.dark, true, options);
  return createPaperTheme(MD3DarkTheme, materialTheme.dark, false, options);
}

const fallbackMaterialTheme = {
  light: tokens.color.md3.light,
  dark: tokens.color.md3.dark,
} satisfies AppMaterialTheme;

export const paperThemes = {
  light: createAppPaperTheme('light', fallbackMaterialTheme),
  dark: createAppPaperTheme('dark', fallbackMaterialTheme),
  amoled: createAppPaperTheme('amoled', fallbackMaterialTheme),
} as const;

export function resolveThemeMode(
  preference: ThemePreference | undefined,
  systemScheme: 'light' | 'dark' | null | undefined,
): ResolvedThemeMode {
  if (preference === 'light' || preference === 'dark' || preference === 'amoled') return preference;
  return systemScheme === 'light' ? 'light' : 'dark';
}

export function normalizeThemeAccentPreference(
  preference: ThemeAccentPreference | undefined,
): Required<Pick<ThemeAccentPreference, 'source'>> & Pick<ThemeAccentPreference, 'customColor'> {
  if (preference?.source === 'custom') {
    return {
      source: 'custom',
      customColor: normalizeHexColor(preference.customColor) ?? DEFAULT_CUSTOM_ACCENT_COLOR,
    };
  }
  return { source: 'system' };
}

export function normalizeHexColor(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const hex = value.trim().replace(/^#/, '');
  if (/^[0-9a-fA-F]{6}$/.test(hex)) return `#${hex.toUpperCase()}`;
  if (/^[0-9a-fA-F]{3}$/.test(hex)) {
    return `#${hex
      .split('')
      .map((character) => character + character)
      .join('')
      .toUpperCase()}`;
  }
  return undefined;
}

export const paperTheme = paperThemes.dark;

export type AppTheme = typeof paperTheme;
