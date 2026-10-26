# `assets/fonts/` — Typography Fonts

## 🎯 Role & Overview
Houses local TrueType font binaries bundled with the app to ensure offline, cross-platform typographic consistency without relying on runtime Google Fonts network downloads.

---

## 📜 Font Families

- **Inter (`Inter-Regular`, `Inter-Medium`, `Inter-SemiBold`, `Inter-Bold`)**:
  - Primary UI typeface for all headings, body text, buttons, and navigation chrome.
- **Roboto & Roboto Mono (`Roboto-Regular`, `Roboto-Medium`, `Roboto-Bold`, `RobotoMono-Regular`, `RobotoMono-Medium`)**:
  - Used for fixed-width tabular numbers, account numbers, and transaction currency amounts.

---

## 🛡️ Critical Invariants & Architecture

1. **Pubspec Registration**:
   - All fonts must be declared under `fonts:` in `pubspec.yaml` matching their respective font families and weights.
2. **Tabular Numerals**:
   - Monetary amount displays must prioritize fonts supporting monospace / tabular digits to prevent layout jitter when numbers change.
