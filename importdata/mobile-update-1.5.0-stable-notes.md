# 1Wallet Android 1.5.0 (1050000)
## New Features

- Home Cash now shows a converted total with a compact native-currency split derived from existing Cash records.
- Android startup uses the theme-aware loading handoff, native splash resources, and foreground capture service setup for a steadier release launch.
- Review, Accounts, Home widgets, and Add flows include the latest responsiveness and autosave polish.

## Bug Fixes

- Loan detail and edit screens now calculate disbursement-date interest, editable remaining amounts, EMI counts, and payoff dates consistently.
- Ledger save queues, indexed balances, Review lookups, and dashboard widgets were hardened to reduce slow reloads and deadlock-prone save waits.
- Cash and double-currency account tiles now stay the same size and use inline | separators instead of bordered mini-pills.
- SMS capture, permissions, notifications, and local storage maintenance paths were tightened for the stable Android build.

## Notes

- Planned stable release: Android 1.5.0 / 1050000 for arm64-v8a devices.
- Validated locally with mobile lint/typecheck, focused package typechecks, ledger tests, and signed release APK build; final physical 1.5.0 install is pending ADB reconnect.
