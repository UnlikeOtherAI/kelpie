# Windows and Linux Portability Plan

**Goal:** Reuse as much of the existing macOS app architecture as possible to ship a Windows desktop app, a Linux desktop app, and a Linux headless build without fragmenting the HTTP/MCP surface or the CLI experience.

**Recommendation:** Do not try to "port the Mac app" literally. The SwiftUI/AppKit shell is not portable, and we should not try to share Swift on Windows or Linux. The portable asset is the macOS app's architecture: shared handler surface, renderer abstraction, cookie/state model, HTTP/MCP contract, and CEF-backed Chromium path. Build a shared desktop Chromium core and put thin Windows and Linux shells around it.

**Non-goal:** Reproducing Safari/WebKit behavior outside Apple platforms. Windows and Linux should be Chromium-only.

---

## Executive Summary

What we can transfer directly today:

- The CLI and shared TypeScript packages
- The `/v1/` HTTP contract and MCP tool surface
- The device discovery model and `_kelpie._tcp` advertisement contract
- The macOS app's separation between UI shell, renderer, handlers, and network server
- The Chromium/CEF renderer strategy already proven on macOS
- The browser stores and invariants: bookmarks, history, cookies, network traffic, console log, viewport state

What we cannot transfer directly:

- SwiftUI/AppKit UI code
- Swift language code as a shared Windows/Linux implementation strategy
- `WKWebView`, Safari auth, `ASWebAuthenticationSession`, and other Apple-only APIs
- `Network.framework` server/discovery code
- The Objective-C++ CEF bridge as-is

The minimum-complexity path is:

1. Freeze the cross-platform contract at the current HTTP/MCP layer.
2. Extract a non-Swift desktop core around Chromium/CEF.
3. Put a thin Windows GUI shell on that core.
4. Put a Linux shell on that core that supports both GUI and headless launch modes.
5. Add Windows/Linux packaging without changing the browser/server core.

That yields the highest reuse with the least platform-specific product divergence.

---

## Current macOS Assets That Matter

The parts of the macOS app worth preserving are architectural seams, not the Apple UI code.

### Proven reusable seams

- [`apps/macos/Kelpie/Renderer/RendererEngine.swift`](/System/Volumes/Data/.internal/projects/Projects/kelpie/apps/macos/Kelpie/Renderer/RendererEngine.swift) defines the right abstraction boundary: navigation, JS evaluation, cookies, screenshots, view attachment, and state callbacks.
- [`apps/macos/Kelpie/Handlers/HandlerContext.swift`](/System/Volumes/Data/.internal/projects/Projects/kelpie/apps/macos/Kelpie/Handlers/HandlerContext.swift) centralizes browser actions behind the active renderer.
- [`apps/macos/Kelpie/Network/ServerState.swift`](/System/Volumes/Data/.internal/projects/Projects/kelpie/apps/macos/Kelpie/Network/ServerState.swift) already separates server lifecycle, mDNS, renderer lifecycle, and switching.
- [`packages/shared/src/device-types.ts`](/System/Volumes/Data/.internal/projects/Projects/kelpie/packages/shared/src/device-types.ts) and [`packages/shared/src/api-types.ts`](/System/Volumes/Data/.internal/projects/Projects/kelpie/packages/shared/src/api-types.ts) already define the external contract consumed by the CLI and MCP.

### macOS-specific code we should not treat as portable

- SwiftUI views under [`apps/macos/Kelpie/Views/`](/System/Volumes/Data/.internal/projects/Projects/kelpie/apps/macos/Kelpie/Views)
- Apple networking primitives in the macOS server layer
- WebKit renderer implementation
- Safari auth helper
- Objective-C++ bridge details tied to Cocoa embedding

---

## Portability Matrix

| Area | Reuse Level | Notes |
|---|---|---|
| CLI (`packages/cli`) | High | Reuse unchanged apart from new platform enums/capabilities |
| Shared TypeScript contracts | High | Extend `Platform` to include `windows` and `linux` |
| HTTP endpoints and MCP tools | High | Keep identical contracts across desktop targets |
| Handler architecture | Medium | Reuse behavior and endpoint semantics, but reimplement in desktop core language |
| Bookmark/history/network stores | Medium | Reuse data model and behavior; not the Swift code directly |
| Renderer abstraction | High | Keep the same idea; move to a language usable on Win/Linux |
| CEF/Chromium engine path | High | Best reuse candidate for all non-Apple desktop targets |
| SwiftUI/AppKit shell | None | Replace completely |
| WKWebView/Safari path | None | Apple-only |
| Safari auth | None | Apple-only; do not emulate badly |

---

## Recommended Target Architecture

## 1. Shared Desktop Core

Create one shared desktop runtime responsible for:

- Browser engine lifecycle
- HTTP server
- MCP server
- mDNS advertisement
- Command routing
- Handler execution
- Cookie/storage/bookmark/history/network stores
- Screenshot and DOM/query implementations
- Headless/windowed mode selection

This core should be Chromium-only and built around CEF.

It should not be written as shared Swift. Swift remains macOS-only. The shared desktop core should use a language/runtime that can build on Windows and Linux directly, with C++ being the natural fit because CEF already lives there.

Why CEF:

- The macOS app already proved Chromium parity matters for real websites.
- Windows and Linux both have mature CEF distributions.
- Linux headless can be served by the same engine in off-screen mode instead of building a second browser backend.
- It avoids inventing a second transport/automation stack only for desktop.

## 2. Thin Platform Shells

Keep shells thin. Their only job should be native windowing, menus, tray integration if needed, and platform packaging.

### Windows shell

- Native window host
- Toolbar, URL bar, settings, bookmarks/history/network panels
- Embed the shared desktop core's windowed Chromium view
- Package as standard desktop app

### Linux shell

- Native Linux window host for normal desktop usage
- Same product surface as Windows where practical
- Embed the shared desktop core's windowed Chromium view in GUI mode
- Launch the exact same core in off-screen mode for headless usage

Linux headless is not a second app architecture. It is the Linux app running without a visible shell.

---

## What To Standardize Before Porting

The macOS implementation currently expresses good boundaries, but they live in Swift. Before building Windows/Linux, we should standardize the desktop contract explicitly.

## Desktop core interfaces

Define explicit cross-platform interfaces for:

- `RendererEngine`
- `BrowserStore`
- `NetworkServer`
- `MdnsAdvertiser`
- `DesktopShell`
- `AuthProvider`

The important point is not the exact names. The important point is that handlers must depend on these abstractions instead of platform frameworks.

## Feature capability reporting

Add `windows` and `linux` to the platform model and keep capability reporting honest.

Expected desktop capability shape:

- Supported on Windows/Linux GUI: navigation, DOM, screenshots, eval, console, network inspector, cookies, storage, tabs, history, bookmarks, viewport presets, toast, MCP, mDNS
- Supported on Linux headless: everything above except UI-only shell features
- Unsupported on Windows/Linux: Safari auth, WebKit renderer switching, soft keyboard APIs, Apple TV external display, orientation lock

Do not pretend unsupported features exist. Return `PLATFORM_NOT_SUPPORTED`.

---

## Product Decisions

## 1. No Safari/WebKit outside Apple platforms

Windows and Linux should not have `set-renderer` in the macOS sense.

Recommended behavior:

- `get-renderer` returns `chromium`
- `set-renderer` accepts `chromium` only, or returns `PLATFORM_NOT_SUPPORTED` if we want a stricter contract

Recommendation: keep the endpoint and make it deterministic.

- macOS: `webkit` and `chromium`
- Windows/Linux: `chromium` only

That preserves tooling symmetry without lying about platform behavior.

## 2. No fake Safari auth replacement

The macOS/iOS Safari auth flow is Apple-specific. Do not ship a weak imitation that only works on some sites.

Recommended initial behavior:

- `safari-auth` remains Apple-only
- Windows/Linux return `PLATFORM_NOT_SUPPORTED`

Possible future follow-up:

- Add a new cross-platform `system-auth` flow with its own contract
- Keep it separate from `safari-auth`

## 3. Linux headless is first-class, not an afterthought

Linux headless should be designed from the start as a runtime mode of the same desktop core.

Requirements:

- No visible window
- Off-screen rendering for screenshots
- Full DOM/query/eval support
- Persisted cookies/storage/profile data
- Same HTTP/MCP surface as GUI builds
- Explicit capability flag showing `headless: true` in a future extension

---

## Repo Shape

Recommended repository change:

```text
apps/
  macos/                 # existing Swift app
  windows/               # thin native shell
  linux/                 # thin native shell + headless entry point
  desktop-core/          # shared Chromium desktop runtime
packages/
  cli/
  shared/
```

`desktop-core` owns the browser and server logic. `windows` and `linux` should be mostly host/bootstrap code plus packaging.

Longer-term simplification:

- macOS Chromium support should also consume `desktop-core`
- macOS WebKit stays in the Swift app as the Apple-only renderer path

That would reduce the current duplication between macOS Chromium and future Windows/Linux Chromium work.

---

## Language and Runtime Recommendation

There are two realistic options.

### Option A: Shared C++ desktop core around CEF

Pros:

- Maximum reuse of the Chromium strategy
- Native fit for CEF on Windows/Linux
- Natural way to support Linux headless/off-screen mode
- Makes the desktop browser behavior uniform

Cons:

- Requires rewriting Swift handler logic into a shared native core
- More native build tooling

### Option B: Separate platform apps with duplicated logic

Pros:

- Faster first spike per platform

Cons:

- Duplicates handlers, stores, and invariants again
- Makes Linux headless a second implementation
- Increases drift risk immediately

Recommendation: Option A.

It is more work up front, but it is still the minimum-complexity system because it prevents three separate desktop codebases.

### What this means in practice

- macOS keeps Swift for the Apple shell and WebKit path
- Windows does not run shared Swift
- Linux does not run shared Swift
- Shared desktop browser/server logic lives in C++ around CEF
- If macOS later wants to reuse that shared desktop Chromium core, it does so through an Objective-C++ or C bridge, not by making Swift the shared language

---

## Migration Plan

## Phase 1: Freeze the desktop contract

- Audit current macOS endpoints and capability behavior
- Add `windows` and `linux` to shared platform enums
- Define desktop-specific capability tables
- Document which endpoints stay cross-platform and which remain Apple-only

## Phase 2: Extract a desktop-core design

- Move renderer-neutral handler behavior into a platform-agnostic design doc
- Define shared store formats for cookies, bookmarks, history, and captured network traffic
- Define the shell-to-core interface for window attach/detach and state updates

## Phase 3: Build Chromium desktop core

- CEF-backed renderer
- HTTP server and MCP server
- mDNS advertiser
- Shared stores
- Headless/windowed runtime mode

At the end of this phase, Linux headless should already exist.

## Phase 4: Add Windows shell

- URL bar
- desktop toolbar/menu
- settings sheet
- bookmarks/history/network inspector views
- installer/packaging

## Phase 5: Add Linux GUI + headless shell

- Match Windows feature set closely in GUI mode
- Keep shell-specific behavior minimal
- Reuse the same desktop core and the same API/capability model
- Support a headless launch flag that skips the visible window but keeps the browser runtime alive

## Phase 6: Converge macOS Chromium onto the same core

This is optional for the first ship, but strongly recommended after Windows/Linux are real.

It simplifies all Chromium-specific desktop work:

- network inspection
- console handling
- cookies/storage
- screenshots
- DOM/query/eval behavior

The Apple-only surface then becomes a smaller layer:

- Swift shell
- WebKit renderer
- Safari auth

---

## Feature Mapping

| Feature | macOS WebKit | macOS Chromium | Windows | Linux GUI | Linux Headless |
|---|---|---|---|---|---|
| Navigate/click/fill/scroll | Yes | Yes | Yes | Yes | Yes |
| DOM/query/eval | Yes | Yes | Yes | Yes | Yes |
| Viewport screenshot | Yes | Yes | Yes | Yes | Yes |
| Full-page screenshot | Yes | Yes | Yes | Yes | Yes |
| Console capture | Yes | Yes | Yes | Yes | Yes |
| Network inspector | Yes | Yes | Yes | Yes | Yes |
| Cookies/storage | Yes | Yes | Yes | Yes | Yes |
| Bookmarks/history | Yes | Yes | Yes | Yes | Yes |
| mDNS + HTTP + MCP | Yes | Yes | Yes | Yes | Yes |
| Renderer switching | Yes | Yes | No | No | No |
| Safari auth | Yes | No | No | No | No |
| Native desktop UI shell | Yes | Yes | Yes | Yes | No |

---

## Build and Packaging Notes

## Windows

- Package the app, helper subprocess, and CEF runtime together
- Keep packaging simple first: local dev build, then installer
- Persist runtime state in a normal user data directory, not registry-only state

## Linux GUI

- Package the app plus CEF runtime and helper processes
- Prefer a packaging strategy that works on common desktop distributions first
- Treat distro-specific packaging as a release problem, not a core architecture problem

## Linux headless

- Ship the same Linux app/runtime with a `--headless` or equivalent launch mode
- Support explicit profile/data directory flags
- Make service-mode deployment straightforward with a documented systemd unit later

---

## Risks

## 1. Rewriting handlers three times by accident

If Windows, Linux GUI, and Linux headless each get their own handler implementations, this effort will fail architecturally.

Mitigation:

- One desktop core
- Thin shells only

## 2. Keeping macOS Chromium separate forever

That would create two Chromium desktop stacks with duplicated bugs and fixes.

Mitigation:

- Treat convergence of macOS Chromium onto the shared core as part of the roadmap, not optional cleanup

## 3. Over-promising cross-platform auth

The Apple auth story does not transfer.

Mitigation:

- Mark `safari-auth` unsupported off Apple platforms
- Design a separate cross-platform auth feature later if needed

## 4. Treating headless as a special one-off

That usually produces a second browser implementation.

Mitigation:

- Headless is the same desktop core in a different launch mode

---

## Recommendation

Build one Chromium desktop core and reuse it everywhere outside Apple WebKit.

That means:

- macOS keeps its dual-renderer value
- Windows gets a Chromium desktop shell
- Linux gets a Chromium desktop shell
- Linux headless is the same Chromium core without a UI shell

This is the highest-reuse path that still respects the reality that the current macOS Swift app is not itself portable.

---

## Cross-Provider Review

Pending. This document should get an adversarial review before implementation begins, focused on:

- whether `desktop-core` is the right seam
- whether Linux headless truly stays the same runtime instead of becoming a fork
- whether `set-renderer` should remain a universal endpoint or become macOS-only
- whether macOS Chromium convergence should be mandatory earlier
