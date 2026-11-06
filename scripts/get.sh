#!/bin/bash
# Installs the latest Move release, signed on your Mac. No Xcode, no Apple Developer account.
#
#   curl -fsSL https://raw.githubusercontent.com/ahmadawais/move/main/scripts/get.sh | bash
#
# 1. Downloads Move.zip, make-cert.sh and SHA256SUMS from the GitHub release.
# 2. Checks the SHA-256 sums. With the GitHub CLI signed in, also checks the build provenance: proof the zip
#    was built by this repo's release workflow from the tagged commit (gh attestation verify).
# 3. Signs Move with a local certificate ("Move Local Signing", created once with make-cert.sh) so macOS keeps
#    the Accessibility permission across updates. MOVE_ADHOC=1 signs ad-hoc instead (re-allow after updates).
# 4. Replaces /Applications/Move.app and opens it. Run it again to update.
#
# MOVE_VERSION=v1.0.0 pins a release (default: latest).
set -euo pipefail

REPO="ahmadawais/move"
VERSION="${MOVE_VERSION:-latest}"
CERT="Move Local Signing"
if [ "$VERSION" = latest ]; then BASE="https://github.com/$REPO/releases/latest/download"
else BASE="https://github.com/$REPO/releases/download/$VERSION"; fi

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Move is a macOS app."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

say "Downloading Move ($VERSION)"
for f in Move.zip make-cert.sh SHA256SUMS; do
  curl -fsSL --proto '=https' --tlsv1.2 -o "$f" "$BASE/$f" || die "couldn't download $f from $BASE"
done

say "Verifying"
shasum -a 256 -c SHA256SUMS || die "checksum mismatch: the download is damaged or was changed"
if command -v gh > /dev/null && gh auth status > /dev/null 2>&1; then
  for f in Move.zip make-cert.sh; do
    gh attestation verify "$f" --repo "$REPO" > /dev/null || die "$f has no valid build provenance for $REPO"
  done
  echo "Build provenance: built by $REPO's release workflow"
else
  echo "Build provenance: skipped (install the GitHub CLI and sign in to check it)"
fi

ditto -x -k Move.zip .
[ -d Move.app ] || die "Move.zip has no Move.app"
xattr -cr Move.app   # curl doesn't quarantine, but a copied-in zip might

ID="-"
if [ "${MOVE_ADHOC:-}" != 1 ]; then
  for id in "$CERT" "AA Local Code Signing"; do
    if security find-certificate -c "$id" > /dev/null 2>&1; then ID="$id"; break; fi
  done
  if [ "$ID" = "-" ]; then
    say "Creating a local signing certificate (once per Mac)"
    if [ -r /dev/tty ]; then bash make-cert.sh < /dev/tty || true; else bash make-cert.sh || true; fi
    security find-certificate -c "$CERT" > /dev/null 2>&1 && ID="$CERT"
  fi
fi

say "Signing with ${ID/#-/ad-hoc}"
codesign --force --options runtime --timestamp=none --preserve-metadata=entitlements --sign "$ID" Move.app
codesign --verify --strict Move.app

say "Installing"
pkill -x Move 2> /dev/null || true
for _ in $(seq 50); do pgrep -xq Move || break; sleep 0.1; done
rm -rf /Applications/Move.app
ditto Move.app /Applications/Move.app
open /Applications/Move.app

V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Move.app/Contents/Info.plist)"
say "Move $V is in /Applications."
echo "First time: System Settings → Privacy & Security → Accessibility → turn on Move. It relaunches by itself."
[ "$ID" = "-" ] && echo "Signed ad-hoc: after each update, turn Move off and on again in that list."
exit 0
