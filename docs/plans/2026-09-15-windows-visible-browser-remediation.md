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

## Checkpoint review findings

The first drawing checkpoint is not visual acceptance. Complete these within the
existing repair batches and verify their actual final implementation:

- The original owner loop refreshes browser state after every Windows message.
  Unconditional SetWindowText/InvalidateRect calls from the shell then invalidate
  controls again after a paint. Compare unchanged state before updating controls;
  a hidden-native regression must show identical state does not perpetuate paint.
  This is a plausible contributor to the preview's high CPU use, not a measured
  attribution of its entire CPU cost.
- WS_TABSTOP does not implement traversal for a normal top-level window. Provide
  a real Tab/Shift+Tab path for chrome controls while preserving page key input
  and Ctrl+Tab tab switching; check native keyboard activation and return focus.
- Use per-window DPI for geometry and owned regular Segoe UI fonts. GDI
  LOGPIXELSX is shared across monitors and cannot supply per-monitor scaling.
  [Microsoft DPI contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow),
  [GDI device-capabilities contract](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-getdevicecaps).
- Native edits must sit inside their rounded presentation surfaces. High-contrast
  highlighted fills use their matching text colors. All font/brush owners release
  replaced resources and refresh persistent controls on DPI/theme changes.
- The protected-file regression shows the previous replacement sequence can
  succeed. It does not establish where the observed launch stalled. Invalidate
  predecessor readiness after exclusive ownership, record concrete failure stages,
  and use the next live launch to resolve the original publication failure.
- Report the complete actual CTest result. The first visual-build log contained
  22 passing tests and one failed network-event test, despite an initial green
  summary. That executable imports libcef.dll; its nested test directory and
  test environment need a verified dependency search path. Diagnose the exit
  cause before changing adapter logic or claiming the entire suite passed.

### Final close ordering

An ingress flag alone is insufficient: an already admitted settings or bookmark
mutation can finish after persistence and receive success for a change that is
then lost. Reuse the HTTP server's worker-drain lifecycle instead of classifying
individual routes. Request listener stop without joining; keep the owner pump
active until all admitted handlers have retired; persist once while stores and
tabs exist; then drain CEF and release owners. A scheduled owner retry must
progress a close whose first drain attempt is incomplete. Cover an in-flight
non-engine mutation and an incomplete-then-complete close in targeted tests.

This is the final follow-up in the current repair scope. It does not establish
live shutdown, restart, rendering, or visual acceptance by itself.

### Final close-ordering checkpoint

Implemented on `codex/windows-browser-recovery` after the historical
`207857383b4cd7c3bc45cf28408661002c14c375` checkpoint. The listener now waits
until its server thread is active before `Start` succeeds, closes admission
idempotently, retires already-admitted `/v1` and MCP handlers without blocking
the native owner, and reports drained only after its worker thread has exited.
Windows persists session, stores, and settings only after that drain, then
retries bounded CEF shutdown from an owner timer until it completes.

The native Release build and all 29 CTests passed, including a held `set-home`
request that completes before drain while a later mutation is refused, and the
close lifecycle sequence that waits for drain, persists once, then completes on
a retry. This does not replace the required user-assisted live browser review.
