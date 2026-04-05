# Task 14: End-to-End Integration Tests

**Component:** All
**Depends on:** Tasks 09, 11, 13
**Estimated size:** ~500 lines

## Goal

Verify the complete pipeline works: CLI discovers devices, sends commands, receives responses, and AppReveal validates app state. Tests run against Simulators and Emulators.

## Files to Create

```
packages/cli/tests/
  e2e/
    setup.ts                      # Test helpers: launch simulators, wait for mDNS
    discovery.e2e.test.ts         # CLI discovers Simulator/Emulator devices
    navigation.e2e.test.ts        # Navigate, screenshot, verify URL
    interaction.e2e.test.ts       # Click, fill, verify DOM changes
    group.e2e.test.ts             # Group commands across multiple simulators
    mcp.e2e.test.ts               # MCP server tool invocation
    appreveal.e2e.test.ts         # Use AppReveal to validate app state

docs/testing.md                   # Testing setup guide
```

## Test Environment Setup

### Prerequisites

- Xcode with iOS Simulators
- Android Studio with Emulators
- `adb forward` for Android Emulator port mapping
- Kelpie apps built and installed on simulators/emulators

### Setup Helper (`e2e/setup.ts`)

```typescript
// Launch iOS Simulator with Kelpie app
async function launchIOSSimulator(deviceType: string): Promise<Device>

// Launch Android Emulator with Kelpie app
async function launchAndroidEmulator(avd: string): Promise<Device>

// Wait for mDNS discovery of N devices
async function waitForDevices(count: number, timeout: number): Promise<Device[]>

// Connect to AppReveal on a device for state verification
async function connectAppReveal(device: Device): Promise<AppRevealClient>
```

### AppReveal Integration for Testing

AppReveal MCP tools used for test verification:
- `screenshot` — capture app state for visual verification
- `get_screen` — verify which screen is active
- `get_elements` — verify UI element state
- `get_state` — verify app internal state
- `get_navigation_stack` — verify navigation state
- `get_webviews` — verify WebView URL and state

## Test Scenarios

### Discovery (`discovery.e2e.test.ts`)

1. Launch 2 Simulators with Kelpie
2. Run `kelpie discover` — verify both devices found
3. Verify device metadata: name, platform, resolution, version
4. Run `kelpie ping` — verify both reachable
5. Kill one Simulator — verify `ping` reports it unreachable

### Navigation (`navigation.e2e.test.ts`)

1. `kelpie navigate "https://example.com" --device <sim>`
2. `kelpie url --device <sim>` — verify URL matches
3. `kelpie screenshot --device <sim>` — verify file exists and is valid PNG
4. Use AppReveal `get_webviews` to confirm WebView URL matches
5. `kelpie back` / `kelpie forward` — verify history navigation

### Interaction (`interaction.e2e.test.ts`)

1. Navigate to a form page
2. `kelpie fill "#email" "test@example.com"` — verify value set
3. `kelpie click "#submit"` — verify navigation or DOM change
4. `kelpie a11y` — verify accessibility tree reflects page state
5. Use AppReveal to verify app didn't crash

### Group Commands (`group.e2e.test.ts`)

1. Launch 2+ Simulators
2. `kelpie group navigate "https://example.com"` — verify all navigate
3. `kelpie group screenshot --output ./test/` — verify one file per device
4. `kelpie group find-button "Submit"` — verify found/notFound response
5. `kelpie group fill "#email" "test@test.com"` — verify all filled

### MCP (`mcp.e2e.test.ts`)

1. Start `kelpie mcp` in background
2. Send MCP `kelpie_discover` tool call
3. Send MCP `kelpie_navigate` with device and URL
4. Send MCP `kelpie_screenshot` — verify response
5. Send MCP `kelpie_group_find_button` — verify aggregated response

### AppReveal Validation (`appreveal.e2e.test.ts`)

1. Connect to Kelpie app via AppReveal MCP
2. `get_screen` — verify browser screen is active
3. `get_elements` — verify URL bar, WebView, settings button exist
4. Navigate via Kelpie CLI — then `get_webviews` via AppReveal to confirm
5. Open settings panel via AppReveal `tap_element` — verify settings fields
6. `screenshot` via AppReveal — verify app chrome renders correctly

## Documentation (`docs/testing.md`)

Write a testing guide covering:
- How to set up Simulators/Emulators for testing
- How to run E2E tests
- AppReveal usage for app state verification
- How to debug test failures

## Acceptance Criteria

- [ ] E2E tests discover real Simulator/Emulator devices via mDNS
- [ ] Navigation test: CLI navigates, device responds, URL matches
- [ ] Screenshot test: file saved, valid PNG, correct dimensions
- [ ] Interaction test: fill + click produces expected DOM state
- [ ] Group test: commands sent to multiple devices, aggregated results correct
- [ ] MCP test: stdio MCP server responds to tool calls correctly
- [ ] AppReveal test: can discover Kelpie app, take screenshots, inspect elements
- [ ] AppReveal verification: app state matches after CLI commands
- [ ] Tests handle device startup time gracefully (retries, timeouts)
- [ ] `docs/testing.md` explains full setup and usage
- [ ] All E2E tests pass with at least one iOS Simulator OR one Android Emulator

---

- [ ] **Have you run an adversarial review with Codex?**
