#!/bin/bash
# Build the complete consumer SDK for the selected distribution.
set -euo pipefail

# Build tools receive paths and platform selection, never the developer's credential environment.
if [ "${KELPIE_APPLE_SDK_CLEAN_ENV:-}" != 1 ]; then
    exec env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" PATH="$PATH"         TMPDIR="${TMPDIR:-/tmp}" DEVELOPER_DIR="$(xcode-select -p)" KELPIE_APPLE_SDK_CLEAN_ENV=1         /bin/bash "$0" "$@"
fi

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <macosx|iphoneos|iphonesimulator> <arm64|x86_64> <new-output-directory> [webkit|chromium]" >&2
    exit 2
fi
sdk="$1"
arch="$2"
out="$3"
engines="${4:-webkit}"
case "$engines" in webkit) webkit=true ;; chromium) [ "$sdk" = macosx ]; webkit=false ;; *) exit 2 ;; esac
case "$sdk:$arch" in
    macosx:arm64|macosx:x86_64|iphoneos:arm64|iphonesimulator:arm64|iphonesimulator:x86_64) ;;
    *) echo "Unsupported Apple SDK/architecture" >&2; exit 2 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
case "$out" in /*) ;; *) echo "Output directory must be absolute" >&2; exit 2 ;; esac
if [ -e "$out" ]; then echo "Output already exists: $out" >&2; exit 2; fi
revision="$(git -C "$root" rev-parse HEAD)"
build="$root/core/native/.build-sdk-$sdk-$arch"
derived="$root/core/apple/.build/sdk-$sdk-$arch-$engines"
products="$derived/products"
mkdir -p "$build" "$derived" "$(dirname "$out")"
if [ "$sdk" = macosx ]; then target=KelpieBrowserMac; minimum=14.0
else target=KelpieBrowserIOS; minimum=16.0; fi
bash "$root/core/apple/build-native.sh" "$sdk" "$arch" "$build" "$derived/libKelpieNative.a"

# The Mac Swift inference layer uses the same pinned llama C API as the core.
# These are build-only imports; none enter the browser's public Swift interface.
headers="$build/swift-llama"
mkdir -p "$headers"
cp "$build/_deps/kelpie_llama-src/include/llama.h" "$headers/"
cp "$build/_deps/kelpie_llama-src/ggml/include/"*.h "$headers/"
printf 'module llama [system] { header "llama.h" export * }\n' > "$headers/module.modulemap"
includes="$root/core/native/core-protocol/include $headers"
cef_settings=()
if [ "$webkit" = false ]; then
    cef="$derived/cef"
    bash "$root/scripts/prepare-macos-sdk-cef.sh" "$arch" "$cef"
    includes="$includes $cef/cef_include $root/core/apple/macos/Renderer"
    cef_settings=("FRAMEWORK_SEARCH_PATHS=$cef")
fi
TUIST_KELPIE_WEBKIT_ONLY="$webkit" tuist generate --path "$root/core/apple" --no-open
xcodebuild -project "$root/core/apple/KelpieBrowser.xcodeproj" -scheme "$target" \
    -configuration Release -sdk "$sdk" -arch "$arch" -jobs 2 \
    -derivedDataPath "$derived" CONFIGURATION_BUILD_DIR="$products" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
    "HEADER_SEARCH_PATHS=$includes" ${cef_settings[@]+"${cef_settings[@]}"} \
    "SWIFT_INCLUDE_PATHS=$root/core/apple/Native $headers" build

stage="$derived/package-$revision"
if [ -e "$stage" ]; then echo "Staging directory already exists: $stage" >&2; exit 2; fi
framework="$stage/KelpieBrowser.framework"
mkdir -p "$framework/Modules"
archives=("$products/lib$target.a" "$derived/libKelpieNative.a")
xcrun libtool -static -o "$framework/KelpieBrowser" "${archives[@]}"
cp -R "$products/KelpieBrowser.swiftmodule" "$framework/Modules/"
cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.unlikeotherai.kelpie.browser</string>
<key>CFBundleName</key><string>KelpieBrowser</string>
<key>CFBundleExecutable</key><string>KelpieBrowser</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>MinimumOSVersion</key><string>$minimum</string>
</dict></plist>
PLIST
cp -R "$products/KelpieBrowserResources.bundle" "$stage/"
if [ "$webkit" = false ]; then
    xcodebuild -project "$root/core/apple/KelpieBrowser.xcodeproj" -scheme KelpieHelper \
        -configuration Release -sdk macosx -arch "$arch" -jobs 2 -derivedDataPath "$derived" \
        CONFIGURATION_BUILD_DIR="$products" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
        "FRAMEWORK_SEARCH_PATHS=$cef" "HEADER_SEARCH_PATHS=$cef/cef_include" build
    bash "$root/scripts/stage-macos-cef.sh" "$cef/Chromium Embedded Framework.framework" \
        "$products/KelpieHelper" "$stage/Frameworks" 'com.kelpie.browser.helper' 1
fi
printf '%s\n' "$engines" > "$stage/engines.txt"
printf '%s\n' "$revision" > "$stage/revision.txt"
printf '%s\n' "$sdk:$arch" > "$stage/target.txt"
# Compile an unrelated target against only the packaged public module.
printf 'import KelpieBrowser\n' > "$derived/Consumer.swift"
triple="$arch-apple-macos$minimum"
if [ "$sdk" = iphoneos ]; then triple="$arch-apple-ios$minimum"; fi
if [ "$sdk" = iphonesimulator ]; then triple="$arch-apple-ios$minimum-simulator"; fi
xcrun --sdk "$sdk" swiftc -typecheck -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -target "$triple" -F "$stage" "$derived/Consumer.swift"
mv "$stage" "$out"
echo "Apple browser SDK: $out ($revision, $sdk:$arch)"
