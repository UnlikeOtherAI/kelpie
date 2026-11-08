#!/bin/bash
# Build a WebKit-only consumer SDK, including the existing six native libraries.
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <macosx|iphoneos|iphonesimulator> <arm64|x86_64> <new-output-directory>" >&2
    exit 2
fi
sdk="$1"
arch="$2"
out="$3"
case "$sdk:$arch" in
    macosx:arm64|macosx:x86_64|iphoneos:arm64|iphonesimulator:arm64|iphonesimulator:x86_64) ;;
    *) echo "Unsupported Apple SDK/architecture" >&2; exit 2 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd)"
case "$out" in /*) ;; *) echo "Output directory must be absolute" >&2; exit 2 ;; esac
if [ -e "$out" ]; then echo "Output already exists: $out" >&2; exit 2; fi
revision="$(git -C "$root" rev-parse HEAD)"
build="$root/core/native/.build-sdk-$sdk-$arch"
derived="$root/core/apple/.build-sdk-$sdk-$arch"
products="$derived/products"
mkdir -p "$build" "$derived" "$(dirname "$out")"
args=(-DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$sdk" --show-sdk-path)"
    -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DKELPIE_BUILD_DESKTOP_ENGINES=OFF -DKELPIE_LOCAL_LLM=ON)
if [ "$sdk" = macosx ]; then
    target=KelpieBrowserMac
    minimum=14.0
    args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET="$minimum" -DKELPIE_LOCAL_LLM_METAL=ON)
else
    target=KelpieBrowserIOS
    minimum=16.0
    args+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET="$minimum")
fi
cmake -S "$root/core/native" -B "$build" -G Ninja "${args[@]}"
cmake --build "$build" --parallel 2

# The Mac Swift inference layer uses the same pinned llama C API as the core.
# These are build-only imports; none enter the browser's public Swift interface.
headers="$build/swift-llama"
mkdir -p "$headers"
cp "$build/_deps/kelpie_llama-src/include/llama.h" "$headers/"
cp "$build/_deps/kelpie_llama-src/ggml/include/"*.h "$headers/"
printf 'module llama [system] { header "llama.h" export * }\n' > "$headers/module.modulemap"
TUIST_KELPIE_WEBKIT_ONLY=true tuist generate --path "$root/core/apple" --no-open
xcodebuild -project "$root/core/apple/KelpieBrowser.xcodeproj" -scheme "$target" \
    -configuration Release -sdk "$sdk" -arch "$arch" -jobs 2 \
    -derivedDataPath "$derived" CONFIGURATION_BUILD_DIR="$products" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
    "HEADER_SEARCH_PATHS=$root/core/native/core-protocol/include $headers" \
    "SWIFT_INCLUDE_PATHS=$root/core/apple/Native $headers" build

stage="$derived/package-$revision"
if [ -e "$stage" ]; then echo "Staging directory already exists: $stage" >&2; exit 2; fi
framework="$stage/KelpieBrowser.framework"
mkdir -p "$framework/Modules"
archives=("$products/lib$target.a")
for module in state connect protocol automation mcp ai; do
    archives+=("$build/core-$module/libkelpie_core_$module.a")
done
for library in llama ggml ggml-base ggml-cpu; do
    found="$(find "$build/_deps/kelpie_llama-build" -name "lib$library.a" -type f)"
    if [ -z "$found" ] || [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" != 1 ]; then
        echo "Expected exactly one native archive for $library" >&2; exit 1
    fi
    archives+=("$found")
done
if [ "$sdk" = macosx ]; then
    archives+=("$build/_deps/kelpie_llama-build/ggml/src/ggml-metal/libggml-metal.a")
fi
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
