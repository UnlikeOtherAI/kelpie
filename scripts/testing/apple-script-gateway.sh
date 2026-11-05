#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p .cache
artifacts="$(mktemp -d "$root/.cache/apple-gateway-XXXXXX")"
mkdir "$artifacts/tmp"
export TMPDIR="$artifacts/tmp"
nice -n 10 xcrun swiftc -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$artifacts/module-cache" -O -j 1 -num-threads 1 -parse-as-library \
  apps/macos/Kelpie/Network/ScriptGatewayPolicy.swift \
  apps/macos/Kelpie/Handlers/ScriptArtifactStore.swift \
  apps/macos/Kelpie/Handlers/ScriptCaptureError.swift \
  tests/apple/script-gateway-policy.swift -o "$artifacts/acceptance"
nice -n 10 "$artifacts/acceptance" "$artifacts/run"
printf 'Artifacts: %s\n' "$artifacts"
