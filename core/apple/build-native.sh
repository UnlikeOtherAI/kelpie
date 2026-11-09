#!/bin/bash
# Shared C++ build for standalone SDK packages and source Pod consumers.
set -euo pipefail
if [ "${KELPIE_APPLE_NATIVE_CLEAN_ENV:-}" != 1 ]; then
    exec env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" PATH="$PATH" \
        TMPDIR="${TMPDIR:-/tmp}" DEVELOPER_DIR="$(xcode-select -p)" KELPIE_APPLE_NATIVE_CLEAN_ENV=1 \
        /bin/bash "$0" "$@"
fi
if [ "$#" -ne 4 ]; then echo "Usage: $0 <sdk> <architecture> <absolute-build-directory> <absolute-native-archive>" >&2; exit 2; fi
sdk="$1"
arch="$2"
build="$3"
archive="$4"
case "$sdk:$arch" in macosx:arm64|macosx:x86_64|iphoneos:arm64|iphonesimulator:arm64|iphonesimulator:x86_64) ;; *) exit 2 ;; esac
case "$build:$archive" in /*:/*) ;; *) exit 2 ;; esac
[ ! -L "$archive" ] || exit 2
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p "$build" "$(dirname "$archive")"
args=(-DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$sdk" --show-sdk-path)"
    -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DKELPIE_BUILD_DESKTOP_ENGINES=OFF -DKELPIE_LOCAL_LLM=ON)
if [ "$sdk" = macosx ]; then
    args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DKELPIE_LOCAL_LLM_METAL=ON)
else
    args+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DKELPIE_LOCAL_LLM_METAL=OFF)
fi
cmake -S "$root/core/native" -B "$build" -G Ninja "${args[@]}"
cmake --build "$build" --parallel 2
archives=()
for module in state connect protocol automation mcp ai sync; do archives+=("$build/core-$module/libkelpie_core_$module.a"); done
for library in llama ggml ggml-base ggml-cpu; do
    found="$(find "$build/_deps/kelpie_llama-build" -name "lib$library.a" -type f)"
    if [ -z "$found" ] || [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" != 1 ]; then
        echo "Expected exactly one native archive for $library" >&2; exit 1
    fi
    archives+=("$found")
done
if [ "$sdk" = macosx ]; then archives+=("$build/_deps/kelpie_llama-build/ggml/src/ggml-metal/libggml-metal.a"); fi
xcrun libtool -static -o "$archive" "${archives[@]}"
