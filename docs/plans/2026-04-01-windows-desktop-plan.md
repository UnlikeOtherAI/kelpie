# Windows Desktop Plan

**Goal:** Ship a Windows desktop browser app on top of the shared desktop Chromium core without creating a second browser implementation.

**Recommendation:** Windows should follow Linux headless/core extraction, not precede it. By the time Windows starts, the browser runtime, browser-side MCP, HTTP layer, and stores should already exist in the shared desktop core.

---

## Product Requirements

Windows must support:

- visible desktop browser shell
- shared desktop browser HTTP surface
- shared browser-side MCP surface
- bookmarks, history, console log, and network inspector
- screenshots, DOM access, eval, cookies, storage
- mDNS advertisement

Windows must not fake:

- Safari/WebKit support
- Safari auth
- mobile-only keyboard and orientation APIs

---

## Shared vs Windows-Specific

### Shared with Linux desktop

- desktop Chromium engine
- browser-side MCP
- HTTP handlers
- state stores
- capability evaluation
- mDNS logic

### Windows-specific

- native window host
- application lifecycle
- Windows packaging and installer
- app paths and user data locations

The Windows app should be mostly shell and packaging code.

---

## Runtime Behavior

Windows is GUI-first. Unlike Linux, no headless requirement is in scope for the first pass.

Renderer behavior:

- Chromium-only
- no renderer switching requirement
- `get-renderer` can return `chromium` if we keep the endpoint universally shaped

MCP behavior:

- expose supported shared tools
- hide Apple-only and mobile-only tools from browser-side MCP discovery
- keep unsupported HTTP methods deterministic with `PLATFORM_NOT_SUPPORTED`

---

## Implementation Sequence

## Phase 1: Consume the shared desktop core

- link the Windows shell to the shared desktop Chromium runtime
- launch the browser runtime in windowed mode
- attach shell state to the core

## Phase 2: Build the shell

- window host
- URL bar
- navigation controls
- settings panel
- bookmarks/history/network inspector views

## Phase 3: Package the app

- local development build
- distributable Windows package
- stable user data/profile directory handling

---

## Windows-Specific Tasks

### Task 1: App bootstrap

- define Windows entry point
- create window host
- start shared desktop runtime
- bind shell actions to runtime commands

### Task 2: Shell UI

- URL bar and navigation controls
- shell state display
- settings view
- bookmarks/history/network inspector views
- network inspector must include three filter dropdowns: Method (All/GET/POST/PUT/DELETE), Type (All/HTML/JSON/JS/CSS/Image/Font/XML/Other), Source (All/Browser/JS) — matching iOS, Android, and macOS

### Task 3: User data handling

- define application data directory layout
- persist shell preferences separately from shared browser state where appropriate

### Task 4: Packaging

- package app plus Chromium runtime assets
- keep initial packaging straightforward
- avoid installer complexity until runtime is stable

---

## Verification

Minimum Windows verification:

- launch visible browser shell
- discover via mDNS
- navigate via shell and via CLI
- capture screenshot
- run eval
- verify bookmarks/history/network inspector use shared runtime data
- verify browser-side MCP exposes only supported tools

---

## Risks

### Shell leaks into browser logic

Mitigation:

- keep the Windows shell limited to view and lifecycle concerns

### Windows packaging starts driving architecture

Mitigation:

- complete shared runtime integration before installer work

### Windows starts before shared core stabilizes

Mitigation:

- require Linux headless validation first

---

## Cross-Provider Review

Pending before implementation. Review should challenge:

- whether Windows should remain GUI-only initially
- whether the shell scope is sufficiently thin
- whether any Windows-specific runtime concerns have been pushed too far down into the shared core
