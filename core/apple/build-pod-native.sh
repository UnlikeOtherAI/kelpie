#!/bin/bash
set -euo pipefail
if [ "${KELPIE_APPLE_POD_CLEAN_ENV:-}" != 1 ]; then
    exec env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
        DEVELOPER_DIR="$(xcode-select -p)" PODS_TARGET_SRCROOT="$PODS_TARGET_SRCROOT" \
        PODS_CONFIGURATION_BUILD_DIR="$PODS_CONFIGURATION_BUILD_DIR" PLATFORM_NAME="$PLATFORM_NAME" ARCHS="$ARCHS" \
        KELPIE_APPLE_POD_CLEAN_ENV=1 /bin/bash "$0" "$@"
fi
case "$PLATFORM_NAME" in iphoneos|iphonesimulator) ;; *) echo "Kelpie's source Pod requires iOS" >&2; exit 2 ;; esac
out="$PODS_CONFIGURATION_BUILD_DIR/KelpieBrowser/Native"
mkdir -p "$out"
archives=()
for arch in $ARCHS; do
    case "$arch" in arm64|x86_64) ;; *) exit 2 ;; esac
    binary="$out/$arch/libKelpieNative.a"
    bash "$PODS_TARGET_SRCROOT/build-native.sh" "$PLATFORM_NAME" "$arch" "$out/$arch/build" "$binary"
    archives+=("$binary")
done
[ "${#archives[@]}" -gt 0 ] || exit 2
xcrun lipo -create "${archives[@]}" -output "$out/libKelpieNative.a"
