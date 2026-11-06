#!/bin/bash
# Builds build/Move.app (release, hardened runtime, no network). No Apple Developer account needed.
# Signing, in order:
#   1. SIGN_ID="Your Identity" ./scripts/build.sh
#   2. a "Move Local Signing" or "AA Local Code Signing" certificate in your keychain (scripts/make-cert.sh makes one):
#      same signature every build, so macOS keeps the Accessibility grant across rebuilds
#   3. ad-hoc ("-"): works, but macOS forgets the Accessibility grant after every rebuild
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${SIGN_ID:-}" ]; then
  SIGN_ID=-
  for id in "Move Local Signing" "AA Local Code Signing"; do
    if security find-certificate -c "$id" > /dev/null 2>&1; then SIGN_ID="$id"; break; fi
  done
fi
# UNIVERSAL=1: one binary for Apple silicon and Intel (needs full Xcode; release CI uses it).
ARCH=()
if [ "${UNIVERSAL:-}" = 1 ]; then ARCH=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCH[@]+"${ARCH[@]}"}
BIN="$(swift build -c release ${ARCH[@]+"${ARCH[@]}"} --show-bin-path)/Move"
if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make-icon.swift && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
APP=build/Move.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Move"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --timestamp=none --entitlements Resources/Move.entitlements \
  --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
