## Summary

-

## Release Notes

### New Features

-

### Bug Fixes

-

### Notes

-

## Verification

- \*\*\* Add File: c:\Users\Joel\Documents\Github\1wallet\.github\workflows\ci.yml
  name: CI

on:
pull_request:
push:
branches: - main

permissions:
contents: read

jobs:
typecheck:
name: Typecheck
runs-on: ubuntu-latest
steps: - name: Checkout
uses: actions/checkout@v4

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 11.4.0

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Typecheck mobile app
        run: pnpm --filter @1wallet/mobile typecheck

\*\*\* Add File: c:\Users\Joel\Documents\Github\1wallet\.github\workflows\android-release.yml
name: Android Release

on:
push:
branches: - main
workflow_dispatch:
inputs:
release_type:
description: Release type for update metadata
required: true
default: patch
type: choice
options: - patch - minor - major
mandatory:
description: Mark the in-app update as mandatory
required: true
default: false
type: boolean
features:
description: New feature changelog lines, one per line
required: false
type: string
fixes:
description: Bug fix changelog lines, one per line
required: false
type: string
notes:
description: Extra release notes, one per line
required: false
type: string

permissions:
contents: write
pull-requests: read

jobs:
release:
name: Build and publish APK
runs-on: ubuntu-latest
if: github.event_name == 'workflow_dispatch' || !contains(github.event.head_commit.message, '[skip release]')
env:
APK_PATH: apps/mobile/android/app/build/outputs/apk/release/app-universal-release.apk
ASSET_REPO: ${{ vars.APK_RELEASE_REPO }}
FIREBASE_PROJECT_ID: ${{ vars.FIREBASE_PROJECT_ID || 'wallet-1a5af' }}
UPDATE_CHANNEL: ${{ vars.ONEWALLET_UPDATE_CHANNEL || 'stable' }}
PUBLISH_ASSET_REPO: ${{ vars.PUBLISH_APK_TO_ASSETS_REPO || 'true' }}
RELEASE_TYPE: ${{ inputs.release_type || 'patch' }}
MANDATORY_UPDATE: ${{ inputs.mandatory || false }}
steps: - name: Checkout
uses: actions/checkout@v4
with:
fetch-depth: 0

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3

      - name: Install Android build packages
        run: sdkmanager "platforms;android-36" "build-tools;36.0.0" "ndk;27.1.12297006"

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 11.4.0

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Write mobile environment
        run: |
          {
            echo "EXPO_PUBLIC_FIREBASE_API_KEY=${{ secrets.EXPO_PUBLIC_FIREBASE_API_KEY }}"
            echo "EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN=${{ secrets.EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN }}"
            echo "EXPO_PUBLIC_FIREBASE_PROJECT_ID=${{ secrets.EXPO_PUBLIC_FIREBASE_PROJECT_ID }}"
            echo "EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET=${{ secrets.EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET }}"
            echo "EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID=${{ secrets.EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID }}"
            echo "EXPO_PUBLIC_FIREBASE_APP_ID=${{ secrets.EXPO_PUBLIC_FIREBASE_APP_ID }}"
            echo "EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID=${{ secrets.EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID }}"
            echo "EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID=${{ secrets.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID }}"
            echo "EXPO_PUBLIC_FIREBASE_USE_EMULATOR=false"
          } > .env.local

      - name: Restore Android release keystore
        run: |
          printf '%s' "${{ secrets.ONEWALLET_RELEASE_KEYSTORE_BASE64 }}" | base64 --decode > apps/mobile/android/release.keystore
          chmod 600 apps/mobile/android/release.keystore

      - name: Read release info
        id: info
        run: node scripts/mobile-release-info.mjs --output "$GITHUB_OUTPUT"

      - name: Typecheck mobile app
        run: pnpm --filter @1wallet/mobile typecheck

      - name: Build signed universal APK
        env:
          ONEWALLET_RELEASE_STORE_FILE: release.keystore
          ONEWALLET_RELEASE_STORE_PASSWORD: ${{ secrets.ONEWALLET_RELEASE_STORE_PASSWORD }}
          ONEWALLET_RELEASE_KEY_ALIAS: ${{ secrets.ONEWALLET_RELEASE_KEY_ALIAS }}
          ONEWALLET_RELEASE_KEY_PASSWORD: ${{ secrets.ONEWALLET_RELEASE_KEY_PASSWORD }}
        run: pnpm --filter @1wallet/mobile android:release:universal

      - name: Collect release note source
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh pr list --repo "$GITHUB_REPOSITORY" --state merged --search "$GITHUB_SHA" --json number,title,body,url --limit 1 > .tmp-pr.json || echo "[]" > .tmp-pr.json
          previous_tag="$(git describe --tags --match 'android-v*' --abbrev=0 2>/dev/null || true)"
          if [ -n "$previous_tag" ]; then
            git log --pretty=format:'%s' "$previous_tag..HEAD" > .tmp-commits.txt
          else
            git log --pretty=format:'%s' -20 > .tmp-commits.txt
          fi

      - name: Generate release notes
        run: |
          node scripts/mobile-release-notes.mjs \
            --pr-json .tmp-pr.json \
            --commit-log .tmp-commits.txt \
            --version "${{ steps.info.outputs.versionName }}" \
            --version-code "${{ steps.info.outputs.versionCode }}" \
            --feature "${{ inputs.features }}" \
            --fix "${{ inputs.fixes }}" \
            --note "${{ inputs.notes }}" \
            --output .tmp-release-notes.json \
            --markdown .tmp-release-notes.md

      - name: Publish APK to this repository release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          tag="${{ steps.info.outputs.tag }}"
          title="1Wallet Android ${{ steps.info.outputs.versionName }} (${{ steps.info.outputs.versionCode }})"
          if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
            gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --title "$title" --notes-file .tmp-release-notes.md --prerelease=false
          else
            gh release create "$tag" --repo "$GITHUB_REPOSITORY" --title "$title" --notes-file .tmp-release-notes.md
          fi
          gh release upload "$tag" "$APK_PATH#${{ steps.info.outputs.apkFileName }}" --repo "$GITHUB_REPOSITORY" --clobber

      - name: Publish APK to public assets repo
        id: asset_release
        env:
          GH_TOKEN: ${{ secrets.GH_RELEASE_TOKEN }}
        run: |
          tag="${{ steps.info.outputs.tag }}"
          title="1Wallet Android ${{ steps.info.outputs.versionName }} (${{ steps.info.outputs.versionCode }})"
          download_repo="$GITHUB_REPOSITORY"
          if [ "$PUBLISH_ASSET_REPO" != "false" ] && [ -n "$ASSET_REPO" ]; then
            if gh release view "$tag" --repo "$ASSET_REPO" >/dev/null 2>&1; then
              gh release edit "$tag" --repo "$ASSET_REPO" --title "$title" --notes-file .tmp-release-notes.md --prerelease=false
            else
              gh release create "$tag" --repo "$ASSET_REPO" --title "$title" --notes-file .tmp-release-notes.md
            fi
            gh release upload "$tag" "$APK_PATH#${{ steps.info.outputs.apkFileName }}" --repo "$ASSET_REPO" --clobber
            download_repo="$ASSET_REPO"
          fi
          download_url="$(gh release view "$tag" --repo "$download_repo" --json assets --jq '.assets[] | select(.name == "${{ steps.info.outputs.apkFileName }}") | .url')"
          echo "download_url=$download_url" >> "$GITHUB_OUTPUT"
          echo "download_repo=$download_repo" >> "$GITHUB_OUTPUT"

      - name: Generate update manifest
        run: |
          mandatory_args=()
          if [ "$MANDATORY_UPDATE" = "true" ]; then
            mandatory_args=(--mandatory true)
          fi
          pnpm run mobile:update:manifest -- \
            --apk "$APK_PATH" \
            --version "${{ steps.info.outputs.versionName }}" \
            --version-code "${{ steps.info.outputs.versionCode }}" \
            --url "${{ steps.asset_release.outputs.download_url }}" \
            --channel "$UPDATE_CHANNEL" \
            --release-type "$RELEASE_TYPE" \
            --changelog-json .tmp-release-notes.json \
            "${mandatory_args[@]}" \
            --output "importdata/mobile-update-${{ steps.info.outputs.versionName }}.json"

      - name: Publish update metadata to Firestore
        env:
          FIREBASE_SERVICE_ACCOUNT_JSON: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}
        run: |
          pnpm run mobile:update:publish -- \
            --project "$FIREBASE_PROJECT_ID" \
            --skip-upload \
            --manifest "importdata/mobile-update-${{ steps.info.outputs.versionName }}.json"

      - name: Upload manifest to releases
        env:
          GH_TOKEN: ${{ secrets.GH_RELEASE_TOKEN }}
        run: |
          tag="${{ steps.info.outputs.tag }}"
          manifest="importdata/mobile-update-${{ steps.info.outputs.versionName }}.json"
          gh release upload "$tag" "$manifest#${{ steps.info.outputs.manifestFileName }}" --repo "$GITHUB_REPOSITORY" --clobber
          if [ "${{ steps.asset_release.outputs.download_repo }}" != "$GITHUB_REPOSITORY" ]; then
            gh release upload "$tag" "$manifest#${{ steps.info.outputs.manifestFileName }}" --repo "${{ steps.asset_release.outputs.download_repo }}" --clobber
          fi

      - name: Upload workflow artifacts
        uses: actions/upload-artifact@v4
        with:
          name: 1wallet-android-${{ steps.info.outputs.versionName }}-${{ steps.info.outputs.versionCode }}
          path: |
            ${{ env.APK_PATH }}
            importdata/mobile-update-${{ steps.info.outputs.versionName }}.json
            .tmp-release-notes.md
