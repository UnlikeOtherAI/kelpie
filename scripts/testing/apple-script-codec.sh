#!/usr/bin/env bash
# Reproducible standalone codec acceptance; no app, simulator, device or native build cache mutation.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p .cache
artifacts="$(mktemp -d "$root/.cache/apple-codec-XXXXXX")"
mkdir "$artifacts/tmp"
export TMPDIR="$artifacts/tmp"
target="$(uname -m)-apple-macos14.0"
nice -n 10 xcrun clang++ -target "$target" -std=c++17 -I native/core-automation/include \
  -c native/core-automation/src/script_presentation.cpp -o "$artifacts/presentation.o"
nice -n 10 xcrun swiftc -target "$target" -module-cache-path "$artifacts/module-cache" -O -j 1 -num-threads 1 -parse-as-library \
  -import-objc-header native/core-automation/include/kelpie/script_presentation.h \
  apps/macos/Kelpie/Handlers/ScriptCaptureError.swift \
  apps/macos/Kelpie/Handlers/ScriptCaptureBudget.swift \
  apps/macos/Kelpie/Handlers/ScriptGIFEncoder.swift \
  apps/macos/Kelpie/Handlers/ScriptImageEncoder.swift \
  apps/macos/Kelpie/Handlers/ScriptVideoWriter.swift \
  apps/macos/Kelpie/Handlers/ScriptVideoSegmentSink.swift \
  apps/macos/Kelpie/Handlers/ScriptArtifactStore.swift \
  apps/macos/Kelpie/Handlers/ScriptOverlayDrawing.swift \
  tests/apple/script-codec.swift "$artifacts/presentation.o" -lc++ -o "$artifacts/acceptance"
nice -n 10 /usr/bin/time -l "$artifacts/acceptance" "$artifacts/run"
printf 'Artifacts: %s\n' "$artifacts"
