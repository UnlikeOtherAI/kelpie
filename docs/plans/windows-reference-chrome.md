# Windows reference chrome

## Intent and diagnosis

Use the supplied Horizen screenshot as the Windows browser-chrome reference,
with a new-tab plus in the empty upper-left space. The website in the screenshot
is page content, not a replacement start page. Keep Kelpie's working browser
commands and stores. macOS supplies the interaction reference (tabs, favicons, history completion,
favorites, settings and inspector), including live page-edge colors.

The existing Windows layout reserves separate title, navigation and tab rows;
it draws traffic lights and bordered buttons. Changing colors alone cannot
produce the reference. The layout, non-client hit testing and painting must
share the same geometry. Existing favicon helpers are not wired into the shell.

## Design

- One 52-DIP caption/tab row. A 56-DIP leading slot contains a single plus;
  its context menu and Ctrl+Shift+N retain isolated-tab creation. Standard
  minimize, maximize/restore and close controls occupy the right edge.
- Tabs begin 8 DIP below the top and meet the navigation surface. Selected
  tabs have curved upper corners and outward curved feet; inactive tabs are
  transparent against the caption material with subtle vertical separators.
  Keep native tab selection/overflow, close buttons, tooltips and keyboard use.
- A 72-DIP navigation row with unboxed 20-DIP icons and a 44-DIP rounded
  address field. Preserve native EDIT, IME and completion. Add a Home action;
  keep bookmarks, history, network and settings usable rather than decorative
  screenshot-only features. Use real favicons and existing letter fallbacks.
- A 44-DIP favorites row only when the bookmark store is nonempty. Existing
  bookmarks are the favorites source; each opens its URL. Overflow is a menu.
  An add-favorite action uses the existing bookmark store and persistence.
- A single physical-pixel separator immediately above the page, formed by
  compositing the contrasting black/white color at 10% over the chrome.
- A per-window chrome palette, separate from utility-panel/system palettes.
  Sample the active page's visible top edge using a bounded, ephemeral CDP
  viewport capture and metadata reads (no listeners or persistent scripts). Smoothly transition over
  220 ms, retaining the previous valid sample on transient failures. Ignore
  results belonging to old tab leases or URLs. Limit sampling to two times
  per second with one request in flight; do not block the UI/CEF pump. Derive
  selected tabs from the navigation surface and inactive tabs from the caption
  surface. The user refined the reference: the caption and inactive tabs stay static light gray (RGB 229,234,243), on both Windows and macOS. Respect high contrast and
  reduced animation. Keep the last valid color when captures are unavailable.
- Split shell tabs/painting out of the already oversized shell file along
  responsibility boundaries. Keep each changed source under 500 lines.

## Verification

Native tests cover layout/hit testing, caption controls, empty/nonempty
favorites, overflow, tab colors, separator blending, animation retargeting,
and stale sample rejection. Run the sandboxed CEF build and Windows CTest,
then inspect the running app and exercise tabs, navigation, completion,
favorites, caption controls and light/dark pages. Verify loopback MCP and
alias bridge, readiness cleanup, and CLI lint/build/tests before release.

## Cross-Provider Review

Reviewed by Claude Code and an independent Codex reviewer before implementation.
Accepted: protect child-window hit tests as well as the parent; reserve a drag
gap; correct maximized work-area geometry; own the entire tab-strip paint;
derive all chrome foregrounds from luminance; cache the EDIT brush; keep the
separator outside the browser HWND; refresh bookmarks independently of URL
changes; and discard stale samples using a navigation/selection epoch.

Use a single bounded asynchronous request against the existing engine API,
drained before runtime teardown while the owner continues pumping. This avoids
adding a second asynchronous API to the shared engine. Retain accessible native
caption buttons rather than replacing them with inaccessible painted regions;
native Snap Layout flyout support is outside this change. Use a reserved drag
gap and child forwarding for resize edges. The favorites row must disappear
when empty as explicitly requested; document the resulting viewport resize.
Retain existing internal JSON tab transport for now rather than widen this UI
change into an engine/delegate refactor. Sampling remains bounded polling to
follow scroll-driven page-edge changes, which event-only sampling would miss.

## Implementation refinement

The first live check showed CSS-only sampling missed propagated body backgrounds.
CEF Alloy resizes its live native renderer when a CDP screenshot clip is used.
Capture the existing viewport with no clip or emulation, then sample its top
24-pixel band as a low-pass backdrop. Ephemeral evaluation
only reads viewport metadata. Verify URL, time origin and scroll before/after
capture, in addition to the owner epoch. This handles images and gradients too
and requires no shared-engine API change.

The upstream integration preserves its tested maximized-work-area calculation
and window-placement persistence. The shell explicitly supplied `about:blank`
to new-tab requests, overriding the engine start-page default; removing that
override restores the documented behavior for the plus and keyboard shortcut.
