# Cleanup Audit

Date: 2026-05-30

This audit records the first implementation pass for the major cleanup/refactor request. The goal is to keep the commit clean without deleting source files that are framework entrypoints, native entrypoints, dependency patches, schema history, tests, docs, or QA evidence.

## Preflight Snapshot

- Staged files after generated-artifact cleanup: 260.
- Staged top-level areas: `apps` 203, `packages` 34, `docs` 10, `supabase` 2, plus root config/readme/lock/workspace files and `patches` 1.
- Unstaged tracked changes after this pass include the inventory script wiring, parser cleanup, mobile lint/style cleanup, and removal of stale inline planned-payment screen code.
- Generated artifacts are no longer staged: no staged matches for `.cxx`, Android `build/`, `.turbo/`, `.next/`, `*.tsbuildinfo`, `expo-env.d.ts`, or `local.properties`.

## Inventory Output

- Inventory file: `docs/code-inventory.csv`.
- Generator: `scripts/generate-code-inventory.mjs`.
- Files inventoried: 297 Git-visible non-generated files after adding release QA screenshot evidence.
- Rows generated: 2,288.
- Source/runtime files remain 262; the additional files are cleanup-release screenshots kept as QA evidence.
- The generator prefers the TypeScript compiler API when dependencies are installed and falls back to a lightweight parser when `node_modules` is absent.

## Cleanup Completed

Removed from the index and disk:

- `apps/mobile/android/.gradle/`
- `apps/mobile/android/app/.cxx/`
- `apps/mobile/android/app/build/`
- `apps/mobile/android/build/`
- `apps/mobile/.expo/`
- Package `.turbo/` folders
- Package `dist/` folders
- Loose generated `*.tsbuildinfo`, `.tmp-*.json`, and `expo-env.d.ts` files outside `node_modules`

The same generated Android/package build outputs were removed again after release-emulator validation so the worktree stays commit-ready.

Left intentionally untouched:

- `node_modules/` workspace/package folders, because dependency reinstall timing should be a deliberate validation step.
- `apps/mobile/android/local.properties`, because it is local SDK machine config and already ignored.
- `backups/`, because it may contain local device/emulator data and is ignored.
- `screenshots/`, because it is QA evidence and not safe to prune automatically.

## Keep-By-Convention Files

The inventory marks these as keep-worthy even when normal import references are low:

- Expo Router files under `apps/mobile/app/**`.
- Android native classes under `apps/mobile/android/app/src/main/java/**`.
- Tooling/config files such as Metro, Babel, Expo, Turbo, TypeScript, and package manifests.
- `patches/react-native-get-sms-android@2.1.0.patch`, because `pnpm` references it.
- `supabase/migrations/**`, because migrations are schema history.
- Font, image, icon, and Android resource assets.

## Source Cleanup Policy

No framework route, native, config, migration, patch, test, asset, or QA evidence source files were deleted in this pass. Source deletion needs all of the following:

- No import references or package export references.
- Not a framework/native/config entrypoint.
- Not a migration, dependency patch, test fixture, QA evidence file, or asset referenced by native/Expo config.
- Static validation remains green after removal.

## Refactor Candidate Summary

Generated tags from `docs/code-inventory.csv`:

- `add-record-extraction-review`: 44 symbols in `apps/mobile/app/add.tsx`.
- `parser-performance-review`: 95 symbols in `packages/ledger/src/capture/messages.ts`.
- `index-performance-review`: 10 symbols in `packages/ledger/src/services/indexes.ts`.
- `large-file` / `screen-decomposition`: several large mobile route files that should be refactored only in focused slices.
- `picker-reuse`: `apps/mobile/src/components/record/RecordPickers.tsx` remains a reuse candidate.

## Recommended Next Implementation Order

1. Add focused tests for ledger/index, currency, and parser behavior before semantic refactors.
2. Decompose `apps/mobile/app/add.tsx` in small behavior-preserving slices.
3. Optimize parser/index hot paths with fixtures proving output equivalence.
4. Consolidate duplicate record/currency helper logic shared by Add/Edit/Capture.
5. Keep release screenshots and `docs/mobile-qa-run-log.csv` rows as the audit trail for visual QA.

## Validation Status

Completed in this pass:

- `pnpm inventory` generated `docs/code-inventory.csv` successfully with the TypeScript compiler API: 2,288 rows for 297 Git-visible non-generated files.
- `git clean -ndX` after cleanup reports only intentionally retained ignored local items: `local.properties` and `node_modules/` folders.
- Staged generated build artifacts were removed from the index.
- `pnpm --filter @1wallet/mobile typecheck` passed.
- `pnpm --filter @1wallet/mobile lint` passed.
- `pnpm typecheck` passed.
- `pnpm test` passed.
- `pnpm lint` passed.
- `pnpm build` passed.
- `git diff --check` passed with line-ending warnings only.
- Android x86_64 release build passed after explicit React Native codegen artifact generation for the pnpm/Windows build.
- Release APK installed on `emulator-5554` and cold-launched successfully after a clean no-snapshot emulator boot.
- Local-auth first-run flow completed with disposable account `qa@onewallet.test`, including profile, main account, permissions, and Home handoff.
- Release visual QA covered Home, Notifications, Add Record, Transactions, Calendar, Planner, Accounts, Drawer, Settings, Currencies, Imports, and Review via normal UI navigation.
- Focused release logcat scan found no app `AndroidRuntime`, `FATAL EXCEPTION`, or `ReactNativeJS` crash signatures; matched lines were app GC/resource-close noise and Google Messages RCS emulator logs.
- Final generated-output cleanup leaves `git clean -ndX` previewing only intentionally retained ignored local items: `local.properties` and `node_modules/` folders.

Known release-emulator QA limitations:

- UIAutomator XML dump failed with `ERROR: could not get idle state`, so the release pass uses screenshots, `dumpsys` focus/surface checks, and logcat instead of XML text dumps.
- Deep-link route starts returned `Status: ok` but did not reliably navigate an already-mounted release activity, so the visual pass used normal UI taps/drawer navigation.
- Visual notes to revisit later: permissions onboarding is functional but visually dense, Add Record keypad sits close to the Android gesture bar, Calendar selector labels intentionally ellipsize, and Settings lower hub is copy-heavy but usable.
