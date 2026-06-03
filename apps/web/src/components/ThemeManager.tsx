'use client';

import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useEffect } from 'react';
import { mixHexColors, readableTextColorForBackground, withColorAlpha } from '../lib/colorContrast';

function normalizeHexColor(value: string | undefined): string | undefined {
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

export function ThemeManager() {
  const { state } = useLedger();
  const theme = state?.preferences?.theme || 'system';
  const customAccent = normalizeHexColor(state?.preferences?.themeAccent?.customColor);
  const useAccent = state?.preferences?.themeAccent?.source === 'custom' && !!customAccent;

  useEffect(() => {
    const isDark =
      theme === 'dark' ||
      theme === 'amoled' ||
      (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    
    let palette = { ...(isDark ? tokens.color.md3.dark : tokens.color.md3.light) };

    if (theme === 'amoled') {
      palette.background = '#000000';
      palette.surfaceContainerLowest = '#000000';
      palette.surfaceContainerLow = '#050505';
      palette.surfaceContainer = '#090909';
      palette.surfaceContainerHigh = '#101010';
      palette.surfaceContainerHighest = '#171717';
      palette.outlineVariant = '#303236';
    }

    if (useAccent && customAccent) {
      palette.primary = customAccent;
      palette.onPrimary = readableTextColorForBackground(customAccent);
      palette.primaryContainer = mixHexColors(
        customAccent,
        isDark ? palette.surfaceContainerHigh : palette.surfaceContainerLowest,
        isDark ? 0.34 : 0.16,
      );
      palette.onPrimaryContainer = readableTextColorForBackground(palette.primaryContainer);
      
      const outlineBase = readableTextColorForBackground(palette.background);
      palette.outline = withColorAlpha(outlineBase, isDark ? 0.62 : 0.46);
      palette.outlineVariant = withColorAlpha(outlineBase, isDark ? 0.34 : 0.22);
    }
    
    const root = document.documentElement;
    
    root.style.setProperty('--color-primary', palette.primary);
    root.style.setProperty('--color-on-primary', palette.onPrimary);
    root.style.setProperty('--color-bg', palette.background);
    root.style.setProperty('--color-on-bg', palette.onBackground);
    root.style.setProperty('--color-surface', palette.surfaceContainerLowest);
    root.style.setProperty('--color-surface-low', palette.surfaceContainerLow);
    root.style.setProperty('--color-surface-high', palette.surfaceContainerHigh);
    root.style.setProperty('--color-on-surface', palette.onSurface);
    root.style.setProperty('--color-outline', palette.outline);
    root.style.setProperty('--color-outline-variant', palette.outlineVariant);
    root.style.setProperty('--color-error', palette.error);
    root.style.setProperty('--color-on-error', palette.onError);
    
    root.style.setProperty('--color-positive', tokens.color.finance.positive);
    root.style.setProperty('--color-warning', tokens.color.finance.warning);
    root.style.setProperty('--color-danger', tokens.color.finance.danger);
    root.style.setProperty('--color-transfer', tokens.color.finance.transfer);

  }, [theme, customAccent, useAccent]);

  return null;
}
