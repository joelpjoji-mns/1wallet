# `pwa/` — 1Wallet Companion Progressive Web App (React + Vite)

## 🎯 Role & Overview
The `pwa/` directory contains a companion lightweight Progressive Web App built with **React 19**, **TypeScript**, **Vite**, and **Firebase**. It provides desktop and mobile browser users with direct, instant access to their financial ledger synced via Cloud Firestore, without requiring a Flutter native binary download.

---

## 🏗️ Architecture & Organization

```
pwa/
├── public/               # Static assets, web manifest, icons
├── src/
│   ├── components/       # Modals (AccountModal, TransactionModal) & shared UI
│   ├── context/          # React contexts: AuthContext, WalletDataContext
│   ├── lib/              # Core business logic: ledger codecs, sync guards, crypto
│   ├── pages/            # Page routes: HomePage, AccountsPage, HistoryPage, CalendarPage, PlannerPage
│   ├── App.tsx           # Router wiring & layout shell
│   └── main.tsx          # DOM root mounting
├── index.html            # Vite HTML host
├── package.json          # Node scripts and dependencies
├── tsconfig.json         # TypeScript configuration
└── vite.config.ts        # Vite build & bundler configuration
```

---

## 🛡️ Critical Invariants & Architecture

1. **Ledger Codec Parity with Flutter**:
   - `pwa/src/lib/ledgerCodec.ts` must maintain strict 1:1 schema compatibility with the Flutter client's `ledger_codec.dart`.
   - Data written by Flutter must be parsed correctly by the PWA, and vice versa.
2. **Sync & Race Guards**:
   - `pendingSaveGuard.ts` and `walletSyncGuards.ts` prevent multi-tab race conditions and inadvertent overwrites of remote cloud data.
3. **Minor Currency Units**:
   - Monetary values in `money.ts` and `ledgerTypes.ts` use integer minor units (`amountMinor`).

---

## 🧪 Testing and Verification

Run the PWA test suite:
```bash
cd pwa
npm test
```
Linting and type checking:
```bash
npm run lint
npm run build
```
