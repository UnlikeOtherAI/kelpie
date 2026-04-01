# Desktop Shared Core Refactor Plan

**Goal:** Refactor the browser-app side of Mollotov so that the shared browser protocol, MCP interface, state stores, and renderer-agnostic automation logic live in reusable libraries, while platform shells stay thin.

**Scope:** This plan covers the shared refactor and implementation sequence for the browser app side only. The Node CLI remains in TypeScript. Platform-specific delivery for Linux and Windows is split into separate plans.

**Recommendation:** Build a shared C++ core for browser-app logic and keep the current Swift/Kotlin code only as platform shells and renderer adapters where needed.

**See Also:** [browser-engines.md](../browser-engines.md) — Complete guide to engine availability by platform, Apple regulatory requirements, and compliance strategy.

---

## Why This Refactor

The current repo already has the right external seam:

- shared HTTP contract in [`packages/shared/src/api-types.ts`](/System/Volumes/Data/.internal/projects/Projects/mollotov/packages/shared/src/api-types.ts)
- shared MCP tool names in [`packages/shared/src/mcp-tools.ts`](/System/Volumes/Data/.internal/projects/Projects/mollotov/packages/shared/src/mcp-tools.ts)
- renderer abstraction and handler context on macOS in [`apps/macos/Mollotov/Renderer/RendererEngine.swift`](/System/Volumes/Data/.internal/projects/Projects/mollotov/apps/macos/Mollotov/Renderer/RendererEngine.swift) and [`apps/macos/Mollotov/Handlers/HandlerContext.swift`](/System/Volumes/Data/.internal/projects/Projects/mollotov/apps/macos/Mollotov/Handlers/HandlerContext.swift)

What is missing is a reusable internal core. Right now the external contract is shared, but the browser-app implementation is not.

---

## Target Architecture

Split the browser-app implementation into reusable libraries by responsibility.

### `core-protocol`

Owns:

- endpoint names
- MCP tool names
- error codes
- platform and engine enums
- region constants for alternative engine availability (`ALTERNATIVE_ENGINE_REGIONS`)
- capability model
- request/response schemas

Rules:

- This is the source of truth for browser HTTP/MCP naming.
- Platform-specific methods still live here, but with explicit availability metadata.

### `core-state`

Owns:

- bookmarks model and persistence rules
- history model and persistence rules
- console entry model
- network inspector entry model
- cookie normalization helpers
- storage normalization helpers

Rules:

- Event capture is platform-specific.
- Event storage, filtering, pagination, and serialization are shared.

### `core-automation`

Owns:

- handler logic against abstract interfaces
- command dispatch
- response shaping
- feature gating
- shared invariants for click/fill/scroll/wait/eval/navigation

Rules:

- This layer must not know about AppKit, SwiftUI, Android Views, or Linux/Windows UI toolkits.

### `core-mcp`

Owns:

- browser-side MCP registry
- tool metadata
- availability evaluation
- runtime registration filtering

Rules:

- One shared MCP registry for browser apps.
- Platform-only methods are gated here, not split into separate MCP servers.

### `engine-cdp`

Owns:

- reusable CDP client and helpers
- request/response decoding
- shared CDP operations for DOM, network, console, screenshot, emulation where applicable

Rules:

- Reusable by Android, Chromium desktop adapters, and iOS Chromium (region-gated).
- Must not assume CEF-specific embedding.

### `engine-chromium-desktop`

Owns:

- CEF runtime
- windowed and off-screen rendering
- Chromium desktop cookies and browser lifecycle
- desktop screenshot path
- desktop network and console collection hooks

Rules:

- Desktop-only.
- Linux headless is the same engine in off-screen mode.

### `engine-webkit`

Owns:

- Apple WebKit adapter
- Apple-only auth integration hooks
- WebKit-specific DOM, screenshot, and cookie bridge code

Rules:

- Apple-only.
- Keeps Safari/WebKit isolated from the desktop Chromium core.

### `engine-gecko`

Owns:

- Gecko/Firefox embedding runtime
- GeckoView (mobile) or Gecko embedding API (desktop) integration
- Gecko-specific DOM, screenshot, cookie, and network hooks
- Firefox-parity rendering for web compatibility testing

Rules:

- Primary engine for Windows.
- Available on macOS as a third renderer option alongside WebKit and CEF — gives macOS Safari + Chrome + Firefox rendering parity.
- Available on iOS as an alternative engine in EU, UK, and Japan regions only (see [Region-Gated Engine Availability](#region-gated-engine-availability)).
- Available on Android as an alternative engine via GeckoView (no region restriction — Android has always allowed alternative engines).
- Available on Linux if Gecko embedding is supported.
- Shares the CDP-like remote debugging surface where possible (Firefox Remote Protocol / Marionette).
- Must not assume Chromium APIs — Gecko has its own debugging protocol.

### `engine-chromium-mobile`

Owns:

- Chromium embedding for iOS in regions where alternative engines are permitted
- Blink-based rendering as an alternative to WKWebView
- CDP surface reuse from `engine-cdp`

Rules:

- iOS only, region-gated to EU, UK, and Japan.
- Android already uses Chromium via system WebView — this module is for iOS alternative engine support.
- Shares CDP helpers with `engine-cdp`.

### `platform-shell-*`

Owns:

- UI chrome
- menus and settings panels
- app lifecycle
- packaging
- native window embedding
- native permissions

Rules:

- Thin only.
- No business logic beyond shell concerns.

---

## Region-Gated Engine Availability

EU Digital Markets Act (DMA), upcoming UK and Japan legislation require Apple to permit alternative browser engines on iOS in those jurisdictions. This means iOS can run Chromium (Blink) and Gecko (Firefox) in addition to WebKit — but only when the device's App Store region is EU, UK, or Japan.

### Detection

- iOS: check `Storefront.current` or `SKStorefront.countryCode` at runtime to determine the device's registered region
- The renderer switcher UI (like macOS has for WebKit/CEF) must only appear on iOS when the region is in the allowed set: `EU`, `GB`, `JP`
- Android has no region restriction on alternative engines — GeckoView is always available

### Regions list

Maintain a single `ALTERNATIVE_ENGINE_REGIONS` constant in `core-protocol`:
- `EU` (all EU member states — use the full ISO 3166-1 alpha-2 list)
- `GB` (United Kingdom)
- `JP` (Japan)

This list will expand as more jurisdictions adopt similar legislation. Keep it data-driven so adding a country is a one-line change.

### iOS behavior

- Default region (outside EU/UK/JP): WebKit only, no renderer switcher shown
- EU/UK/JP region: WebKit + Chromium + Gecko available, renderer switcher visible in settings and floating menu
- The active engine is persisted per-session and reported in mDNS TXT records and `getDeviceInfo`

### Android behavior

- Default: system Chromium WebView (current behavior)
- GeckoView available as alternative engine everywhere (no region gate)
- Renderer switcher shown in settings

---

## MCP Availability Model

This refactor is mainly driven by the MCP surface.

The browser-side MCP registry should move from "flat list of tools" to "tool definitions plus availability".

Each tool needs:

- name
- endpoint/method
- schema
- description
- availability metadata

Minimum availability metadata:

- supported platforms
- supported engines
- requires UI
- allowed in headless mode
- required capability flags
- region restrictions (optional — for region-gated features like iOS alternative engines)

Example cases:

- `mollotov_safari_auth`
  - platforms: `ios`, `macos`
  - requires UI: `true`
- `mollotov_set_renderer`
  - platforms: `ios` (EU/UK/JP only), `android`, `macos`, `windows`, `linux`
  - engines: `webkit` (iOS/macOS), `chromium` (all), `gecko` (all)
- `mollotov_show_keyboard`
  - platforms: `ios`, `android`
  - requires UI: `true`

Rules:

- Shared tools are exposed everywhere they are supported.
- Unsupported tools should be omitted from browser-side MCP discovery.
- HTTP endpoints may remain present for contract stability, but must return `PLATFORM_NOT_SUPPORTED`.
- Region-gated tools (like `set_renderer` on iOS) must return `PLATFORM_NOT_SUPPORTED` when invoked outside the permitted region.
- `getCapabilities` must be generated from the same availability source of truth, including region awareness.

---

## Shared Features To Pull Into Libraries First

These are strong early candidates because they are mostly renderer-agnostic after event capture.

### Bookmarks

Share:

- model
- validation
- persistence format
- add/remove/list/clear logic
- MCP/HTTP handlers

### History

Share:

- model
- dedupe rules
- persistence format
- limit trimming
- list/clear handlers

### Network inspector

Share:

- normalized network event model (includes `initiator` field: `"browser"` for document/subresource loads, `"js"` for fetch/XHR)
- filtering by method, content-type category, initiator/source, URL pattern, and status range
- paging
- detail lookup
- current selection
- clear/list/detail/select handlers

Do not force shared raw capture hooks.

Platform collection remains separate:

- WebKit path
- Android/CDP path
- Chromium desktop path

### Console/error log

Share:

- entry model
- store
- filtering
- truncation
- clear/list handlers

### Capability and unsupported-method handling

Share:

- capability manifest
- availability evaluation
- `PLATFORM_NOT_SUPPORTED` response generation

---

## Proposed Repo Shape

```text
packages/
  cli/                       # existing Node CLI
  shared/                    # TS schemas consumed by CLI/docs if retained
native/
  core-protocol/
  core-state/
  core-automation/
  core-mcp/
  engine-cdp/
  engine-chromium-desktop/
  engine-chromium-mobile/
  engine-webkit/
  engine-gecko/
apps/
  ios/
  android/
  macos/
  linux/
  windows/
```

If we do not want a new `native/` top-level folder, place these under `apps/native/`. The important part is module separation, not the exact path.

---

## Refactor Sequence

## Phase 1: Freeze the contract

- Audit browser HTTP routes and MCP tools
- Add `windows` and `linux` to shared platform enums
- Define the availability metadata model
- Mark platform-specific methods explicitly

Deliverable:

- one source of truth for method names and availability

## Phase 2: Extract shared models

- move bookmarks/history/network/console/capability models into shared libraries
- define normalized persistence formats
- define runtime feature manifest format

Deliverable:

- stores and schemas no longer owned by app shells

## Phase 3: Extract browser-side MCP

- replace flat tool list with tool definitions plus availability
- generate browser-side MCP registry from shared definitions
- ensure `getCapabilities` and MCP exposure use the same rules

Deliverable:

- one browser-side MCP definition system across platforms

## Phase 4: Extract renderer-agnostic handlers

- move handler behavior into `core-automation`
- define renderer/storage/network abstractions
- keep platform adapters thin

Deliverable:

- platform apps mostly wire abstract handlers to real renderers

## Phase 5: Build Chromium desktop engine

- create shared CEF desktop runtime
- support GUI and off-screen execution
- implement desktop browser-side MCP and HTTP surfaces on top of it

Deliverable:

- one reusable desktop browser runtime for Linux and Windows

## Phase 6: Re-point shells

- Windows shell uses Gecko/Firefox as primary engine
- Linux shell uses Gecko/Firefox as primary engine if Gecko embedding is available, Chromium desktop as fallback
- macOS adds Gecko as a third renderer (WebKit + CEF + Gecko — full Safari/Chrome/Firefox parity)

Deliverable:

- desktop platforms no longer duplicate browser logic
- Windows and Linux get Firefox rendering parity via Gecko
- macOS becomes the only platform with all three major engine families

---

## Implementation Tasks

### Task 1: Browser capability manifest

- add structured availability metadata beside browser tool definitions
- teach the browser-side MCP server to filter tools by runtime
- generate `getCapabilities` from the same manifest

### Task 2: Shared state libraries

- extract bookmarks/history/network/console stores
- normalize event shapes
- add tests for filtering, truncation, persistence, and selection

### Task 3: Shared automation layer

- define abstract interfaces for renderer, storage, network observer, and shell services
- port shared handler logic behind those interfaces

### Task 4: Shared desktop Chromium runtime

- implement CEF-based renderer adapter
- add HTTP server, browser-side MCP server, and mDNS
- support GUI and headless modes

### Task 5: Platform adapters

- iOS WebKit adapter (default, all regions)
- iOS Chromium adapter (EU/UK/JP only, region-gated)
- iOS Gecko/GeckoView adapter (EU/UK/JP only, region-gated)
- Android WebView/CDP adapter (default)
- Android GeckoView adapter (alternative, no region gate)
- macOS WebKit adapter
- macOS Gecko/Firefox adapter (third renderer alongside WebKit + CEF)
- Windows Gecko/Firefox adapter (primary engine)
- Linux Gecko/Firefox adapter (primary if available, Chromium desktop fallback)
- Linux/Windows Chromium desktop shell adapters (fallback)

---

## Testing Strategy

- protocol tests: endpoint and MCP name stability
- availability tests: tool exposure and unsupported-method behavior
- state tests: bookmarks/history/network/console persistence and querying
- integration tests: browser-side MCP and HTTP routes over a fake renderer
- desktop runtime tests: Linux headless first

Linux headless should be the first serious integration target because it exercises the shared desktop core without UI-shell noise.

---

## Risks

### Too much platform code in the shared core

Mitigation:

- enforce strict abstract interfaces
- keep windowing and auth outside the core

### MCP drift between CLI and browser apps

Mitigation:

- one shared tool/availability source of truth
- generation or validation tests for tool naming

### Treating Android as CEF-compatible

Mitigation:

- share CDP logic, not desktop Chromium embedding

### iOS region-gated engine complexity

Risk: Region detection on iOS relies on App Store storefront APIs which may change. Apple's compliance with DMA/UK/JP legislation is evolving — engine availability rules may shift.

Mitigation:

- keep the region list (`ALTERNATIVE_ENGINE_REGIONS`) as a data-driven constant, not hard-coded conditionals
- detect region at app launch and cache; re-check on `willEnterForeground`
- if region detection fails, fall back to WebKit-only (safe default)
- watch Apple developer documentation for changes to alternative engine entitlements

### Gecko embedding maturity

Risk: Gecko/Firefox embedding for desktop (outside Android GeckoView) is less mature than CEF. Mozilla's `libxul` embedding API is not as well-maintained as CEF.

Mitigation:

- evaluate GeckoView applicability on desktop Linux first
- if desktop Gecko embedding is not viable, fall back to Chromium desktop on Linux and keep Gecko as a future goal
- Windows Gecko embedding via Firefox's remote debugging protocol (Firefox Remote Protocol) may be more practical than full embedding — consider a hybrid approach

### Rewriting everything at once

Mitigation:

- extract protocol and state first
- Linux headless as the first end-to-end validation target

---

## Cross-Provider Review

Pending before implementation. Review should challenge:

- whether the module boundaries are correct
- whether MCP availability belongs in `core-protocol` or `core-mcp`
- whether `engine-cdp` is the right reuse seam for Android
- whether Gecko embedding is viable for Windows/Linux or if Firefox Remote Protocol is a better approach
- whether desktop core extraction should precede or follow shared handler extraction
