# 3D Inspector Native Controls Plan

**Goal:** Move 3D inspector controls out of the injected page overlay and into native shell UI on macOS, iOS, and Android. Add a native two-mode toggle so users explicitly switch between `rotate` and `scroll` interaction while the 3D inspector is active.

**Why:** The current 3D inspector mixes two responsibilities inside injected JavaScript:
- It renders the control buttons itself.
- It decides how single-finger / pointer input should behave.

That creates two problems:
- The controls are not native or reliably accessible.
- Single-finger input is overloaded between rotate and scroll, which creates an unavoidable gesture conflict on touch devices.

## Root Cause

The defect is architectural, not visual. The page overlay owns both UI chrome and scene interaction, so the shell cannot present native controls or enforce a clear mode. The right fix is to split responsibilities:

- Native shell owns buttons, selected mode, and visible control state.
- Injected JavaScript owns only the 3D scene transform state and low-level gesture execution.

## Decision

Introduce a small JavaScript gateway on `window.__m3d` and drive it only from native controls.

### JavaScript responsibilities

`window.__m3d` remains the live 3D scene controller and exposes imperative methods:

- `setMode('rotate' | 'scroll')`
- `getMode()`
- `zoomBy(delta)`
- `resetView()`
- `exit()`

The injected script keeps the transparent input capture layer but removes its in-page button UI. Input handling changes to:

- `rotate` mode:
  - pointer drag rotates
  - one-finger touch drag rotates
  - wheel / trackpad vertical scrolling zooms
- `scroll` mode:
  - pointer drag vertically scrolls the source page
  - one-finger touch drag vertically scrolls the source page
  - wheel / trackpad vertical scrolling scrolls the source page
- pinch on touch still zooms in either mode
- hover info remains in-page because it is scene-local feedback, not shell chrome

This avoids the broken “one finger means two things” model.

### Native responsibilities

When 3D inspector is active, native UI shows a dedicated control strip with native buttons only:

- `Exit`
- `Zoom out`
- `Zoom in`
- `Reset`
- `Rotate mode` with hand icon
- `Scroll mode` with hand + vertical arrows icon

The selected mode is held in native state and pushed into the page via the gateway. The shell also initializes the JS mode immediately after entering 3D so UI state and scene state cannot drift.

## Platform UI

### macOS

Show the 3D control strip in the existing native URL bar row while 3D mode is active. Use native `Button` / segmented native controls, not gesture-backed custom views.

### iOS

Show a native overlay control strip while 3D mode is active. Keep it outside the web view and above the floating menu. The control set and mode icons must match macOS.

### Android

Show the same native overlay control strip while 3D mode is active. The available actions and mode semantics must mirror iOS exactly for platform parity.

## State Model

Add a small native enum per platform:

- `rotate`
- `scroll`

The default on 3D entry is `rotate`.

If 3D inspector exits for any reason, native state resets back to `rotate` so the next entry always starts from a known-good mode.

## Files

### macOS

- Update `apps/macos/Kelpie/Handlers/Snapshot3DBridge.swift`
- Update `apps/macos/Kelpie/Views/BrowserView.swift`
- Update `apps/macos/Kelpie/Views/URLBarView.swift`

### iOS

- Update `apps/ios/Kelpie/Views/BrowserView.swift`
- Add native 3D control strip view under `apps/ios/Kelpie/Views/`
- Reuse shared `apps/macos/Kelpie/Handlers/Snapshot3DBridge.swift`

### Android

- Update `apps/android/app/src/main/java/com/kelpie/browser/handlers/Snapshot3DBridge.kt`
- Update `apps/android/app/src/main/java/com/kelpie/browser/ui/BrowserScreen.kt`
- Add native 3D control strip view under `apps/android/app/src/main/java/com/kelpie/browser/ui/`

## Non-Goals

- No HTTP or MCP API change in this pass
- No attempt to unify the Swift and Kotlin bridge sources yet
- No custom inertial scroll physics rewrite beyond preserving the existing scroll behavior semantics

## Verification

- macOS: build and launch, enter 3D, verify all controls are native and functional
- iOS: Xcode build succeeds, verify 3D entry, rotate mode, scroll mode, zoom, reset, exit
- Android: Gradle build succeeds, verify the same control behavior as iOS

## Cross-Provider Review

Reviewed by Claude Code on 2026-04-03 with an adversarial prompt focused on gesture correctness, state drift, accessibility, and cross-platform regression.

Result:
- No critical findings.

Assessment:
- Accepted as-is. The design already splits shell chrome from scene logic, which addresses the underlying conflict without adding protocol or persistence complexity.
