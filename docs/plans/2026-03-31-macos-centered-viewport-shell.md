# macOS Centered Viewport Shell

## Problem

The current macOS browser presets resize and hard-lock the whole `NSWindow`. That couples shell size, chrome layout, and viewport size so tightly that:

- shrinking the window breaks the browser chrome and renderer layout,
- preset changes resize the shell instead of simulating a smaller viewport,
- the app title remains `Kelpie` instead of reflecting the current page title,
- viewport APIs report fake values instead of the real visible viewport.

The requested behavior is a fixed browser shell with a centered simulated viewport inside it.

## Goals

- Make the current default macOS browser shell size the minimum window size.
- Stop preset buttons from resizing the whole window.
- Render preset viewports inside a centered stage with dark grey surround and a lighter grey viewport border.
- Keep the viewport centered horizontally and vertically as the window grows.
- Show the current HTML page title in the standard macOS title area instead of `Kelpie`.
- Show the current viewport resolution in the macOS browser chrome.
- Make `/v1/get-viewport`, `/v1/resize-viewport`, and `/v1/reset-viewport` reflect the real viewport model.

## Non-Goals

- No custom title bar implementation. Use the native window title.
- No attempt to make named presets freely resizable. Only the custom viewport follows manual resizing.
- No iOS or Android changes in this task.

## Proposed Design

### 1. Separate shell size from viewport size

Introduce a dedicated macOS-only `ViewportState` object that owns:

- the selected preset,
- the active viewport size,
- whether the viewport is fixed or follows available space,
- the minimum window size for the shell.

The shell minimum becomes the current default browser window size: `1280x800`.

Named presets no longer change the window frame. They only change the viewport size rendered inside the shell.

### 2. Centered stage layout

Replace the current “renderer fills remaining space” layout with a stage:

- stage background: dark grey,
- viewport card: lighter grey border,
- renderer view clipped inside the viewport card,
- viewport always centered inside the stage.

When the viewport is smaller than the shell, the grey surround is visible.
When the viewport is `custom`, it fills the available stage and tracks manual window resizing.

### 3. Preset behavior

- `iPhone` / `iPad` presets keep their fixed viewport dimensions.
- `Laptop` becomes a centered laptop viewport, not a shell resize.
- `Custom` is the only mode that tracks window resizing.

When a named preset does not fit inside the current stage, clamp it to the largest centered size that fits and surface the actual viewport dimensions in the resolution label and APIs. This is intentional because the user explicitly wants a fixed minimum shell plus smaller centered viewport modes.

### 4. Window title

Stop hardcoding `window.title = "Kelpie"` after setup.
Instead, update the native `NSWindow` title from `browserState.pageTitle`, falling back to the current URL host or `Kelpie` only when no page title exists yet.

This keeps the title in the standard centered macOS title position without inventing a custom chrome layer.

### 5. Viewport reporting and resize APIs

The current handlers return placeholder viewport sizes. Replace that with the live viewport state:

- `get-viewport` returns the current centered viewport dimensions,
- `resize-viewport` switches to `custom` and updates viewport size without resizing the window,
- `reset-viewport` re-applies the preset currently selected in the macOS UI. If `Custom` is selected, it restores full custom fill behavior.

## Files Likely Touched

- `apps/macos/Kelpie/Views/BrowserView.swift`
- `apps/macos/Kelpie/Views/URLBarView.swift`
- `apps/macos/Kelpie/KelpieApp.swift`
- `apps/macos/Kelpie/Handlers/BrowserManagementHandler.swift`
- `apps/macos/Kelpie/Handlers/DeviceHandler.swift`
- `apps/macos/Kelpie/Browser/BrowserState.swift` or a new macOS viewport state file

## Acceptance Criteria

- The macOS window cannot be shrunk below the current default shell size.
- Choosing phone/tablet/laptop presets no longer resizes the window.
- The renderer is centered inside a dark grey stage with a lighter grey border around the viewport.
- Manual window resize only changes the viewport in `custom` mode.
- The visible page title appears in the native macOS title area.
- The chrome shows the current viewport resolution.
- Viewport HTTP endpoints return the real viewport size.

## Risks

- CEF and WKWebView both need to respect an explicit hosted viewport size; resizing the outer SwiftUI container alone is not enough.
- Some existing logic assumes preset changes equal window changes and will need to be removed instead of patched around.

## Simplification Choice

The right fix is to stop treating window size as the viewport model. A small shared viewport state is simpler than continuing to let presets mutate `NSWindow` directly from `URLBarView`.

## Cross-Provider Review

Reviewed with Gemini CLI on 2026-03-31.

Accepted findings:

- Keep viewport state separate from `BrowserState`; use a dedicated `ViewportState` object.
- Make `reset-viewport` unambiguous: it re-applies the currently selected preset.
- Treat renderer-host sizing as a first-class implementation concern, not a SwiftUI clipping detail.
- Keep one clear owner for native window title updates.

Rejected finding:

- “Kill preset clamping” is not compatible with the requested fixed shell minimum and the existing tall portrait presets. For this UI, clamping plus honest viewport reporting is the simpler and more coherent tradeoff.
