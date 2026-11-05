#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p .cache
artifacts="$(mktemp -d "$root/.cache/apple-snapshot-XXXXXX")"
target="$(uname -m)-apple-macos14.0"
nice -n 10 xcrun clang++ -target "$target" -std=c++17 tests/apple/script-source-limits.cpp -o "$artifacts/source-limits"
nice -n 10 "$artifacts/source-limits"
nice -n 10 xcrun swiftc -target "$target" -module-cache-path "$artifacts/module-cache" -parse-as-library -j 1 \
  apps/macos/Kelpie/Handlers/ScriptCaptureViewport.swift tests/apple/script-viewport.swift -o "$artifacts/viewport"
nice -n 10 "$artifacts/viewport"
nice -n 10 xcrun swiftc -target "$target" -module-cache-path "$artifacts/module-cache" -parse-as-library -j 1 \
  apps/macos/Kelpie/Handlers/ScriptCaptureDeadline.swift tests/apple/script-deadline.swift -o "$artifacts/deadline"
nice -n 10 "$artifacts/deadline"
printf 'Artifacts: %s\n' "$artifacts"
