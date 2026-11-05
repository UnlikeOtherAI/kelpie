#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p .cache
artifacts="$(mktemp -d "$root/.cache/apple-deadline-XXXXXX")"
nice -n 10 xcrun swiftc -target "$(uname -m)-apple-macos14.0" -parse-as-library -j 1 \
  -module-cache-path "$artifacts/module-cache" \
  apps/macos/Kelpie/Handlers/ScriptCaptureDeadline.swift tests/apple/script-deadline.swift \
  -o "$artifacts/acceptance"
nice -n 10 "$artifacts/acceptance"
