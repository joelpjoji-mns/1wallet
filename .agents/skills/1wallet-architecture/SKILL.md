---
name: 1wallet-architecture
description: >-
  Architectural guide and mental model for navigating and modifying 1Wallet.
  Use when exploring code, implementing new features, or tracing data flow.
---

# 1Wallet Architecture Skill

This skill guides an AI agent through navigating, designing, and maintaining the 1Wallet Flutter and PWA codebase.

## System Topology

```mermaid
flowchart TD
    UI[Flutter Widgets & Screens] --> Selectors[Ledger Selectors]
    UI --> Router[GoRouter app_router.dart]
    UI --> Riverpod[Riverpod StateNotifierProviders]
    
    subgraph State Layer
        Riverpod --> LedgerCtrl[LedgerController: LedgerState]
        Riverpod --> AuthCtrl[AuthController: AuthState]
        Riverpod --> SyncCtrl[CloudSyncController: CloudSyncState]
        Riverpod --> ThemeCtrl[ThemeController]
    end

    subgraph Data & Persistence
        LedgerCtrl --> LocalStore[LedgerRepository: SharedPreferences / File]
        SyncCtrl --> WriteGuard[CloudSyncWriteGuard]
        WriteGuard --> Firestore[(Firebase Cloud Firestore)]
        LocalStore --> Encryption[AES-256-GCM / PBKDF2]
    end

    subgraph Ingestion Pipeline
        OCR[Receipt OCR: Google ML Kit] --> CapturePipeline[CapturePipeline]
        SMS[SMS / Notifications Spooler] --> CapturePipeline
        CapturePipeline --> ReviewQueue[Review Queue: CaptureCandidate]
        ReviewQueue --> LedgerCtrl
    end
```

## Architectural Guidelines

1. **State Isolation**: UI components never write directly to storage or Firestore. All writes flow through `ledgerProvider.notifier` methods (`addRecord`, `updateRecord`, `deleteRecord`, `addAccount`, etc.).
2. **Derived Data via Selectors**: Calculated values such as account balances, net worth, and spending by category are computed via memoized selectors in `lib/src/ledger/ledger_selectors.dart`.
3. **Double-Entry Representation**: Transfers between two accounts are modeled as a transaction with `accountId` (source) and `counterAccountId` (destination). Both account balances update in an atomic step.
4. **Minor Units for Financial Calculations**: Never use floating point math for currency amounts. All amounts are stored as integer `amountMinor` (1.00 USD = 100 minor units).
