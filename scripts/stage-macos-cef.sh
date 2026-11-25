#!/bin/bash
# Stage the pinned framework and its subprocess bundles for a Mac browser host.
set -euo pipefail
[ "$#" -eq 5 ] || exit 2
CEF_SRC="$1"
HELPER_EXE="$2"
HELPER_ROOT="$3"
helper_id="$4"
bundle_version="$5"
script_dir="$(cd "$(dirname "$0")" && pwd)"
case "$HELPER_ROOT" in /*) ;; *) exit 2 ;; esac
test -n "$helper_id" && test -n "$bundle_version" && test -x "$HELPER_EXE"
test -f "$CEF_SRC/Chromium Embedded Framework"
CEF_DST="$HELPER_ROOT/Chromium Embedded Framework.framework"
mkdir -p "$HELPER_ROOT"
rm -rf "$CEF_DST"
mkdir -p "$CEF_DST/Versions/A"
cp "$CEF_SRC/Chromium Embedded Framework" "$CEF_DST/Versions/A/"
rsync -a "$CEF_SRC/Resources/" "$CEF_DST/Versions/A/Resources/"
if [ -d "$CEF_SRC/Libraries" ]; then
  rsync -a "$CEF_SRC/Libraries/" "$CEF_DST/Versions/A/Libraries/"
  ln -sf Versions/Current/Libraries "$CEF_DST/Libraries"
fi
ln -sf A "$CEF_DST/Versions/Current"
ln -sf "Versions/Current/Chromium Embedded Framework" "$CEF_DST/Chromium Embedded Framework"
ln -sf Versions/Current/Resources "$CEF_DST/Resources"
# Reconstructing the versioned framework changes its resource layout. Seal
# that final bundle before Xcode signs the containing app.
if [ "${CODE_SIGNING_ALLOWED:-NO}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY:-}" != "-" ]; then
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:-}" "$CEF_DST"
fi

test -x "$HELPER_EXE"

stage_helper() {
  local helper_name="$1"
  local bundle_id="$2"
  local app_dir="${HELPER_ROOT}/${helper_name}.app"
  local exe_dir="${app_dir}/Contents/MacOS"
  local exe_path="${exe_dir}/${helper_name}"
  local plist_path="${app_dir}/Contents/Info.plist"

  mkdir -p "$exe_dir"
  cp "$HELPER_EXE" "$exe_path"

  /usr/libexec/PlistBuddy -c "Clear dict" "$plist_path" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${helper_name}" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${bundle_id}" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${helper_name}" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${bundle_version}" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist_path"

  install_name_tool -change \
    "@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
    "@executable_path/../../../Chromium Embedded Framework.framework/Chromium Embedded Framework" \
    "$exe_path"

  if [ "${CODE_SIGNING_ALLOWED:-NO}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY:-}" != "-" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:-}" --entitlements "${script_dir}/../core/apple/Helpers/KelpieHelper.entitlements" "$app_dir"
  fi
}

rm -rf \
  "${HELPER_ROOT}/Kelpie Helper.app" \
  "${HELPER_ROOT}/Kelpie Helper (Renderer).app" \
  "${HELPER_ROOT}/Kelpie Helper (GPU).app" \
  "${HELPER_ROOT}/Kelpie Helper (Plugin).app" \
  "${HELPER_ROOT}/Kelpie Helper (Alerts).app"

stage_helper "Kelpie Helper" "${helper_id}"
stage_helper "Kelpie Helper (Renderer)" "${helper_id}.renderer"
stage_helper "Kelpie Helper (GPU)" "${helper_id}.gpu"
stage_helper "Kelpie Helper (Plugin)" "${helper_id}.plugin"
stage_helper "Kelpie Helper (Alerts)" "${helper_id}.alerts"
