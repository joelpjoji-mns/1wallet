# Mobile Updates

1wallet uses a hybrid update model for Android and iOS:

- Firestore stores published release metadata under `appUpdates/android` and `appUpdates/ios`.
- APK files are hosted through this public repository's GitHub Releases by default. The separate `APK_RELEASE_REPO` mirror is optional and controlled by `PUBLISH_APK_TO_ASSETS_REPO`.
- The app downloads APK updates into private app cache, verifies SHA-256, then opens the Android system installer.
- iOS native updates open TestFlight or the App Store from Firestore metadata. iOS does not download or install app binaries inside the app.
- Users can choose the `stable` or `beta` update channel from the Updates screen. The selection is stored per installed app/device.
- `expo-updates` is installed for compatible JavaScript/assets updates. It cannot replace native updates for native code, permissions, native modules, signing, or dependency changes.

Android does not allow this app to silently install APK files. Users must confirm installation in the system installer.

## Versioning

Use semantic versions for display. Android uses `versionCode`; iOS uses `buildNumber`. Firestore stores both platform counters as `versionCode` for shared ordering logic.

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

The current published stable rescue is `1.4.1` with version code `1040100`. The earlier `1.4.0 / 1040000` rescue is published, but the accidental beta's old in-app updater can compute its current build as `1040000`, so the in-app rescue had to be higher than that. Keep `1.4.1` as a one-time Android versionCode recovery exception; future planned stable releases should end in `.0`, such as `1.5.0 / 1050000`.

Release asset names are channel-aware and omit `versionCode` for readability:

```text
1wallet-1.4.1-stable-arm64-v8a.apk
1wallet-1.4.2-beta-arm64-v8a.apk
```

Keep `versionCode` in Android build metadata, Firestore release IDs, workflow artifact names, and Git tags. Android uses `versionCode` for install ordering, so every beta release must use a unique patch-numbered beta build above the last stable build. After the `1.4.1` rescue, the next beta line is `1.4.2-beta / 1040200`; later development betas should bump the patch again, for example `1.4.3-beta / 1040300`. The next planned stable line is `1.5.0 / 1050000`.

Recommended GitHub Release tags:

```text
android-stable-v1.4.1-1040100
android-beta-v1.4.2-beta-1040200
ios-stable-v1.5.3-1050300
ios-beta-v1.5.3-beta-1050300
```

## Firestore Schema

Latest channel pointer:

```text
appUpdates/android/channels/stable
appUpdates/android/channels/beta
appUpdates/ios/channels/stable
appUpdates/ios/channels/beta
```

Release document:

```text
appUpdates/android/releases/1040100
appUpdates/ios/releases/1050300
```

Firebase Console sorts collection documents by document ID in ascending order, so the app-facing `releases/{versionCode}` collection can look oldest-first in panel view. The release workflow also writes a console-friendly feed whose IDs start with an inverted version-code sort key, so panel view shows the newest Android build first:

```text
appUpdates/android/releaseFeed/998959899-1040100-stable-1.4.1
```

The app does not read `releaseFeed`; it is only for human browsing and release audits.

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

For iOS releases, replace the `apk` object with store metadata:

```json
{
  "platform": "ios",
  "channel": "beta",
  "status": "published",
  "versionName": "1.5.3-beta",
  "versionCode": 1050300,
  "runtimeVersion": "1.5.3-beta",
  "releaseType": "patch",
  "mandatory": false,
  "requirement": "optional",
  "minimumSupportedVersionCode": 0,
  "publishedAt": "Firestore timestamp",
  "changelog": {
    "newFeatures": ["iOS build is available through TestFlight"],
    "bugFixes": [],
    "notes": ["The app opens TestFlight or App Store to install native updates"]
  },
  "ios": {
    "testFlightUrl": "https://testflight.apple.com/join/example",
    "appStoreUrl": "https://apps.apple.com/app/id1234567890",
    "bundleIdentifier": "com.joelpjoji.one.wallet",
    "minimumOsVersion": "15.1"
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
pnpm run mobile:update:manifest -- --apk apps/mobile/android/app/build/outputs/apk/release/app-release.apk --version 1.5.0 --version-code 1050000 --url "https://example.com/1wallet-1.5.0-stable-arm64-v8a.apk" --file-name "1wallet-1.5.0-stable-arm64-v8a.apk" --architecture arm64-v8a --channel stable --release-type minor --feature "Home header now shows 1Wallet again" --fix "Update download validation" --note "Android installer confirmation is required" --output importdata/mobile-update-1.5.0-stable.json
```

For iOS, generate metadata with at least one store or build URL:

```powershell
pnpm run mobile:update:manifest -- --platform ios --version 1.5.3 --version-code 1050300 --channel stable --release-type patch --app-store-url "https://apps.apple.com/app/id1234567890" --bundle-identifier "com.joelpjoji.one.wallet" --minimum-os-version 15.1 --note "Native updates open in the App Store" --output importdata/mobile-update-1.5.3-stable-ios.json
```

## Release Workflow

Do not commit directly to `main` or `development`. Create `feature/*` or `bug/*` branches from `development`, test locally and on device as needed, then open a pull request back to `development`. Fill the PR Release Notes sections because they become both the GitHub Release notes and the in-app OTA changelog.

Beta releases publish from `development`. When a feature or bug PR is merged into `development`, the Android Release workflow builds the arm64-v8a APK and the iOS Release workflow builds through EAS/TestFlight. Both workflows create prerelease GitHub Releases, generate manifests, and update the Firestore `beta` channel documents. Each development beta must have a unique patch beta version such as `1.4.2-beta`; bump the patch again for the next beta.

Stable releases publish only after `development` is merged into `main`. The Android Release workflow builds the arm64-v8a APK used by production phones. The iOS Release workflow builds and submits through EAS/App Store Connect. Both workflows publish the Firestore `stable` channel documents. Future planned stable versions should use `.0` releases such as `1.5.0`; the existing Android `1.4.1` stable is a rescue exception. PRs that should not ship a native app update must use the `skip-release` label or include `[skip release]` in the merge commit.

The iOS workflows require `EXPO_TOKEN` plus Apple/EAS submit credentials in secrets, and `IOS_TESTFLIGHT_URL`, `IOS_APP_STORE_URL`, or `IOS_BUILD_URL` in repository variables so in-app update metadata can open the correct destination.

Manual workflow dispatch is reserved for release administration. Stable dispatches are allowed only from `main`. Beta dispatches are allowed from `development`, `feature/*`, or `bug/*`, never from `main`.

The repo still keeps local universal/x86 build scripts for emulator QA. If `PUBLISH_APK_TO_ASSETS_REPO=true`, the workflow also mirrors the same APK and manifest to `APK_RELEASE_REPO`; otherwise the Firestore `apk.downloadUrl` points at this repo.

## Beta Opt-Out

When a user switches from beta back to stable in the app, the update provider clears stale beta download state and checks the `stable` channel. Android will only install updates with a higher `versionCode`; if the installed beta has a higher code than the latest stable, the user will remain on that beta until a newer stable release is published.

The Updates screen shows the installed release identity separately from the selected checking channel. It reads `appUpdates/android/releases/{installedVersionCode}` so an installed beta can still show as beta even when Android reports only the base app version. The selected channel still comes from local app settings and controls which channel pointer is checked.

True JS OTA through `expo-updates` can be added later for JavaScript/assets-only fixes, but it is not required for the current update system. The APK pipeline is the reliable path for this app because most release changes can include native Android code, permissions, or native module updates.
On iOS, JS OTA can serve JavaScript/assets-only fixes, while native changes still go through TestFlight or App Store review.

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
15. On iOS, confirm beta metadata opens TestFlight and stable metadata opens the App Store or configured build URL.

## Rollback

To stop serving an update, change the channel pointer back to the previous `latestVersionCode` or remove the published release document from the active channel. Clients cannot write update metadata because Firestore rules deny release/channel writes from the app.
