#!/bin/bash
set -euo pipefail

# Build 1wallet for iOS without code signing, then package into a LiveContainer-compatible IPA.

echo "==> Fetching Flutter dependencies..."
flutter pub get

echo "==> Building iOS release bundle (no codesign)..."
flutter build ios --release --no-codesign

echo "==> Packaging into LiveContainer IPA..."
PAYLOAD_DIR="build/LiveContainer_Payload/Payload"
mkdir -p "$PAYLOAD_DIR"
rm -rf "$PAYLOAD_DIR"/*
cp -R build/ios/iphoneos/Runner.app "$PAYLOAD_DIR/"

(
  cd build/LiveContainer_Payload
  zip -qr ../../1wallet-LiveContainer.ipa Payload
)

echo "==> SUCCESS! LiveContainer IPA ready at: 1wallet-LiveContainer.ipa"
