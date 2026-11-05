# macOS native build

The app uses Tuist and the repository's native CMake bootstrap. Do not edit or commit generated Xcode projects, copy unidentified vendor libraries, or raise the deployment target to make a build pass.

## Prerequisites

Use an Apple Silicon Mac, Xcode with a macOS26 SDK or newer, CMake, Ninja, Node20+, pnpm, mise and SwiftLint. The app deployment target remains macOS14. Tuist is pinned by the root .mise.toml.

The CI job uses the stable [GitHub macos-26 ARM64 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), whose documented default is Xcode 26.6. The pinned CEF bootstrap is ARM64-only. The job prints its actual toolchain and refuses a different architecture.

## Bootstrap and build

AppReveal is public and pinned to the committed source used by the local compiled candidate:

```sh
git init vendor/AppReveal
git -C vendor/AppReveal remote add origin https://github.com/UnlikeOtherAI/AppReveal.git
git -C vendor/AppReveal fetch --depth 1 origin 3a28e56e5e72aa2a1f0b241cac63140e5906c8b4
git -C vendor/AppReveal checkout --detach FETCH_HEAD
bash scripts/download-cef.sh macos
make lint-swift
cmake -S native -B native/.build -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DKELPIE_BUILD_DESKTOP_ENGINES=OFF \
  -DKELPIE_LOCAL_LLM=ON \
  -DKELPIE_AI_USE_HTTPLIB=OFF \
  -DBUILD_TESTING=ON
cmake --build native/.build --parallel 1 --target \
  kelpie_core_state kelpie_core_connect kelpie_core_protocol \
  kelpie_core_automation kelpie_core_mcp kelpie_core_ai
(cd apps/macos && mise exec -- tuist generate --no-open)
xcodebuild -workspace apps/macos/Kelpie.xcworkspace -scheme Kelpie \
  -configuration Debug -derivedDataPath apps/macos/.build -jobs 1 \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

These are bootstrap commands for a fresh worktree; preserve an existing vendor checkout rather than overwriting it. Native configuration installs frozen pnpm dependencies and regenerates the canonical browser contract. It downloads llama source8345f333951c661d166b00e6f9362e553768f292 through the existing FetchContent definition. Darwin enables CPU, Metal and Accelerate; other platforms retain their existing defaults.

Project.swift links the core libraries and llama/ggml outputs under native/.build. The permanent Kelpie/AI/Llama/module.modulemap exposes those pinned headers to Swift. No apps/macos/vendor/llama.cpp tree is needed. The existing CEF download script supplies framework149.0.6 and matching headers; do not reuse framework148 with those headers.

## Scope and known diagnostics

The local macOS27 candidate passed full Swift lint, native core/inference compilation, Tuist generation and app/XCTest build-for-testing. The [hosted run 41950256231](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41950256231) also passed at revision 28426edc2fe9faffefea4a3df508786d5107bc15 using Xcode 26.6 (17F113), macOS SDK 26.5, CEF 149.0.6 and native Metal/BLAS ON. The scope job took 6 seconds and the native job 8 minutes 10 seconds. This compiles XCTest without executing tests or launching Kelpie.

The build emits known warnings in existing AppReveal concurrency declarations, native categories/callbacks, deprecated UI calls and script phases without output declarations. An absent optional Gecko helper also produces a warning; the checked renderer paths are WebKit and Chromium. The workflow retains build diagnostics and does not claim zero warnings or turn off diagnostics.

Build-for-testing compiles tests without launching an app or simulator. CODE_SIGNING_ALLOWED=NO is only a compile-check setting: it does not create a signed release or prove installed behavior. This job adds no runtime sandbox bypass, changes no mocked-keychain setting and publishes no app artifact. Runtime tests, owner-authorized app replacement, supported native UI/MCP/CLI flows, release signing, installation and inference smoke remain separate requirements.

## CI change scope

The workflow always runs a small Ubuntu change detector and its regression cases. The native job runs only when that detector identifies macOS source/tests, Tuist settings, linked core libraries, shared generated-contract source/build configuration, canonical pnpm bootstrap inputs, CEF/native generators or this CI configuration. Desktop-engine-only changes are excluded because this macOS graph configures KELPIE_BUILD_DESKTOP_ENGINES=OFF. Documentation, unrelated app/CLI/admin changes and shared tests outside tsconfig.build.json do not start a native build.

Pull requests compare merge-base to head; main pushes compare before/after and preserve both rename endpoints. A first push checks its tree. A manual dispatch explicitly requests the build. Failed Git comparison fails detection rather than silently skipping. GitHub reports conditionally skipped jobs as successful checks, preserving required-check behavior for unrelated-only changes. See [GitHub job conditions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions).

Reproduce the lightweight scope tests with python3 -m unittest discover -s tests/ci -p test_macos_inputs.py. The hosted compile result above covers its exact recorded revision. Later native-input changes require their own checks; installed runtime behavior remains separately tracked.
