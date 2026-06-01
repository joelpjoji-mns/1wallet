import { tokens } from '@1wallet/ui';

export const appFontAssets = {
  [tokens.font.nativeFamily.regular]: require('../assets/fonts/Inter-Regular.ttf'),
  [tokens.font.nativeFamily.medium]: require('../assets/fonts/Inter-Medium.ttf'),
  [tokens.font.nativeFamily.semibold]: require('../assets/fonts/Inter-SemiBold.ttf'),
  [tokens.font.nativeFamily.bold]: require('../assets/fonts/Inter-Bold.ttf'),
  [tokens.font.nativeFamily.numeric]: require('../assets/fonts/RobotoMono-Regular.ttf'),
  [tokens.font.nativeFamily.numericMedium]: require('../assets/fonts/RobotoMono-Medium.ttf'),
} as const;

export const appFonts = tokens.font.nativeFamily;
export const numericFontFamily = appFonts.numeric;
export const numericMediumFontFamily = appFonts.numericMedium;
