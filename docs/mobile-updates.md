# Mobile Updates

1wallet uses a hybrid update model for Android:

- Firestore stores published release metadata under `appUpdates/android`.
- APK files are hosted through this public repository's GitHub Releases by default. The separate `APK_RELEASE_REPO` mirror is optional and controlled by `PUBLISH_APK_TO_ASSETS_REPO`.
- The app downloads APK updates into private app cache, verifies SHA-256, then opens the Android system installer.
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

The current target release is `1.2.1` with version code `1020100`. Use `1.2.0` as the baseline when testing update detection.

## Firestore Schema

Latest channel pointer:

```text
appUpdates/android/channels/stable
```

Release document:

```text
appUpdates/android/releases/1020100
```

Required release fields:

```json
{
  "platform": "android",
  "channel": "stable",
  "status": "published",
  "versionName": "1.2.1",
  "versionCode": 1020100,
  "runtimeVersion": "1.2.1",
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
    "downloadUrl": "https://github.com/joelpjoji-mns/1wallet/releases/download/android-v1.2.1-1020100/1wallet-1.2.1-1020100-universal.apk",
    "fileName": "1wallet-1.2.1-1020100-universal.apk",
    "sizeBytes": 62217478,
    "sha256": "64 lowercase hex characters",
    "architecture": "universal",
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
  "latestVersionCode": 1020100,
  "updatedAt": "Firestore timestamp"
}
```

## Generate Metadata

After building the APK, generate the release manifest:

```powershell
pnpm run mobile:update:manifest -- --apk apps/mobile/android/app/build/outputs/apk/release/app-universal-release.apk --version 1.2.1 --version-code 1020100 --url "https://example.com/app-universal-release.apk" --release-type patch --feature "Home header now shows 1Wallet again" --fix "Update download validation" --note "Android installer confirmation is required" --output importdata/mobile-update-1.2.1.json
```

The GitHub Actions Android Release workflow builds the APK, uploads it to this repo's GitHub Release, generates the manifest, and publishes the Firestore release/channel documents. If `PUBLISH_APK_TO_ASSETS_REPO=true`, it also mirrors the same APK and manifest to `APK_RELEASE_REPO`; otherwise the Firestore `apk.downloadUrl` points at this repo.

True JS OTA through `expo-updates` can be added later for JavaScript/assets-only fixes, but it is not required for the current update system. The APK pipeline is the reliable path for this app because most release changes can include native Android code, permissions, or native module updates.

## QA Checklist

1. Install a signed `1.2.0` build on the Pixel.
2. Publish `1.2.1` metadata and APK URL.
3. Open the drawer, then Updates.
4. Confirm it shows current version, new version, release type, mandatory/optional status, changelog, size, and ETA.
5. Tap Update app and confirm progress moves.
6. Tap Cancel and confirm `Update cancelled`.
7. Retry and complete download.
8. Confirm checksum success and `Update downloaded successfully`.
9. Tap Install update and complete Android installer confirmation.
10. Relaunch and confirm `Your app is up to date`.
11. Test offline, bad URL, checksum mismatch, denied install permission, installer cancellation, stale metadata, and low storage where feasible.

## Rollback

To stop serving an update, change the channel pointer back to the previous `latestVersionCode` or remove the published release document from the active channel. Clients cannot write update metadata because Firestore rules deny release/channel writes from the app.
