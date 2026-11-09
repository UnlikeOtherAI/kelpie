#!/bin/bash
# Exercise the standalone address bar without sharing another job's app identity.
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <built-Kelpie.app> <new-result.xcresult>" >&2
    exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$(cd "$1" && pwd)"
result="$2"
case "$result" in /*) ;; *) result="$root/$result" ;; esac
if [ -e "$result" ]; then echo "Preserve the existing result: $result" >&2; exit 2; fi
fixture="$root/.cache/address-ui/KelpieAddressVerification.app"
if pgrep -x KelpieAddressVerification >/dev/null; then
    osascript -e 'tell application id "com.kelpie.browser.address-focus-verification" to quit'
    attempts=0
    while pgrep -x KelpieAddressVerification >/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -gt 50 ]; then echo "Previous verification app is still closing" >&2; exit 1; fi
        sleep 0.1
    done
fi
mkdir -p "$(dirname "$fixture")" "$(dirname "$result")"
if [ -d "$fixture" ]; then
    mv "$fixture" "$root/.cache/address-ui/previous-$(date +%s)-$$.app"
fi
ditto "$source_app" "$fixture"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.kelpie.browser.address-focus-verification' "$fixture/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable KelpieAddressVerification' "$fixture/Contents/Info.plist"
mv "$fixture/Contents/MacOS/Kelpie" "$fixture/Contents/MacOS/KelpieAddressVerification"
codesign --force --deep --sign - "$fixture"
open -n "$fixture" --args -hideWelcomeCard YES -sessionTabs '' -sessionTabURLs '()' --port 18475
cd "$root"
status=0
xcodebuild -workspace apps/macos/Kelpie.xcworkspace -scheme KelpieEmbeddingUITests \
    -configuration Debug -destination platform=macOS,arch=arm64 \
    -derivedDataPath "${KELPIE_UI_DERIVED_DATA:-$root/.cache/address-ui-derived}" -jobs 2 \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ONLY_ACTIVE_ARCH=YES \
    -resultBundlePath "$result" -only-testing:KelpieEmbeddingUITests/DesktopAddressUITests test || status=$?
xcrun xcresulttool export attachments --path "$result" --output-path "$result.attachments"
exit "$status"
