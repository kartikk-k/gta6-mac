#!/bin/bash
# Builds build/ViceNights.app (menu bar only), signed with your Apple Development identity if present.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0}"
# Build number: the commit count, so every release goes up.
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
swift build -c release
APP="build/ViceNights.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ViceNights "$APP/Contents/MacOS/ViceNights"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.vicenights.theme</string>
  <key>CFBundleName</key><string>Vice Nights</string>
  <key>CFBundleDisplayName</key><string>Vice Nights</string>
  <key>CFBundleExecutable</key><string>ViceNights</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# Sign with your Apple Development identity when available, so macOS keeps the Accessibility
# permission across rebuilds (an ad-hoc signature changes every build and resets it).
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
if [ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1; then
  echo "Signed with $IDENTITY"
else
  codesign --force --sign - "$APP" >/dev/null
  echo "Signed ad-hoc"
fi
echo "Built $APP"
