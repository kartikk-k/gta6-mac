#!/bin/bash
# Builds a Developer ID–signed, notarized and stapled build/ViceNights.dmg, following the same
# pipeline as Doctor Mac (sign → DMG → notarize → staple → verify). Doctor Mac drives Xcode
# projects, and this is a Swift package, so the steps run here instead, using the notarization
# credentials already set up in Doctor Mac.
#
#   scripts/release.sh                  # full pipeline
#   scripts/release.sh --skip-notarize  # signed DMG only
#
# Overrides: SIGN_IDENTITY (default: the first "Developer ID Application" identity) and
# NOTARY_PROFILE (default: the first credential's keychain profile in Doctor Mac).
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_NOTARIZE=0
[ "${1:-}" = "--skip-notarize" ] && SKIP_NOTARIZE=1

APP="build/release/Vice Nights.app"   # a separate copy: build/ViceNights.app stays dev-signed,
DMG="build/ViceNights.dmg"             # so its Accessibility permission survives

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/' || true)}"
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application certificate in the keychain." >&2
  exit 1
fi

echo "==> Build"
scripts/build-app.sh >/dev/null
rm -rf build/release
mkdir -p build/release
cp -R build/ViceNights.app "$APP"

echo "==> Sign app ($IDENTITY)"
xattr -cr "$APP"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Vice Nights" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$SKIP_NOTARIZE" = 1 ]; then
  echo "Signed (not notarized): $DMG"
  exit 0
fi

PROFILE="${NOTARY_PROFILE:-}"
if [ -z "$PROFILE" ]; then
  STATE="$HOME/Library/Application Support/DoctorMac/state.json"
  PROFILE=$(plutil -extract credentials.0.keychainProfile raw -o - "$STATE" 2>/dev/null || true)
fi
if [ -z "$PROFILE" ]; then
  echo "No notarization profile: set NOTARY_PROFILE or add an API key in Doctor Mac." >&2
  exit 1
fi

echo "==> Notarize (profile $PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Staple"
xcrun stapler staple "$DMG"

echo "==> Verify"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG"
echo "Notarized: $DMG"
