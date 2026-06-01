# Mobile Updates

1wallet uses a hybrid update model for Android:

- Firestore stores published release metadata under `appUpdates/android`.
- APK files are hosted through this public repository's GitHub Releases by default. The separate `APK_RELEASE_REPO` mirror is optional and controlled by `PUBLISH_APK_TO_ASSETS_REPO`.
- The app downloads APK updates into private app cache, verifies SHA-256, then opens the Android system installer.
- Users can choose the `stable` or `beta` update channel from the Updates screen. The selection is stored per installed app/device.
- `expo-updates` is installed for compatible JavaScript/assets updates, but true JS OTA is optional. It cannot replace APK updates for native code, permissions, Android modules, signing, or dependency changes.

Android does not allow this app to silently install APK files. Users must confirm installation in the system installer.

## Versioning

Use semantic versions for display and Android `versionCode` for ordering.

Recommended mapping:

```text
versionCode = major * 1000000 + minor * 10000 + patch * 100
```

Examples:

```text
1.0.0 -> 1000000
1.2.0 -> 1020000
1.2.3 -> 1020300
```

The current target release is the stable rescue `1.4.1` with version code `1040100`. The earlier `1.4.0 / 1040000` rescue is published, but the accidental beta's old in-app updater can compute its current build as `1040000`, so the in-app rescue must be higher than that. Use `1.3.0` as the baseline when testing update detection, and use `1039901` to verify the installed-beta rescue path.

Release asset names are channel-aware and omit `versionCode` for readability:

```text
1wallet-1.4.1-stable-arm64-v8a.apk
1wallet-1.4.2-beta.1-beta-arm64-v8a.apk
```

Keep `versionCode` in Android build metadata, Firestore release IDs, workflow artifact names, and Git tags. Android uses `versionCode` for install ordering, so beta builds must stay above the last stable build and below the next stable build. Stable versions may end in `.0`; beta versions must not. After stable `1.4.1`, the next beta line is `1.4.2-beta.1 / 1040101`, below the future stable `1.4.2 / 1040200`.

Recommended GitHub Release tags:

```text
android-stable-v1.4.1-1040100
android-beta-v1.4.2-beta.1-1040101
```

## Firestore Schema

Latest channel pointer:

```text
appUpdates/android/channels/stable
appUpdates/android/channels/beta
```

Release document:

```text
appUpdates/android/releases/1040100
```

Required release fields:

```json
{
  "platform": "android",
  "channel": "stable",
  "status": "published",
  "versionName": "1.4.1",
  "versionCode": 1040100,
  "runtimeVersion": "1.4.1",
  "releaseType": "patch",
  "mandatory": false,
  "requirement": "optional",
  "minimumSupportedVersionCode": 0,
  "publishedAt": "Firestore timestamp",
  "changelog": {
    "newFeatures": ["Home header now shows 1Wallet again"],
    "bugFixes": ["Improved update error handling"],
    "notes": ["APK installation opens the Android system installer"]
  },
  "apk": {
    "downloadUrl": "https://github.com/joelpjoji-mns/1wallet/releases/download/android-stable-v1.4.1-1040100/1wallet-1.4.1-stable-arm64-v8a.apk",
    "fileName": "1wallet-1.4.1-stable-arm64-v8a.apk",
    "sizeBytes": 30000000,
    "sha256": "64 lowercase hex characters",
    "architecture": "arm64-v8a",
    "minSdk": 24,
    "estimatedDownloadSeconds": 60
  }
}
```

The channel document should point at the latest published build:

```json
{
  "platform": "android",
  "channel": "stable",
  "status": "published",
  "latestVersionCode": 1040100,
  "updatedAt": "Firestore timestamp"
}
```

## Generate Metadata

After building the APK, generate the release manifest:

```powershell
pnpm run mobile:update:manifest -- --apk apps/mobile/android/app/build/outputs/apk/release/app-release.apk --version 1.4.1 --version-code 1040100 --url "https://example.com/1wallet-1.4.1-stable-arm64-v8a.apk" --file-name "1wallet-1.4.1-stable-arm64-v8a.apk" --architecture arm64-v8a --channel stable --release-type patch --feature "Home header now shows 1Wallet again" --fix "Update download validation" --note "Android installer confirmation is required" --output importdata/mobile-update-1.4.1-stable.json
```

## Release Workflow

Do not commit directly to `main`. Create a feature or fix branch from `main`, test locally and on device as needed, then open a pull request. Fill the PR Release Notes sections because they become both the GitHub Release notes and the in-app OTA changelog.

Stable releases publish only after a PR is merged into `main`. The Android Release workflow builds the arm64-v8a APK used by production phones, uploads it to this repo's GitHub Release, generates the manifest, and publishes the Firestore `stable` channel document. PRs that should not ship an APK must use the `skip-release` label or include `[skip release]` in the merge commit.

Beta releases are explicit pre-merge releases from a feature or PR branch. Run the Android Release workflow manually with `channel=beta` and a `beta_number` from `1` to `99`; the workflow derives a display version like `1.4.2-beta.1` and a lower-than-target-stable version code like `1040101`. It publishes a prerelease GitHub Release and updates `appUpdates/android/channels/beta`. Do not dispatch beta from `main`, and do not dispatch beta from a source version whose patch is `0`.

The repo still keeps local universal/x86 build scripts for emulator QA. If `PUBLISH_APK_TO_ASSETS_REPO=true`, the workflow also mirrors the same APK and manifest to `APK_RELEASE_REPO`; otherwise the Firestore `apk.downloadUrl` points at this repo.

## Beta Opt-Out

When a user switches from beta back to stable in the app, the update provider clears stale beta download state and checks the `stable` channel. Android will only install updates with a higher `versionCode`; if the installed beta has a higher code than the latest stable, the user will remain on that beta until a newer stable release is published.

The Updates screen shows the installed release identity separately from the selected checking channel. It reads `appUpdates/android/releases/{installedVersionCode}` so an installed beta can still show as beta even when Android reports only the base app version. The selected channel still comes from local app settings and controls which channel pointer is checked.

True JS OTA through `expo-updates` can be added later for JavaScript/assets-only fixes, but it is not required for the current update system. The APK pipeline is the reliable path for this app because most release changes can include native Android code, permissions, or native module updates.

## QA Checklist

1. Install a signed `1.3.0` build on the Pixel.
2. Publish `1.3.1` metadata and APK URL.
3. Open the drawer, then Updates.
4. Confirm it shows current version, new version, release type, mandatory/optional status, changelog, size, and ETA.
5. Tap Update app and confirm progress moves.
6. Tap Cancel and confirm `Update cancelled`.
7. Retry and complete download.
8. Confirm checksum success and `Update downloaded successfully`.
9. Tap Install update and complete Android installer confirmation.
10. Relaunch and confirm `Your app is up to date`.
11. Test offline, bad URL, checksum mismatch, denied install permission, installer cancellation, stale metadata, and low storage where feasible.
12. Switch to beta, confirm the app checks the beta channel, then switch back to stable and confirm stale beta download state clears.
13. On a device with `1039901` installed, switch to stable and confirm the app offers `1.4.1 / 1040100`.
14. On an older `1.2.x` build, confirm stable checks jump directly to the latest `channels/stable.latestVersionCode` release instead of stepping through older releases.

## Rollback

To stop serving an update, change the channel pointer back to the previous `latestVersionCode` or remove the published release document from the active channel. Clients cannot write update metadata because Firestore rules deny release/channel writes from the app.
