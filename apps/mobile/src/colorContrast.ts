export function readableTextColorForBackground(color?: string | null): string {
  if (!color) return '#FFFFFF';
  const normalized = color.trim().replace('#', '');
  const hex =
    normalized.length === 3
      ? normalized
          .split('')
          .map((part) => `${part}${part}`)
          .join('')
      : normalized;
  if (!/^[0-9a-fA-F]{6}$/.test(hex)) return '#FFFFFF';
  const red = parseInt(hex.slice(0, 2), 16) / 255;
  const green = parseInt(hex.slice(2, 4), 16) / 255;
  const blue = parseInt(hex.slice(4, 6), 16) / 255;
  const luminance =
    0.2126 * linearizedColor(red) +
    0.7152 * linearizedColor(green) +
    0.0722 * linearizedColor(blue);
  return luminance > 0.56 ? '#1B1B1F' : '#FFFFFF';
}

function linearizedColor(value: number): number {
  return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}
