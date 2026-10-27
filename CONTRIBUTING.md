# Contributing to 1Wallet

Thank you for your interest in contributing to **1Wallet**! We welcome bug fixes, documentation improvements, UI enhancements, and feature suggestions.

---

## 🛠️ Development Setup & Prerequisites

Ensure you have the following installed on your machine:
- **Flutter SDK**: `>= 3.12.0` (Dart SDK `>= 3.12.0`)
- **Node.js**: `>= 20.x` (for PWA, CI scripts, and Firebase emulator tests)
- **Git**

### Clone & Bootstrap
```bash
# Clone the repository
git clone https://github.com/joelpjoji-mns/1wallet.git
cd 1wallet

# Install Flutter dependencies
flutter pub get

# Install PWA dependencies
cd pwa && npm install && cd ..

# Setup local environment template
cp .env.example .env.local
```

---

## 🧪 Testing & Quality Assurance

Before submitting any Pull Request, you must verify that all automated test suites pass cleanly:

```bash
# 1. Run Flutter unit and widget tests
flutter test

# 2. Run Flutter static analyzer
flutter analyze

# Validate dynamic notification resources in the actual shrunk release APK.
node --test scripts/validate-android-notification-resources.test.mjs
flutter build apk --release --target-platform android-arm64 --split-per-abi
node scripts/validate-android-notification-resources.mjs --apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# 3. Run PWA tests and linting
cd pwa
npm test
npm run lint
cd ..

# 4. Run Firebase security rules tests (if modified)
cd firebase
npm test
cd ..
```

Notification icons are resolved by name through a platform channel. Keep them in
the Android raw resource keep file; source existence or a debug build is not
sufficient evidence that resource shrinking preserves them. PR validation and
the signed release workflow validate the packaged APK before publishing it.
Use bare drawable names for the notification plugin, not XML `@drawable/...`
syntax, and use an actual bitmap drawable rather than an adaptive launcher XML
for the large icon. Native tests exercise both name lookup and bitmap decoding.
A notification-delivery failure must also leave a discovered update available
to download, with a non-blocking warning instead of an update-check error.

---

## 📐 Coding Conventions & Invariants

All contributors must respect these core engineering invariants:
1. **Financial Minor Units**: Never use floating point (`double`) for currency balances. Always use integer minor units (`amountMinor` in `Money`).
2. **Immutable State**: Never mutate `LedgerState` objects directly. All mutations must occur via `LedgerController` copy methods.
3. **Accessibility**: All interactive buttons, icon buttons, and navigation controls must provide descriptive `Semantics` labels or tooltips.
4. **Documentation**: When adding new features or modifying subdirectories, update the corresponding `AGENTS.md` and tests.

---

## 🔀 Git Branching & Pull Requests

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-description
   ```
2. Commit with concise, descriptive commit messages conforming to Conventional Commits:
   - `feat: add recurring expense monthly interval option`
   - `fix: prevent divide by zero in loan amortization calculator`
   - `docs: update accounts AGENTS.md guide`
3. Push to your fork and submit a Pull Request targeting `main`. Fill in the PR description template with testing steps and verification evidence.
