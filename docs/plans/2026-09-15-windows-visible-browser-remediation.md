# Windows visible-browser remediation

## Problem and evidence

The user opened preview `cecd3e9` and rejected both its appearance and function.
The observed window has a gray content area with "Chromium runtime unavailable",
stock menu/tab/button borders, bold default control fonts, and no usable page.
CEF subprocesses exist. Ctrl+L leaves focus on an embedded Chrome address field.
The fresh process owns port 8420 but the profile readiness record belongs to an
older launch, so its token is rejected. Public device info reports unsupported.
Compilation and 22 unit tests did not establish usable browser startup.

The preview also omitted main's already-landed `359376b` custom window frame
(integrated in `54828fe`). Preserve that work and its native window behavior.
The previous shipping plan remains binding for sandbox, tokens, tab leases,
owner-thread access, and MCP. This plan repairs the visible browser and its UI;
deferred protocol/input/release findings remain recorded separately.

## Batch 1 — Real browser startup and attachment

Terra must document the startup defect before changing production code. Diagnose
why execution does not produce a fresh readiness record and hide the starting
surface, even though CEF and HTTP have started. Capture bounded stage/error
diagnostics without tokens, page data, or profile contents.

- Explicitly select CEF's Alloy style for native child browser creation, including
  initial, restored, and new/popup tabs. The pinned SDK's SetAsChild does not choose
  that style. Preserve the sandboxed bootstrap and external owner-thread pump.
  [Pinned CEF runtime-style contract](https://raw.githubusercontent.com/chromiumembedded/cef/708dc14/include/internal/cef_types_runtime.h).
- A browser-ready transition requires an attached, sized native child, correctly
  selected tab, active event processing, and fresh protected readiness data.
  Do not merely remove the error label. Startup/failure presentation derives from
  runtime state; startup failure must have a concrete, non-secret error reason.
- Bind the actual Windows device-info provider and complete startup without
  relying on stale readiness files. Never repair profile files manually.
- Preserve child z-order, focus, toolbar geometry, and background-tab targeting.
  A running app must accept native navigation and authenticated MCP operations.
- Correct lifecycle behavior needed for clean failed startup and replacement of
  this build; do not create a detached runtime or destroy live CEF callbacks.

## Batch 2 — Consistent native product UI

Use the existing Mac implementation as the design reference. Reuse the custom
frame already on main; retain Windows resize, maximize, system-menu, and DPI
behavior. Keep one native Win32 shell and the shared CEF runtime.

### Visual contract

- Toolbar above tabs, with 34-DIP controls, 8-DIP gaps, 12-DIP horizontal padding,
  and approximately 50-DIP height, based on Mac URLBarView.
- Regular Segoe UI text at roughly 13 DIP for the address and 12 DIP for tab
  titles. Use DPI-scaled metrics and system high-contrast colors when enabled.
- A rounded address surface, subtle separator border, and clear focus ring.
  Preserve native text editing, IME, selection, keyboard shortcuts, and the
  insertion-only autocomplete invariant. Do not claim a secure connection with
  an unconditional lock icon.
- Quiet 40x34-DIP icon buttons for navigation, reload/stop, bookmarks, history,
  network, and settings. Retain accessible names, tooltips, disabled states,
  keyboard focus, and full control hit areas. Only expose implemented actions.
- Rounded tab pills with restrained active accent, truncated regular-weight
  titles, a close button associated with each tab, and a separate add button.
  Preserve stable tab IDs, overflow scrolling, active visibility, and shortcuts.
- Utility panels and toast use the same typography, spacing, colors, and header
  hierarchy. Keep native data/edit controls and improve their visible containers,
  row hit targets, empty states, and sizing. No unrelated feature expansion.

### Implementation constraints

Centralize theme metrics, fonts, and drawing in a small reusable native module.
Use native owner/custom drawing and native input/data controls; do not introduce
another embedded browser, WinUI/Electron framework, or page content scripts.
Retain native accessible tab/button controls where feasible. Any custom strip
must provide actual accessibility semantics and keyboard behavior, not painted
pixels alone. Keep high-contrast, focus, and DPI handling in the same primitives.
Split existing large classes along responsibility seams, keeping source files
under 500 lines without compressing methods or dropping useful comments.

## Integration and verification

Both Terra batches start from the current preview and account for main's frame
changes. Freeze the browser-host interface between them; resolve overlapping
WindowsApp/CMake changes explicitly. Preserve all old qualification/harness
commits and do not replace current CLI files with older versions.

1. Build the actual Release artifact and run relevant tests; this is a prerequisite,
   not the acceptance result.
2. Use one known freshly built app. The previous launch-policy rejection cannot
   be bypassed by another helper, bootstrap invocation, or launcher. If needed,
   have the user open the concrete final build once it is ready.
3. Inspect real page pixels, the URL field, tabs, utility panels, and focus with
   native UI automation. Verify navigate/link/back/forward/reload, new/switch/close,
   autocomplete acceptance/deletion, resize, and browser-to-toolbar focus.
4. Verify fresh readiness and authenticated MCP list/evaluate/navigation/screenshot
   against that same process. Decode a real image; no stub or mock can establish
   this gate. Prove background targeting does not change visible selection.
5. Review the final screenshot against the Mac reference and the user's complaint.
   Do not report the app as usable until the live behavior is actually observed.

## Cross-Provider Review

The user explicitly directed that Claude no longer be used. The prepared Claude
review was not submitted. No different-provider review of this amendment has
been obtained; do not describe the Terra reviews as cross-provider reviews.

Two read-only Terra reviews covered the existing Mac/Windows source and this
repair plan. The orchestrator accepted these concrete corrections:

- One helper configures Alloy style for every initial/restored/new/popup child.
- One shell layout routine owns browser-container geometry; callbacks and MCP
  request its layout rather than repositioning the content independently.
- Keep native accessible controls and custom-draw presentation. Verify native
  names, roles, selected/disabled state, keyboard activation, and focus order.
  Do not add a custom accessibility framework as part of this repair.
- Metrics derive from window DPI. Recreate owned fonts on DPI/theme changes,
  honor the suggested DPI rectangle, and verify 100/150/200-percent layouts.
- Startup stages are explicit: profile ownership, native host, CEF browser,
  bound HTTP listener, usable control, protected readiness publication. An
  existing readiness record never proves this launch is ready. The exclusive
  profile handle is the ownership authority; any cleanup affects only this
  owned profile and shutdown removes only this launch's readiness record.
- Negative tests cover stale readiness replacement, publish failure, missing
  browser attachment, and failure/closure during startup. Diagnostics report
  stage and error without secrets. No success readiness on partial startup.

These are repairs to the existing native shell and reviewed runtime contracts.
No replacement UI framework, browser framework, or protocol redesign is in scope.
