export function readableTextColorForBackground(color?: string | null): string {
  const blackContrast = contrastRatio('#1B1B1F', color);
  const whiteContrast = contrastRatio('#FFFFFF', color);
  return blackContrast >= whiteContrast ? '#1B1B1F' : '#FFFFFF';
}

export function readableContentColorForBackground(
  backgroundColor?: string | null,
  preferredColor?: string | null,
  minimumContrast = 3,
): string {
  if (preferredColor && contrastRatio(preferredColor, backgroundColor) >= minimumContrast) {
    return preferredColor;
  }
  return readableTextColorForBackground(backgroundColor);
}

export function contrastRatio(
  foregroundColor?: string | null,
  backgroundColor?: string | null,
): number {
  const foregroundLuminance = relativeLuminance(foregroundColor);
  const backgroundLuminance = relativeLuminance(backgroundColor);
  const lighter = Math.max(foregroundLuminance, backgroundLuminance);
  const darker = Math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

export function relativeLuminance(color?: string | null): number {
  const rgb = parseColorToRgb(color);
  if (!rgb) return 0;
  return (
    0.2126 * linearizedColor(rgb.red / 255) +
    0.7152 * linearizedColor(rgb.green / 255) +
    0.0722 * linearizedColor(rgb.blue / 255)
  );
}

export function mixHexColors(
  foregroundColor: string,
  backgroundColor: string,
  foregroundWeight: number,
): string {
  const foreground = parseColorToRgb(foregroundColor);
  const background = parseColorToRgb(backgroundColor);
  if (!foreground || !background) return foregroundColor;

  const weight = Math.max(0, Math.min(1, foregroundWeight));
  return rgbToHex({
    red: foreground.red * weight + background.red * (1 - weight),
    green: foreground.green * weight + background.green * (1 - weight),
    blue: foreground.blue * weight + background.blue * (1 - weight),
  });
}

type RgbColor = { red: number; green: number; blue: number };

function parseColorToRgb(color?: string | null): RgbColor | undefined {
  if (!color) return undefined;
  const value = color.trim();
  const normalizedHex = value.replace(/^#/, '');
  const hex =
    normalizedHex.length === 3
      ? normalizedHex
          .split('')
          .map((part) => `${part}${part}`)
          .join('')
      : normalizedHex;

  if (/^[0-9a-fA-F]{6}$/.test(hex)) {
    return {
      red: parseInt(hex.slice(0, 2), 16),
      green: parseInt(hex.slice(2, 4), 16),
      blue: parseInt(hex.slice(4, 6), 16),
    };
  }

  return undefined;
}

function rgbToHex(color: RgbColor): string {
  return `#${toHexChannel(color.red)}${toHexChannel(color.green)}${toHexChannel(color.blue)}`;
}

function toHexChannel(value: number): string {
  return Math.round(Math.max(0, Math.min(255, value)))
    .toString(16)
    .padStart(2, '0')
    .toUpperCase();
}

function linearizedColor(value: number): number {
  return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}

export function withColorAlpha(hexColor: string, opacity: number): string {
  const rgb = parseColorToRgb(hexColor);
  if (!rgb) return hexColor;
  return `rgba(${rgb.red}, ${rgb.green}, ${rgb.blue}, ${opacity})`;
}
