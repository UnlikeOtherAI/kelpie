# Mollotov -- Testing Guide

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

E2E tests verify the full CLI-to-device pipeline. They send real HTTP requests to Mollotov running on a Simulator or Emulator.

### Prerequisites

1. Build and install Mollotov on a target device
2. The device's HTTP server must be reachable from the test machine

### Option A: iOS Simulator

```bash
# Build and install
cd apps/ios
xcodebuild -scheme Mollotov -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Launch simulator and app
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl launch booted com.unlike-other-ai.mollotov
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
MOLLOTOV_TEST_HOST=192.168.1.50 MOLLOTOV_TEST_PORT=8420 pnpm test:e2e
```

Tests auto-skip when no device is reachable. The test output shows which tests ran and which were skipped.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MOLLOTOV_TEST_HOST` | `localhost` | IP or hostname of the test device |
| `MOLLOTOV_TEST_PORT` | `8420` | HTTP server port |

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
xcodebuild -scheme Mollotov -sdk iphonesimulator \
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
