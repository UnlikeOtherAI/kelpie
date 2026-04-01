# Linux GUI and Headless Plan

**Goal:** Ship one Linux browser app that runs in two modes:

- normal GUI desktop app
- headless browser service

Both modes must use the same browser runtime, the same HTTP/MCP surface, and the same state stores.

**Recommendation:** Linux should be the first target for the shared desktop Chromium core because headless mode gives a clean proving ground for the reusable runtime.

---

## Product Requirements

Linux must support:

- full desktop GUI browser shell
- `--headless` launch mode with no visible window
- same `/v1/` HTTP surface as other browser apps where supported
- same browser-side MCP surface where supported
- bookmarks, history, console log, and network inspector
- screenshots, DOM access, eval, navigation, cookies, storage
- mDNS advertisement

Linux must not fake:

- Safari/WebKit support
- Safari auth
- mobile soft keyboard APIs
- device orientation APIs

---

## Linux Runtime Shape

Linux is one app/runtime with two launch modes.

### GUI mode

- visible native window
- URL bar
- toolbar controls
- settings panel
- bookmarks/history/network inspector views
- embedded Chromium desktop renderer

### Headless mode

- no visible window
- same browser profile and stores
- off-screen rendering for screenshots
- same HTTP and browser-side MCP server
- suitable for CI and daemon-style execution

Headless is not a separate product. It is the same runtime launched differently.

---

## Shared vs Linux-Specific

### Shared with other desktop targets

- desktop Chromium engine
- browser-side MCP
- HTTP handlers
- state stores
- mDNS logic
- capability evaluation

### Linux-specific

- process launch flags
- Linux packaging
- Linux app lifecycle
- Linux windowing glue for GUI mode
- service-mode integration guidance

---

## Feature Availability

Linux GUI:

- supports shared desktop browser tools
- exposes GUI-only actions where meaningful

Linux headless:

- supports all renderer/server/store features
- omits UI-only MCP methods
- reports runtime mode in capabilities once that field exists

Linux browser-side MCP should:

- expose only supported tools
- hide Apple-only and mobile-only methods
- keep method names stable for supported tools

---

## Implementation Sequence

## Phase 1: Headless-first runtime

- build desktop Chromium engine with off-screen mode
- attach HTTP server, browser-side MCP, and mDNS
- wire shared stores
- validate screenshots, DOM, eval, cookies, network, and console in headless mode

Why first:

- fastest way to validate the shared desktop core
- avoids GUI shell noise while stabilizing the runtime

## Phase 2: Linux GUI shell

- add Linux native window host
- embed the same renderer in windowed mode
- add URL bar and basic toolbar
- add settings, bookmarks, history, and network inspector views

## Phase 3: Linux mode switching and packaging

- add CLI flags such as `--headless`, `--port`, `--profile-dir`
- ensure GUI and headless use the same runtime paths
- package Linux GUI build
- document headless deployment

---

## Linux-Specific Tasks

### Task 1: Runtime bootstrap

- define Linux entry point
- parse runtime flags
- choose GUI or headless mode
- initialize shared desktop core

### Task 2: Headless profile and persistence

- define profile/data directory layout
- ensure cookies, history, bookmarks, and network cache are consistent
- avoid mode-specific persistence forks

### Task 3: GUI shell

- native Linux window
- URL/navigation controls
- shell-to-core state wiring
- basic desktop menus if needed
- network inspector must include three filter dropdowns: Method (All/GET/POST/PUT/DELETE), Type (All/HTML/JSON/JS/CSS/Image/Font/XML/Other), Source (All/Browser/JS) — matching iOS, Android, and macOS

### Task 4: Linux packaging

- produce reproducible local builds first
- keep packaging strategy simple initially
- defer distro breadth until runtime is stable

### Task 5: Headless ops support

- document headless launch
- document profile directory management
- later add systemd example and service guidance

---

## Verification

Minimum Linux headless verification:

- launch runtime without a visible window
- discover via mDNS
- hit `/v1/get-device-info`
- navigate to a page
- capture screenshot
- run eval
- list bookmarks/history/network data
- expose browser-side MCP with correct filtered tools

Minimum Linux GUI verification:

- open visible shell
- navigate via URL bar
- use settings/bookmarks/history/network inspector
- verify CLI and browser-side MCP both hit the same runtime state

---

## Risks

### Linux headless diverges from GUI

Mitigation:

- one runtime
- mode flag only
- same stores and handler layer

### GUI shell starts owning business logic

Mitigation:

- shell only renders state and forwards actions

### Too many Linux-only forks for packaging

Mitigation:

- stabilize runtime before broad packaging work

---

## Cross-Provider Review

Pending before implementation. Review should challenge:

- whether headless-first is the right sequencing
- whether the Linux shell can stay truly thin
- whether any GUI features currently assumed by the browser runtime block headless correctness
