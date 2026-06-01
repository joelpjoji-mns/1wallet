export function withColorAlpha(color: string, alpha: number): string {
  const clampedAlpha = Math.max(0, Math.min(1, alpha));
  const value = color.trim();
  if (value.startsWith('#')) {
    const hex = value.slice(1);
    const expanded =
      hex.length === 3 || hex.length === 4
        ? hex
            .slice(0, 3)
            .split('')
            .map((part) => `${part}${part}`)
            .join('')
        : hex.slice(0, 6);
    if (expanded.length !== 6) return color;
    const numeric = Number.parseInt(expanded, 16);
    if (Number.isNaN(numeric)) return color;
    const red = (numeric >> 16) & 255;
    const green = (numeric >> 8) & 255;
    const blue = numeric & 255;
    return `rgba(${red}, ${green}, ${blue}, ${clampedAlpha})`;
  }

  const rgbMatch = value.match(/^rgba?\(([^)]+)\)$/i);
  const rgbParts = rgbMatch?.[1];
  if (!rgbParts) return color;
  const parts = rgbParts.split(',').map((part) => part.trim());
  if (parts.length < 3) return color;
  return `rgba(${parts[0]}, ${parts[1]}, ${parts[2]}, ${clampedAlpha})`;
}
