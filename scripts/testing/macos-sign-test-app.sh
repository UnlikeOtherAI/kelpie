#!/bin/bash
# Ad-hoc test identity on an isolated hosted runner, never release signing.
set -euo pipefail
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_OS:-}" = macOS
app="apps/macos/.build/Build/Products/Debug/Kelpie.app"
test -d "$app"
framework="$app/Contents/Frameworks/Chromium Embedded Framework.framework"
# Sign nested Mach-O libraries before their containing framework and helper apps.
while IFS= read -r -d '' library; do
  codesign --force --sign - --timestamp=none "$library"
done < <(find "$framework" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
codesign --force --sign - --timestamp=none "$framework"
while IFS= read -r -d '' helper; do
  codesign --force --sign - --timestamp=none \
    --entitlements apps/macos/KelpieHelper/KelpieHelper.entitlements "$helper"
done < <(find "$app/Contents/Frameworks" -maxdepth 1 -type d -name '*Helper*.app' -print0)
codesign --force --sign - --timestamp=none --entitlements apps/macos/Kelpie/Kelpie.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
