#!/usr/bin/env bash
# build-dmg.sh — Build and package Kelpie.app into a distributable DMG.
# Usage:
#   ./scripts/build-dmg.sh               # unsigned (for dev distribution)
#   ./scripts/build-dmg.sh --sign        # sign + notarize (requires Developer ID)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACOS_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$MACOS_DIR/.build/dmg"
APP_NAME="Kelpie"
SCHEME="Kelpie"
CONFIGURATION="Release"
DMG_NAME="${APP_NAME}.dmg"

SIGN=false
IDENTITY=""
BUNDLE_ID="com.kelpie.browser.macos"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN=true ;;
        --identity) IDENTITY="$2"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/app"

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | (xcpretty 2>/dev/null || cat)

echo "==> Extracting app from archive"
cp -R "$BUILD_DIR/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "$BUILD_DIR/app/"

if $SIGN; then
    if [[ -z "$IDENTITY" ]]; then
        # Auto-detect Developer ID Application certificate
        IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
        if [[ -z "$IDENTITY" ]]; then
            echo "ERROR: No Developer ID Application certificate found. Install one or pass --identity."
            exit 1
        fi
    fi
    echo "==> Signing with: $IDENTITY"
    codesign --deep --force --verify --verbose \
        --sign "$IDENTITY" \
        --options runtime \
        "$BUILD_DIR/app/${APP_NAME}.app"
fi

echo "==> Creating DMG"
# Get version from built app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "$BUILD_DIR/app/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "1.0")
VERSIONED_DMG="${APP_NAME}-${VERSION}.dmg"

# Create a temporary writable DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUILD_DIR/app" \
    -ov \
    -format UDRW \
    "$BUILD_DIR/tmp.dmg"

# Mount it
MOUNT_DIR=$(hdiutil attach "$BUILD_DIR/tmp.dmg" -readwrite -noverify -noautoopen | grep "Volumes" | awk '{print $NF}')

# Add Applications symlink
ln -sf /Applications "$MOUNT_DIR/Applications"

# Unmount
hdiutil detach "$MOUNT_DIR"

# Convert to compressed read-only DMG
hdiutil convert "$BUILD_DIR/tmp.dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$BUILD_DIR/$VERSIONED_DMG"

rm "$BUILD_DIR/tmp.dmg"

if $SIGN; then
    echo "==> Signing DMG"
    codesign --sign "$IDENTITY" "$BUILD_DIR/$VERSIONED_DMG"

    echo "==> Notarizing (this may take a few minutes)"
    echo "    Set APPLE_ID and APPLE_TEAM_ID env vars, or run manually:"
    echo "    xcrun notarytool submit \"$BUILD_DIR/$VERSIONED_DMG\" --apple-id \$APPLE_ID --team-id \$APPLE_TEAM_ID --wait"
    echo "    xcrun stapler staple \"$BUILD_DIR/$VERSIONED_DMG\""
fi

echo ""
echo "==> Done: $BUILD_DIR/$VERSIONED_DMG"
