#!/usr/bin/env bash
# Downloads a pinned Firefox release, strips Mozilla branding, and places the
# result as apps/macos/Frameworks/MollotovGeckoHelper.app.
# Run once: make gecko-runtime
set -euo pipefail

FIREFOX_VERSION="122.0.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$SCRIPT_DIR/../apps/macos/Frameworks"
HELPER_APP="$DEST_DIR/MollotovGeckoHelper.app"
TMP_DMG="/tmp/mollotov-gecko-${FIREFOX_VERSION}.dmg"
MOUNT_POINT="/Volumes/MollotovFirefoxSetup"

if [ -d "$HELPER_APP" ]; then
  echo "MollotovGeckoHelper.app already present. Delete it to re-download."
  exit 0
fi

echo "Downloading Firefox ${FIREFOX_VERSION}..."
curl -L --progress-bar \
  "https://releases.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/mac/en-US/Firefox%20${FIREFOX_VERSION}.dmg" \
  -o "$TMP_DMG"

echo "Mounting DMG..."
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -quiet -nobrowse

echo "Copying..."
cp -R "$MOUNT_POINT/Firefox.app" "$HELPER_APP"

echo "Unmounting..."
hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$TMP_DMG"

echo "Stripping Mozilla branding..."
PLIST="$HELPER_APP/Contents/Info.plist"
plist_set_or_add() {
  local type="$1" key="$2" value="$3"
  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "$PLIST"
}
plist_set_or_add string CFBundleIdentifier  com.mollotov.gecko-helper
plist_set_or_add string CFBundleName        MollotovGeckoHelper
plist_set_or_add string CFBundleDisplayName MollotovGeckoHelper
plist_set_or_add bool   LSUIElement         true

echo "Re-signing with ad-hoc identity..."
codesign --remove-signature "$HELPER_APP" 2>/dev/null || true
codesign -fs - "$HELPER_APP" 2>/dev/null || true

echo "MollotovGeckoHelper.app ready at $HELPER_APP"
