# `assets/` — Application Static Assets

## 🎯 Role & Overview
Houses visual brand assets, application launcher icons, splash backdrop images, and custom typography fonts.

---

## 🗂️ Asset Categories

- **`brand/`**: Application logos, adaptive launcher icons, vector branding (`onewallet-icon.svg`), and native splash graphics.
- **`fonts/`**: Inter and Roboto font families (`Inter-Regular`, `Inter-Medium`, `Inter-Bold`, `RobotoMono-Regular`), declared in `pubspec.yaml`.
- **`images/`**: Provider logos (e.g. `google_logo.png`) and illustration graphics.

---

## 🛡️ Critical Invariants & Architecture

1. **Pubspec Registration**:
   - Any new font or asset directory added here must be declared in `pubspec.yaml` under the `flutter.assets` or `flutter.fonts` section.
2. **Asset Optimization**:
   - Keep PNG images compressed to maintain a lightweight application binary size. Prefer vector SVGs for crisp UI icons where supported.

---

## 🔍 LLM / Developer Checklist

- [ ] Confirm asset paths in code match the exact case-sensitive paths declared in `pubspec.yaml`.
