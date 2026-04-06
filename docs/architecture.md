# Kelpie — System Architecture

## Overview

Kelpie is a two-component system: native browser apps on iOS, Android, macOS, and Linux devices and a CLI orchestrator on the developer's machine. All components communicate over the local network via HTTP/JSON. Discovery is automatic via mDNS.

```
                        ┌─────────────┐
                        │     LLM     │
                        │  (Claude,   │
                        │   GPT, etc) │
                        └──────┬──────┘
                               │ MCP / CLI
                        ┌──────┴──────┐
                        │  Kelpie   │
                        │    CLI      │
                        │             │
                        │ ┌─────────┐ │
                        │ │ mDNS    │ │  Discovers devices
                        │ │ Scanner │ │  automatically
                        │ └─────────┘ │
                        │ ┌─────────┐ │
                        │ │ Command │ │  Routes to individual
                        │ │ Router  │ │  or group targets
                        │ └─────────┘ │
                        │ ┌─────────┐ │
                        │ │ MCP     │ │  Exposes CLI as
                        │ │ Server  │ │  MCP tool provider
                        │ └─────────┘ │
                        └──────┬──────┘
                               │ HTTP/JSON
        ┌──────────────────────┼──────────────────────┬──────────────────────┐
        │                      │                      │                      │
┌───────┴────────┐    ┌────────┴───────┐    ┌────────┴───────┐    ┌────────┴────────┐
│  iPhone        │    │  iPad          │    │  Pixel         │    │  Mac            │
│                │    │                │    │                │    │                 │
│ ┌────────────┐ │    │ ┌────────────┐ │    │ ┌────────────┐ │    │ ┌─────────────┐ │
│ │ WKWebView  │ │    │ │ WKWebView  │ │    │ │  WebView   │ │    │ │ WKWebView / │ │
│ └────────────┘ │    │ └────────────┘ │    │ └────────────┘ │    │ │    CEF      │ │
│ ┌────────────┐ │    │ ┌────────────┐ │    │ ┌────────────┐ │    │ └─────────────┘ │
│ │HTTP Server │ │    │ │HTTP Server │ │    │ │HTTP Server │ │    │ ┌─────────────┐ │
│ └────────────┘ │    │ └────────────┘ │    │ └────────────┘ │    │ │ HTTP Server │ │
│ ┌────────────┐ │    │ ┌────────────┐ │    │ ┌────────────┐ │    │ └─────────────┘ │
│ │ MCP Server │ │    │ │ MCP Server │ │    │ │ MCP Server │ │    │ ┌─────────────┐ │
│ └────────────┘ │    │ └────────────┘ │    │ └────────────┘ │    │ │ MCP Server  │ │
│ ┌────────────┐ │    │ ┌────────────┐ │    │ ┌────────────┐ │    │ └─────────────┘ │
│ │mDNS Advert │ │    │ │mDNS Advert │ │    │ │mDNS Advert │ │    │ ┌─────────────┐ │
│ └────────────┘ │    │ └────────────┘ │    │ └────────────┘ │    │ │ mDNS Advert │ │
└────────────────┘    └────────────────┘    └────────────────┘    └───────────────┘
```

For full tech stack details, see [tech-stack.md](tech-stack.md). For browser engine availability by platform and Apple regulatory requirements, see [browser-engines.md](browser-engines.md).

---

## Component Architecture

### 1. Browser App (iOS / Android / macOS / Linux)

Each browser app has four internal layers:

```
┌──────────────────────────────────┐
│           UI Layer               │
│ URL bar │ Browser │ Settings/UI  │
├──────────────────────────────────┤
│        Browser Engine            │
│ WKWebView / WebView / WKWebView │
│ + CEF (macOS)                   │
├──────────────────────────────────┤
│        Command Handler           │
│ Receives HTTP → executes on the  │
│ active renderer via native APIs  │
├──────────────────────────────────┤
│        Network Layer             │
│  HTTP Server │ MCP │ mDNS        │
└──────────────────────────────────┘
```

**UI Layer** — Minimal chrome on mobile, with the URL bar and settings access always visible. On macOS, the browser window adds desktop toolbar controls and a segmented renderer switcher for Safari/WebKit vs Chrome/Chromium. On Linux, the desktop shell offers a GTK URL bar plus floating access to bookmarks, history, network inspection, and settings, with a headless mode that skips the UI entirely. Settings still expose IP address, port, device name, mDNS status, and connection instructions. For details, see [ui/mobile.md](ui/mobile.md).

**Browser Engine** — Platform WebView. All page interaction goes through native APIs:
- iOS: `WKWebView` native methods — `evaluateJavaScript`, `takeSnapshot`, scroll via `scrollView`
- Android: `WebView` + CDP — `DOM.getDocument`, `Page.captureScreenshot`, `Runtime.evaluate`
- macOS: dual renderer stack — `WKWebView` for Safari/WebKit parity and CEF for Chromium/Chrome parity. Both conform to a shared renderer interface so the HTTP and MCP surface stays the same while the active engine changes.
- Linux: CEF-backed Chromium shell when the SDK/runtime is present, with a stub-safe fallback that keeps the HTTP server, mDNS, and persisted state alive when CEF is unavailable.

**Command Handler** — Translates incoming HTTP requests into native browser calls. Android uses CDP for most operations (no scripts enter the page). iOS uses native `evaluateJavaScript` calls and, for features WebKit doesn't expose natively, ephemeral bridge scripts that are cleared on navigation (see [iOS bridge scripts](#ios--no-injection-dom-access)). macOS routes the same handlers through the active renderer and adds `set-renderer` / `get-renderer` so the UI and API can switch engines at runtime.

**Network Layer** — Embedded HTTP server (Swifter/Telegraph on iOS, Ktor on Android, Network.framework-based server on macOS, native socket server on Linux), MCP server over the same transport, and mDNS service advertisement.

### Shared Native Libraries (`native/`)

Cross-platform C++17 static libraries with C ABI, shared by all platforms via bridging headers (Swift) or JNI (Kotlin). Each module lives under `native/core-*` and follows the same pattern: opaque pointer handle, `extern "C"` API, nlohmann_json, CMake build, assert-based tests.

| Module | Purpose |
|--------|---------|
| `core-protocol` | Shared protocol types and JSON helpers |
| `core-state` | Bookmarks, history, network traffic, console stores |
| `core-automation` | Viewport presets and device fitting |
| `core-mcp` | MCP protocol types |
| `core-ai` | AI model catalog, device fitness evaluation, HF token, and shared AI metadata/store helpers |
| `engine-chromium-desktop` | CEF integration (macOS/Linux only) |

**`core-ai`** manages the shareable AI catalog and storage primitives: the approved model catalog (Gemma 4 E2B Q4/Q8), device fitness evaluation, HF token storage, and model-store helpers. Platform networking stays native: Apple apps use URLSession for downloads, Ollama, and HF cloud inference; Linux and Windows keep the cpp-httplib path.

### 2. CLI

```
┌──────────────────────────────────┐
│         CLI Interface            │
│  Commander.js commands + help    │
├──────────────────────────────────┤
│        Command Router            │
│  Individual │ Group │ Smart      │
├──────────────────────────────────┤
│       Device Manager             │
│  Registry │ Health │ Resolution  │
├──────────────────────────────────┤
│        Network Layer             │
│  mDNS Discovery │ HTTP Client    │
├──────────────────────────────────┤
│         MCP Server               │
│  Exposes all CLI commands as     │
│  MCP tools for direct LLM use   │
└──────────────────────────────────┘
```

**CLI Interface** — Commander.js with structured help. Every command includes LLM-readable descriptions with input/output schemas, usage examples, and behavioral notes.

**Command Router** — Three modes:
- **Individual**: Send command to one device by name or IP
- **Group**: Send same command to all (or filtered subset of) devices, collect results
- **Smart**: Commands that query all devices and return filtered results (e.g., `findButton` returns only devices where the element was found)

**Device Manager** — Maintains a live registry of discovered devices. Tracks each device's name, IP, port, platform, resolution, and health status. Provides resolution metadata for resolution-aware commands.

**Network Layer** — mDNS scanner continuously discovers `_kelpie._tcp` services. HTTP client sends commands to individual browser HTTP servers.

**MCP Server** — Wraps all CLI commands as MCP tools. An LLM connected via MCP can discover devices, send commands, and receive results without going through the CLI interface.

---

## Data Flow

### Single Device Command

```
LLM → CLI (kelpie click --device iphone "#submit")
  → Device Manager (resolve "iphone" → 192.168.1.42:8420)
  → HTTP POST 192.168.1.42:8420/v1/click {selector: "#submit"}
  → Browser Command Handler
  → WKWebView.evaluateJavaScript("document.querySelector('#submit')")
  → Native tap at element coordinates
  → HTTP 200 {success: true, element: {tag: "button", text: "Submit"}}
  → CLI formats and returns result
```

### Group Command

```
LLM → CLI (kelpie group navigate "https://example.com")
  → Device Manager (all devices: [iphone, ipad, pixel])
  → Parallel HTTP POST to each /v1/navigate
  → Each browser navigates independently
  → Collect all responses
  → CLI returns aggregated result:
    {devices: [{name: "iphone", status: "ok"}, ...]}
```

### Smart Query

```
LLM → CLI (kelpie group find-button "Submit")
  → Device Manager (all devices)
  → Parallel HTTP POST to each /v1/find-element {text: "Submit", role: "button"}
  → Collect results, filter to found-only
  → CLI returns:
    {found: [{name: "iphone", element: {...}}, {name: "pixel", element: {...}}],
     notFound: [{name: "ipad"}]}
  → LLM decides what to do with the subset
```

### Resolution-Aware Command (scroll2)

```
LLM → CLI (kelpie scroll2 --device iphone "#footer")
  → Device Manager (resolve "iphone" → 192.168.1.42:8420)
  → HTTP POST 192.168.1.42:8420/v1/scroll2 {selector: "#footer", position: "center"}
  → Browser calculates element position relative to its own viewport
  → Browser scrolls iteratively until element is visible (up to maxScrolls)
  → HTTP 200 {success: true, scrollsPerformed: 3, element: {visible: true}}
  → CLI returns result
```

---

## Communication Protocol

### HTTP API

All browser-CLI communication uses REST over HTTP/JSON.

- Base URL: `http://{device-ip}:{port}/v1/`
- Content-Type: `application/json`
- Auth: None (local network only — devices must be on same network)
- Port: `8420` (default, configurable in settings)

### mDNS Service

```
Service Type: _kelpie._tcp
Port: 8420

TXT Records:
  id       = "a1b2c3d4-..."        # Stable unique device ID (UUID)
  name     = "My iPhone"           # User-friendly device name
  model    = "iPhone 15 Pro"       # Device model
  platform = "ios" | "android" | "macos"   # Platform identifier
  engine   = "webkit" | "chromium" | "gecko"  # Active renderer on macOS
  width    = "390"                  # CSS viewport width
  height   = "844"                  # CSS viewport height
  port     = "8420"                 # HTTP server port
  version  = "1.0.0"               # App version
```

### Device Identity

Every Kelpie browser instance has a **stable unique device ID** used for reliable targeting across sessions:

- **iOS**: Uses `identifierForVendor` (UUID that persists across app launches, resets only on full app reinstall). Stored in Keychain for extra persistence.
- **Android**: Uses a self-generated UUIDv4, stored in SharedPreferences on first launch. Persists across app restarts. Falls back to `Settings.Secure.ANDROID_ID` as a secondary identifier.
- **macOS**: Uses the machine's stable hardware UUID (`IOPlatformUUID`) as the base identity and persists it for app-level reuse.
- **Linux**: Uses a self-generated UUIDv4 stored in the profile directory (`device-id`). Persists across restarts and survives port changes.
- **Simulators/Emulators**: Generate a UUIDv4 on first launch, stored locally. Each simulator instance gets its own unique ID.

The device ID is:
- Included in mDNS TXT records as `id` field
- Returned by `getDeviceInfo` in the `device.id` field
- Accepted by CLI `--device` flag (in addition to name and IP)
- Stable across network changes, app restarts, and reboots
- Never changes unless the app is completely reinstalled

**CLI device targeting priority**: `--device` accepts device ID (exact match), device name (fuzzy match), or IP address. Device ID is the most reliable — names can collide, IPs can change.

### MCP Transport

Both browser and CLI MCP servers use **Streamable HTTP** (SSE) transport:

- Browser MCP: `http://{device-ip}:{port}/mcp`
- CLI MCP: `stdio` (standard MCP CLI transport) or `http://localhost:8421/mcp`

---

## Security Model

Kelpie operates exclusively on the local network. No cloud services, no remote access.

| Boundary | Control |
|---|---|
| Network isolation | Devices must be on the same local network |
| No internet exposure | HTTP servers bind to local/private IPs only |
| No persistent scripts | No browser extensions or content scripts. Some iOS features use ephemeral bridge scripts (cleared on navigation) |
| No data collection | No telemetry, no analytics, no phone-home |
| Port access | Default 8420, configurable per device |

### Shared Network Risk

Kelpie's HTTP API has **no authentication**. Any device on the same network can send commands. This is acceptable on a private home/office network but poses risks on shared Wi-Fi (coworking spaces, hotel networks, conferences):

- An attacker on the same network could discover Kelpie browsers via mDNS and send commands
- Sensitive APIs (cookies, storage, clipboard, JS evaluation) are fully exposed
- There is no TLS — traffic is plaintext HTTP

**Mitigations (planned for v2):**
- **Pairing code**: On first CLI→browser connection, the browser displays a 6-digit code the user must enter in the CLI. The CLI and browser then exchange a shared secret used to sign subsequent requests.
- **Allowlist mode**: The browser can restrict connections to specific IP addresses after initial pairing.

**Current recommendation**: Use Kelpie only on trusted private networks. Do not use on public or shared Wi-Fi without a VPN.

---

## Platform-Specific Architecture Details

### macOS — Dual Renderer Architecture

The macOS app exposes the same HTTP and MCP surface as the mobile apps, but its browser layer is runtime-switchable. It keeps both renderers available:

- `WKWebView` for Safari/WebKit behavior
- CEF for Chromium/Chrome behavior

Both renderers conform to a shared abstraction, so navigation, JavaScript evaluation, screenshots, cookies, and state reads go through one handler interface. The toolbar segmented control and the `/v1/set-renderer` / `/v1/get-renderer` endpoints switch the active engine without changing the API contract.

When the renderer changes, Kelpie migrates cookies from the previous engine into the new one before resuming automation. That preserves authenticated sessions while letting the user or LLM switch between Safari and Chrome rendering behavior.

### iOS — No-Injection DOM Access

WKWebView's `evaluateJavaScript` executes in the page's JS context via the native bridge. It is not a persistent content script — it runs on demand and doesn't survive navigation. The page can theoretically detect these calls (e.g., by overriding DOM prototype methods), but this is true of all browser automation tools including Playwright.

**iOS bridge scripts (honest accounting):** Features that WKWebView doesn't expose natively require ephemeral bridge scripts injected via `evaluateJavaScript` or `WKUserScript`:
- Console capture: overrides `console.log/warn/error` to forward messages to native
- Mutation observation: injects a `MutationObserver`
- Accessibility tree: queries ARIA attributes via DOM traversal
- Page text extraction: runs a Readability-style algorithm
- Network logging: limited — WKWebView has no network interception API; only top-level navigation events via `WKNavigationDelegate`. XHR/fetch tracking requires an injected `XMLHttpRequest`/`fetch` wrapper.

These scripts are lightweight, non-persistent, and do not modify page content or behavior. They are cleared on navigation.

### Simulator & Emulator Support

Both mobile platforms support simulators/emulators alongside real devices. iOS Simulators are zero-setup; Android Emulators require `adb forward` for port mapping:

**iOS Simulator**
- Each Simulator instance runs its own app process
- Bonjour/mDNS works natively — the Simulator shares the host's network stack
- No port forwarding needed — the HTTP server is directly reachable from the host
- Multiple Simulators with different screen sizes can run simultaneously (iPhone SE, iPhone 15, iPad, etc.)
- `getDeviceInfo` returns `isSimulator: true`

**Android Emulator**
- Each emulator instance runs its own app process
- Emulators run behind NAT — use `adb forward tcp:{hostPort} tcp:8420` to expose each instance
- The CLI auto-detects ADB-forwarded ports when standard mDNS discovery fails
- Multiple emulators with different AVDs (Pixel 4, Pixel 8, Tablet, etc.) can run simultaneously
- `getDeviceInfo` returns `isSimulator: true`

**Mixed fleets** — the CLI treats real devices, simulators, and emulators identically once discovered. The `isSimulator` flag in device info lets LLMs distinguish them if needed.

### Android — Chrome DevTools Protocol

Android WebView is Chromium-based. Enabling `setWebContentsDebuggingEnabled(true)` exposes CDP over a local Unix socket. The app connects to this socket and issues CDP commands.

> **Note on `setWebContentsDebuggingEnabled`:** Google documents this API as a debugging tool, not a production control plane. Kelpie enables it intentionally — the app *is* a debugging/automation tool by design. The flag has no known performance or security penalties beyond exposing the CDP socket (which Kelpie's own process consumes). Play Store review has not historically flagged apps that enable it, but this could change. If Google restricts this API in future Android versions, Kelpie would fall back to `evaluateJavascript()` for DOM operations (losing CDP-only features like network interception and the accessibility tree protocol).

- `DOM.*` — full DOM tree traversal and queries
- `Page.captureScreenshot` — screenshots
- `Runtime.evaluate` — JS evaluation via protocol
- `Input.dispatchMouseEvent` / `Input.dispatchTouchEvent` — input simulation
- `Emulation.*` — viewport and device metric control
- `Network.*` — request interception (future)

This is the same protocol Playwright and Chrome DevTools use.
