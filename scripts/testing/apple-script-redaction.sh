#!/usr/bin/env bash
# Checks the thin Swift -> canonical C ABI binding without an app, simulator or native build-cache mutation.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
: "${NLOHMANN_JSON_INCLUDE_DIR:?Set the read-only pinned nlohmann 3.11.3 include directory}"
macros="$NLOHMANN_JSON_INCLUDE_DIR/nlohmann/detail/abi_macros.hpp"
grep -Eq '^#define NLOHMANN_JSON_VERSION_MAJOR 3 ' "$macros"
grep -Eq '^#define NLOHMANN_JSON_VERSION_MINOR 11 ' "$macros"
grep -Eq '^#define NLOHMANN_JSON_VERSION_PATCH 3 ' "$macros"
mkdir -p .cache
artifacts="$(mktemp -d "$root/.cache/apple-redaction-XXXXXX")"
mkdir "$artifacts/tmp"
export TMPDIR="$artifacts/tmp"
target="$(uname -m)-apple-macos14.0"
for source in script_redaction script_redaction_c_api; do
  nice -n 10 xcrun clang++ -target "$target" -std=c++17 -O2 \
    -I native/core-automation/include -I "$NLOHMANN_JSON_INCLUDE_DIR" \
    -c "native/core-automation/src/$source.cpp" -o "$artifacts/$source.o"
done
nice -n 10 xcrun swiftc -target "$target" -module-cache-path "$artifacts/mac-module-cache" \
  -O -j 1 -num-threads 1 -parse-as-library \
  -import-objc-header native/core-automation/include/kelpie/script_redaction.h \
  apps/macos/Kelpie/Handlers/ScriptOutputRedaction.swift tests/apple/script-redaction.swift \
  "$artifacts/script_redaction.o" "$artifacts/script_redaction_c_api.o" -lc++ -o "$artifacts/acceptance"
nice -n 10 "$artifacts/acceptance"
nice -n 10 xcrun --sdk iphonesimulator swiftc \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios16.0-simulator \
  -module-cache-path "$artifacts/ios-module-cache" -typecheck \
  -import-objc-header native/core-automation/include/kelpie/script_redaction.h \
  apps/macos/Kelpie/Handlers/ScriptOutputRedaction.swift
printf 'Artifacts: %s\n' "$artifacts"
