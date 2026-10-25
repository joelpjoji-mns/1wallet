# Running 1wallet on iOS using LiveContainer

[LiveContainer](https://github.com/LiveContainer/LiveContainer) is an open-source iOS application launcher that allows you to run iOS apps (`.ipa` files) directly on non-jailbroken devices without counting towards Apple's free developer 3-app sideloading limit and without needing paid Apple Developer certificates.

---

## Why LiveContainer?

- **Bypass Apple's 3-App Limit**: LiveContainer itself only counts as **1** sideloaded app. Any app (like 1wallet) loaded inside LiveContainer does not consume additional free app IDs.
- **No Paid Apple Developer Account Needed**: Free Apple IDs or AltStore/SideStore certs expire every 7 days and cap active apps at 3. Inside LiveContainer, guest apps inherit LiveContainer's signature.
- **Multiple Instances & Sandbox**: Runs in an isolated container.

---

## Step 1: Install LiveContainer on your iOS Device

1. Download the latest `LiveContainer.ipa` or `LiveContainer+SideStore.ipa` from the [LiveContainer GitHub Releases](https://github.com/LiveContainer/LiveContainer/releases).
2. Sideload LiveContainer onto your iPhone or iPad using your preferred tool:
   - **SideStore** (recommended for on-device refreshes)
   - **AltStore**
   - **TrollStore** (if on a compatible iOS version)
   - **Sideloadly**
3. On your iOS device, go to **Settings > General > VPN & Device Management**, tap your developer account / Apple ID profile, and tap **Trust**.

---

## Step 2: Obtain `1wallet-LiveContainer.ipa`

### Option A: From GitHub Actions (Recommended)
1. Go to this repository's **Actions** tab on GitHub.
2. Select the **Build iOS for LiveContainer** workflow.
3. Click the latest successful run (or click **Run workflow**).
4. Download the **`1wallet-LiveContainer-IPA`** artifact zip and extract `1wallet-LiveContainer.ipa`.

### Option B: Build Locally on macOS
If you have a Mac with Flutter and Xcode installed:
```bash
chmod +x scripts/build_livecontainer_ipa.sh
./scripts/build_livecontainer_ipa.sh
```
The output file will be generated at `./1wallet-LiveContainer.ipa`.

---

## Step 3: Import & Run 1wallet inside LiveContainer

1. Transfer `1wallet-LiveContainer.ipa` to your iOS device (via AirDrop, iCloud Drive, or the native iOS **Files** app).
2. Open the **LiveContainer** app on your iPhone/iPad.
3. Tap the **`+` (Plus)** button located in the top-right corner.
4. Select `1wallet-LiveContainer.ipa` from your Files.
5. LiveContainer will extract and configure the app bundle.
6. Tap the **1wallet** icon from the LiveContainer app list to launch!

---

## Tips & Customization

- **Home Screen Shortcut**: In LiveContainer, long-press on 1wallet and select **Create Shortcut** (or use iOS Shortcuts with LiveContainer's URL scheme) to place a direct launch icon on your iOS home screen.
- **Multitasking & Floating Windows**: LiveContainer supports virtual windowing and Picture-in-Picture on supported iPadOS and iOS devices.
- **Data Backup**: App data is stored in LiveContainer's container directory and can be backed up or inspected via the Files app under `LiveContainer/Data`.
