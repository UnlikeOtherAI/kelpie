# Kelpie -- Testing Guide

## Test Types

| Type | Location | Runs against | Command |
|------|----------|-------------|---------|
| Unit tests | `packages/cli/tests/{client,commands,discovery,group,help,mcp}/` | Mocks | `pnpm test` |
| E2E tests | `packages/cli/tests/e2e/` | Real devices | `pnpm test:e2e` |

## Running Unit Tests

```bash
cd packages/cli
pnpm build && pnpm test
```

All unit tests use mocked HTTP (`vi.fn()` on `globalThis.fetch`) and run without devices.

## Running E2E Tests

E2E tests verify the full CLI-to-device pipeline. They send real HTTP requests to Kelpie running on a Simulator or Emulator.

### Prerequisites

1. Build and install Kelpie on a target device
2. The device's HTTP server must be reachable from the test machine

### Option A: iOS Simulator

```bash
# Build and install
cd apps/ios
xcodebuild -scheme Kelpie -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Launch simulator and app
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl launch booted com.unlike-other-ai.kelpie
```

### Option B: Android Emulator

```bash
# Build and install
cd apps/android
./gradlew installDebug

# If using emulator, forward the port
adb forward tcp:8420 tcp:8420
```

### Running

```bash
cd packages/cli

# Against localhost (Simulator/Emulator with port forwarding)
pnpm test:e2e

# Against a specific device
KELPIE_TEST_HOST=192.168.1.50 KELPIE_TEST_PORT=8420 pnpm test:e2e
```

Tests auto-skip when no device is reachable. The test output shows which tests ran and which were skipped.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KELPIE_TEST_HOST` | `localhost` | IP or hostname of the test device |
| `KELPIE_TEST_PORT` | `8420` | HTTP server port |

## E2E Test Coverage

| Suite | What it tests |
|-------|--------------|
| `discovery.e2e` | Health endpoint, device info, capabilities, viewport, error handling |
| `navigation.e2e` | Navigate, URL verification, screenshot, reload, back/forward |
| `interaction.e2e` | DOM queries, click, evaluate, scroll, wait-for-element |
| `llm-endpoints.e2e` | Accessibility tree, visible elements, page text, find, shadow DOM |
| `browser-management.e2e` | Cookies, storage, console, network log, mutations, iframes, tabs, clipboard |
| `mcp.e2e` | MCP tool count verification, standard method responses |

## Debugging Test Failures

1. Verify the device is reachable: `curl http://localhost:8420/health`
2. Check device logs for errors (Xcode Console or `adb logcat`)
3. Run a single test: `pnpm vitest run tests/e2e/navigation.e2e.test.ts`
4. Increase timeout in `setup.ts` if device is slow to respond

## iOS Build Verification

```bash
cd apps/ios
xcodebuild -scheme Kelpie -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Android Build Verification

```bash
cd apps/android
./gradlew assembleDebug
```

## CLI Build + Unit Tests

```bash
cd packages/cli
pnpm build && pnpm test
```

## Windows build and package

Windows releases use the pinned CEF 152 minimal SDK. Run scripts/download-cef-windows.ps1,
scripts/build-windows.ps1, then scripts/package-windows.ps1. The download verifies both
pinned SHA-256 and SHA-1. The build requires VS2022 C++ Build Tools, Windows SDK, CMake,
and Ninja; it uses C++20, the static MSVC CRT, USE_SANDBOX=ON, and CTest.

The SDK archive is extracted with `cmake -E tar`, not `tar.exe`. Windows' own tar depends on
the Windows build: the windows-2022 CI image's bsdtar 3.8.4 has no bzip2 of its own, hands the
`.tar.bz2` to an external `bzip2`, and never finished. CMake's bundled libarchive extracts it
in about 16 s there. CTest gives any test without its own `TIMEOUT` 120 s, so a hang fails with
the test's name. A green Windows CI run takes about 9.5 minutes, and the Windows CI and release
jobs stop after 30. Each build stage prints a `==>` line, so a stalled job shows where it
stopped.

The ZIP contains only the CEF runtime, locales, licenses, unchanged CEF bootstrap
kelpie.exe, and Kelpie's kelpie.dll. Packaging rejects missing RunWinMain, non-x64 DLLs,
or absent/mismatched 0.1.3 DLL resource versions. It writes uniquely named SHA-256 and
provenance sidecars. Signing happens after deterministic resource stamping when a
certificate is supplied; no certificate is assumed here. Use the approved Windows
release acceptance command documented above; CI packaging does not bypass a locally
rejected browser launch.

## Native iOS browser chrome

Generate `apps/ios` with Tuist and run the Kelpie scheme on both an iPhone and
an iPad simulator. `BrowserChromeScrollTests` covers user motion, rubber-band
bounds, programmatic offsets and layout changes. `BrowserChromeUITests` exercises
collapse, tap-to-expand, keyboard clearance, upward overview entry, horizontal
card dismissal and selection. On iPad it additionally creates overflowing tabs
and closes the active tab. Screenshot attachments are retained in the xcresult.
The tests use a self-contained data-URL page and UserDefaults launch overrides;
they do not depend on live websites or change the person's persisted settings.

For interactive verification, build Debug with
`SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG APPREVEAL_ENABLED"`. AppReveal exposes
a dynamic `_appreveal._tcp` endpoint; inspect its `launch_context` to confirm
Kelpie's bundle, version and simulator before using its screenshot and UI tools.
Release builds omit AppReveal. Browser chrome owns safe-area clearance and
fixed WebView geometry; compare expanded/collapsed screenshots and test
vertical grid scrolling as well as horizontal tab dismissal.
