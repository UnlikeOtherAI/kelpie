#!/bin/bash
# Ad-hoc test identity on an isolated hosted runner, never release signing.
set -euo pipefail
if [[ "$#" -eq 2 && "$1" = --preflight-copy ]]; then
  app="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$2")"
  case "$app" in
    "$PWD"/.cache/mac-sign-preflight-*/Kelpie.app) ;;
    *) echo 'Signing preflight requires an owned ignored copy' >&2; exit 2 ;;
  esac
else
  test "$#" -eq 0
  test "${GITHUB_ACTIONS:-}" = true
  test "${RUNNER_OS:-}" = macOS
  app="apps/macos/.build/Build/Products/Debug/Kelpie.app"
fi
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
# build-for-testing embeds an unsigned XCTest bundle; its resource envelope
# must be sealed before the containing app. Linker ad-hoc code signatures alone
# do not sign that bundle's Info.plist/resources.
while IFS= read -r -d '' library; do
  codesign --force --sign - --timestamp=none "$library"
done < <(find "$app/Contents/MacOS" -maxdepth 1 -type f -name '*.dylib' -print0)
if test -d "$app/Contents/PlugIns"; then
  while IFS= read -r -d '' bundle; do
    codesign --force --sign - --timestamp=none "$bundle"
  done < <(find "$app/Contents/PlugIns" -maxdepth 1 -type d -name '*.xctest' -print0)
fi
codesign --force --sign - --timestamp=none --entitlements apps/macos/Kelpie/Kelpie.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
