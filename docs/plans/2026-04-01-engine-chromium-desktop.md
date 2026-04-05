# Chromium Desktop Engine Plan

**Goal:** Build `native/engine-chromium-desktop/` as the shared desktop browser runtime used by Linux and Windows shells.

**Scope:** This plan covers only the shared desktop core: CEF runtime wiring, HTTP routing, a reusable MCP server implementation, bridge scripts, shared handlers, and platform extension seams for mDNS and device info.

**Out of scope:** GTK, Win32, Cocoa, Avahi, Bonjour, and platform-specific device inspection. Those stay in `apps/linux/` and `apps/windows/`.

## Public Contract

The module must match the existing shared browser contract instead of inventing desktop-only names.

- HTTP endpoints stay under `/v1/`
- MCP tool names stay under `kelpie_`
- Navigation methods are `navigate`, `back`, `forward`, `reload`, and `get-current-url`
- Cookie/storage methods follow the existing names: `get-cookies`, `set-cookie`, `delete-cookies`, `get-storage`, `set-storage`, `clear-storage`
- Unsupported but contract-stable endpoints return `PLATFORM_NOT_SUPPORTED`
- Where the repo currently has naming drift across docs and app handlers, the desktop core should prefer the established shared names and optionally register compatibility aliases instead of forcing Linux/Windows to pick one side of the inconsistency

This matters because the current MCP registry and docs already expose these names. The Linux plan’s `go-back` / `go-forward` wording is treated as shorthand, not source of truth.

## Module Shape

```text
native/engine-chromium-desktop/
  CMakeLists.txt
  include/kelpie/
    desktop_app.h
    desktop_bridge.h
    desktop_engine.h
    desktop_http_server.h
    desktop_mcp_server.h
    desktop_mdns.h
    desktop_router.h
    cef_renderer.h
  src/
    desktop_app.cpp
    desktop_bridge.cpp
    desktop_engine.cpp
    desktop_http_server.cpp
    desktop_mcp_server.cpp
    desktop_router.cpp
    cef_renderer.cpp
    handlers/
      ...
```

## Design

### 1. Engine and renderer seam

`DesktopEngine` owns CEF lifecycle and one browser session. It exposes two operating modes:

- `windowed`: browser hosted by a platform shell that provides the native window handle
- `offscreen`: browser runs with windowless rendering and stores the latest paint buffer for screenshots

The engine owns:

- CEF init and shutdown
- browser creation
- message loop stepping
- bridge injection hooks
- capture sinks for console and network events
- viewport state for offscreen rendering

`CefRenderer` implements `RendererInterface` and is the only object handlers talk to through `HandlerContext`.

To keep app shells thin, platform-specific window handle plumbing is passed in through opaque config fields instead of introducing GTK or Win32 types into this library’s public API.

### 2. HTTP server and router

`DesktopHttpServer` wraps `cpp-httplib::Server`.

- `GET /health` returns `{"status":"ok"}`
- `POST /v1/{method}` parses JSON and delegates to `DesktopRouter`
- `OPTIONS` is handled for CORS preflight
- every response gets permissive CORS headers

`DesktopRouter` is a string-to-handler map using:

```cpp
std::function<nlohmann::json(const nlohmann::json&)>
```

The router does not know about CEF. It only owns handler registration and response shaping for unknown methods or malformed requests.

### 3. Shared handler model

Handlers are grouped by responsibility and keep platform code out of the module:

- navigation: `navigate`, `back`, `forward`, `reload`, `get-current-url`
- interaction: `click`, `fill`, `type`, `select-option`, `check`, `uncheck`
- DOM: `query-selector`, `query-selector-all`, `get-element-text`, `get-attributes`, `get-dom`
- evaluate: `evaluate`
- screenshot: `screenshot`, `screenshot-annotated`
- scroll: `scroll`, `scroll-to-top`, `scroll-to-bottom`
- console: `get-console-messages`, `clear-console`
- network: `get-network-log`, `get-resource-timeline`
- device: `get-device-info`
- bookmarks: `bookmarks-add`, `bookmarks-remove`, `bookmarks-list`, `bookmarks-clear`
- history: `history-list`, `history-clear`
- browser management: `get-tabs`, `new-tab`
- renderer: `get-renderer`, `set-renderer`
- viewport: `get-viewport`, `resize-viewport`, `reset-viewport`
- cookies and storage: `get-cookies`, `set-cookie`, `delete-cookies`, `get-storage`, `set-storage`, `clear-storage`

For desktop MVP:

- `new-tab` returns a successful single-tab placeholder or opens the current tab URL in-place, but `get-tabs` reports one active tab only
- `set-renderer` always returns `PLATFORM_NOT_SUPPORTED`
- `get-renderer` reports current renderer as `chromium` and available renderers as `["chromium"]`
- endpoints that exist in the shared HTTP or MCP contract but are not implemented in this module are registered as explicit unsupported handlers instead of being silently absent from HTTP
- bookmark/history aliases from older plan wording (`add-bookmark`, `get-bookmarks`, `get-history`, `clear-history`) are treated as compatibility shims if Linux or Windows shell code still references them during the transition

### 4. Shared state and context

The handler layer uses:

- `HandlerContext` for renderer access
- `BookmarkStore`
- `HistoryStore`
- `ConsoleStore`
- `NetworkTrafficStore`

`DesktopAppContext` will bundle these dependencies once so each handler constructor stays small.

Extra desktop-only seams:

- `DeviceInfoProvider`: pure virtual interface provided by Linux/Windows apps
- `DesktopMdns`: pure virtual interface provided by Linux/Windows apps

### 5. Browser-side MCP server

`DesktopMcpServer` uses stdio JSON-RPC and `McpRegistry`.

- `initialize` returns server name, version, and capability summary
- `tools/list` returns only tools supported on the current runtime
- `tools/call` maps MCP tool name to the underlying HTTP method name and invokes the same router used by HTTP

This stdio transport is the reusable core implementation. It does not block Linux or Windows shells from additionally exposing browser MCP over HTTP `/mcp` later if the project keeps Streamable HTTP as the public browser-side transport.

Filtering rules:

- only `Platform::kLinux` or `Platform::kWindows` tools are listed
- only `chromium` engine tools are listed
- tools with runtime caveats that are still usable on desktop remain visible
- Apple-only or mobile-only tools are omitted from `tools/list`

HTTP remains broader than MCP:

- unsupported shared endpoints can still exist for contract stability and return `PLATFORM_NOT_SUPPORTED`
- MCP discovery hides tools that are known to be unavailable on desktop Chromium

### 6. Bridge scripts

Bridge injection is split from the engine so the scripts can be unit-tested as strings.

- console bridge wraps `console.log`, `warn`, `error`, `info`, and `debug`
- network bridge wraps `fetch` and `XMLHttpRequest`

Both bridges send structured events back to native via `CefProcessMessage`.

This avoids persistent content scripts in platform shells while keeping the desktop engine self-contained.

### 7. CEF constraints

The module is written against CEF headers only. It does not vendor the SDK.

CMake rules:

- `CEF_ROOT` is a cache path supplied by the app build
- if `CEF_ROOT` is unset, configure should fail with a clear message
- include directories and imported library definitions are derived from `CEF_ROOT`
- the library is built as a static archive consumed by platform apps

The implementation must be careful to avoid pretending the current tree can fully link CEF in CI today. The code should still be structurally correct and compile once the caller provides a real SDK path.

### 8. Simplification choices

To keep complexity bounded for the first desktop core cut:

- single browser instance only
- single active tab only
- device info delegated to platform provider
- mDNS delegated to platform provider
- screenshot annotation metadata generated from DOM queries, not a new rendering pipeline
- cookie and storage operations use shared JS-based access first; full CEF cookie manager plumbing can be added without changing the handler surface

## Build Integration

`native/CMakeLists.txt` will add `add_subdirectory(engine-chromium-desktop)`.

The module links:

- `kelpie_core_protocol`
- `kelpie_core_state`
- `kelpie_core_automation`
- `kelpie_core_mcp`
- `nlohmann_json::nlohmann_json`
- `httplib::httplib`
- CEF libraries from `CEF_ROOT`

## Verification

For this implementation phase, verification should cover:

- native configure/build with the new target wired into `native/CMakeLists.txt`
- handler and router unit tests that do not require a live CEF runtime
- MCP filtering tests for Linux and Windows Chromium runtimes

Full CEF runtime execution is deferred until Linux and Windows shells provide real SDK paths and platform glue.

## Cross-Provider Review

This environment did not expose a non-Codex provider directly, so I used an external `codex exec` adversarial review as a fallback and assessed the findings manually.

Accepted findings:

1. The first draft understated the shared public contract. The repo’s shared docs and MCP metadata cover many more browser methods than the desktop MVP implements, so the plan now requires explicit unsupported HTTP handlers for the wider contract instead of implying Linux/Windows can publish a narrower API.
2. The first draft baked in bookmark and history endpoint names (`add-bookmark`, `get-bookmarks`, `get-history`) that do not match the existing app handlers (`bookmarks-add`, `bookmarks-list`, `history-list`, `history-clear`). The plan now treats those older names as compatibility aliases, not the canonical contract.
3. The first draft made stdio sound like the only browser-side MCP transport. The plan now states that stdio is the reusable shared-core implementation and does not prevent platform shells from exposing HTTP `/mcp` if that remains the public transport.

Rejected or downgraded findings:

1. Concern that opaque native window handles are inherently a bad abstraction. Rejected. For a C++ shared desktop engine that must stay free of GTK and Win32 headers, an opaque host handle in config is the minimum-complexity seam.
2. Concern that a single-tab MVP is too weak for the shared desktop core. Downgraded. It is an acceptable first cut as long as `get-tabs` and `new-tab` stay contract-stable and later expansion does not require a breaking API change.
