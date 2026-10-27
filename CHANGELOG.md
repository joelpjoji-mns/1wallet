# Changelog

All notable changes to **1Wallet** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Offline-only mode ("Use without an account"):
  - Run 1Wallet entirely on the device with no Google sign-in, Firebase account, or cloud sync.
  - Includes an explicit consent sheet, offline status in Settings and Sync, and encrypted backup export/import shortcuts.
- "Back up & sync with Google" upgrade for offline wallets:
  - Moves the wallet to a Google account with no data loss.
  - If the account already has a cloud wallet, the user explicitly chooses to keep this device's wallet, use the cloud wallet, or merge both.

### Fixed
- Importing a backup created by another account now re-owns it to the importing offline wallet instead of keeping the foreign account id.
- Background SMS/notification polling now follows the active device wallet owner.

## [2.1.0] - 2026-10-26

### Added
- Comprehensive hierarchical `AGENTS.md` and architectural playbooks across all repository directories.
- Three workspace AI skills in `.agents/skills/`: `1wallet-architecture`, `1wallet-state-and-sync`, and `1wallet-test-runner`.
- Granular domain rules in `.agents/rules/` for financial math, Riverpod state, and offline synchronization.
- Architectural Decision Records (`doc/adr/`) documenting integer minor units, offline sync, and encryption.
- GitHub issue templates for bug reporting and feature requests.
- Centered empty-state components with contextual action icons across accounts, search, and transactions.

### Changed
- Improved `AppTopFadeMask` passthrough layout behavior during list scrolling.
- Hardened Firestore security rules with comprehensive emulator test coverage.

### Fixed
- Fixed empty search view clipping on narrow mobile screens.
- Prevented potential divide-by-zero errors in credit card utilization calculations when credit limit is zero.

---

## [2.0.0] - 2026-09-20

### Added
- Complete Flutter 3.x cross-platform rewrite with Material 3 styling and liquid glass widgets.
- Companion Progressive Web App (React 19 + TypeScript + Vite) in `pwa/`.
- Offline-first Cloud Firestore snapshot synchronization engine with `CloudSyncWriteGuard`.
- On-device Google ML Kit text recognition for camera and gallery receipt capture.
- Android SMS and banking notification spooler with comprehensive regex extraction engine.
- Multi-currency portfolio consolidation with historical and real-time exchange rate caching.
- Biometric hardware app lock (`local_auth`) and AES-256-GCM local encrypted backups.
