# macOS reference browser chrome

## Problem and scope

The current shell puts dense developer controls before the page and hides tabs until a second tab exists. The supplied reference instead has a pale tab strip at the top, a white navigation row with a long rounded address field, a bookmarks row, and a right-hand vertical three-dot popup. This change applies to the macOS shell, not to web content or the mobile UI.

## Design

- Put the existing native tab controls above navigation and keep a single tab visible. Host this compact 32-point row in a native titlebar accessory beside the native traffic lights, with a transparent full-size titlebar. In fullscreen, where macOS hides titlebar accessories, show the same tab view in the content chrome and hide the native accessory. Preserve dragging, window sizing, keyboard commands, per-window ownership and tab accessibility. Chromium remains single-tab: show its live page title and disable new-tab actions there.
- Use a pale blue-gray tab background, white selected tab, subtle separators, dark outline navigation icons, and a 28-point rounded address field in a 44-point navigation row (40% smaller per follow-up). Keep actual website titles and favicons. Retain adaptive dark appearance.
- Keep back, forward, reload, home, bookmark and history actions visible. Home opens the existing start page. Add native page sharing only when a navigable HTTP(S) URL exists. The mockup's avatar and website are not app data; do not create dead download/profile controls.
- Per user follow-up, mock the favourites row using the reference labels/icons, without persisting fake bookmarks. Mock entries navigate to illustrative public destinations; Add bookmark saves the real current page. Overflow scrolls horizontally; all entries remain reachable. Keep real bookmark management in the popup.
- Move Safari authentication, AI, 3D inspector and its controls, network inspector, settings, renderer, viewport presets, orientation and scale into the right-hand three-dot popup. Reuse existing callbacks and state. Group controls vertically to avoid overflow; provide current viewport resolution there instead of the titlebar badge.
- Use AppKit-backed buttons throughout the chrome and popup, preserving WebView-first-responder hit testing. No full-window AppKit overlays. Keep the address text editing/completion path intact, and show a lock only for HTTPS.
- Keep tabs pinned. A window-scoped native scroll-wheel observer over the renderer hides the address/favourites rows on downward vertical scroll and reveals them on the first upward scroll. Ignore horizontal scroll and events outside this window's renderer; do not consume events or inject page scripts. Navigation reveals the rows. Use a clipped height transition; keep tabs stable.
- Keep recording's chrome suppression, pairing, welcome, sheets, and server/API behavior intact. No protocol changes.

## Verification and delivery

Run strict Swift lint, CLI lint/build/tests, and native macOS tests/build. Launch one known app instance and inspect the rendered shell at normal and minimum widths; click controls after page focus, tabs, bookmarks and popup actions; check WebKit. Chromium verification is excluded by the user for this session. Update functionality/UI docs, bump macOS only, push one PR, merge after green checks, publish the macOS artifact in a dated GitHub release, install the published bundle in /Applications and verify it.

## Cross-Provider Review

OpenAI read-only source review completed. Accepted corrections:

- Home must load about:blank through the active handler, then present the existing start-page overlay and suppress stale page actions. Never reconnect hidden WebKit in Chromium mode.
- Use RendererContainerView's existing monitor lifecycle, matching window and visible renderer bounds, ignoring horizontal input and returning original events. Reveal explicitly for reload, Home and tab selection as well as URL changes.
- Keep Chromium's single-tab title and close-window action independent of WebKit's retained TabStore.
- Popup sheets/auth/engine switches close the popup first. Preserve all existing capability guards, and constrain popup height with scrolling.
- Shared window bridge owns full-size titlebar setup for every window. Remove resolution accessory; show resolution in popup. Drag only empty tab-strip space; verify fullscreen and recording.
- Refresh tab labels after published state changes, including custom names.
- Mock favourites never enter BookmarkStore. Real bookmark additions reject start pages and duplicates.

Claude review attempt failed because its OAuth session expired. Alternate-provider GLM review could not complete: provider returned HTTP 429 (insufficient balance). Cross-provider review remains unavailable; the completed independent OpenAI source review informed the implementation. This limitation is recorded rather than claiming the provider review passed.

## Translucent underlap follow-up

The user requests Safari-style page content visible beneath the blurred top chrome, and favourites height reduced by 40% (48 to 29 points). Use a native NSVisualEffectView with within-window blending behind the controls, not an opaque tint or a screen snapshot. On macOS 26+ full-size WebKit browsing, extend the renderer beneath the 32-point tab row and visible 73-point navigation/favourites area, and set WKWebView.obscuredContentInsets.top to that amount. This public API adjusts the layout viewport and fixed/sticky elements. Reset the inset outside that mode (recording, staged viewport, engine switch). Scope effect views to chrome backgrounds and let them pass hit tests through to controls.

Verify the initial page top, sticky headers, downward hide/upward reveal, click coordinates and screenshots before accepting. If native inset changes screenshot coordinates, align the renderer snapshot crop with the visible viewport. Chromium and older macOS must retain the reserved viewport until an equivalent native inset exists; never inject persistent CSS/scripts into arbitrary websites to fake it.

Keep ViewportStageView's measured visible viewport unchanged: underlap expands only its renderer content upward via negative padding. Remove the unnecessary outer scroll view and clip in full mode; keep the staged viewport scroll view and clip. Snapshot dimensions must use the visible viewport height excluding the inset, preserving their dimensions and CSS-coordinate contract. Add a native WebKit geometry test before accepting this path.

Native WebKit verification confirmed that snapshot origin remains zero (the layout viewport origin); adding the obscured top inset to the snapshot origin incorrectly crops page content. The regression test checks a coloured marker, DOM hit testing, CSS height and screenshot dimensions at expanded and collapsed insets.

The bottom 24-point status bar displays hovered link destinations. Native pointer tracking evaluates a short-lived DOM hit test after movement, clears on exit/scroll/navigation and cancels stale requests. No persistent page listener is installed. Same-origin frames and open shadow roots are traversed; inaccessible cross-origin frame contents cannot disclose a destination through this WebKit API.

## Validation results

- Strict Swift lint passes for iOS and macOS; CLI lint, build and all 541 CLI/shared tests pass.
- All 70 native macOS tests pass, including scroll direction and WebKit obscured-inset geometry, DOM hit testing, hover destination extraction and snapshot pixel/dimension regression checks.
- Debug and Apple Silicon Release builds succeed. Existing build-script dependency and baseline compiler warnings remain; this is not a warning-free build.
- Rendered WebKit checks confirm top-aligned native tabs, compact address/favourites rows, page-focus-safe popup actions, downward collapse, immediate upward reveal, page colour beneath active-window glass, and the bottom status bar displaying the hovered GitHub Pricing URL and clearing afterward. Home then Back restores the previous page. Fullscreen entry retains the tabs, and exiting restores the native tabs beside window controls.
- A selected-tab colour mismatch was traced to resolving a dynamic NSColor outside the view's effective appearance. Pass the content colour scheme into the native titlebar accessory, resolve layer colours in that appearance and refresh on appearance changes.
- The extra native CTest run passes 18 of 20; pre-existing Release assertions in test_ai_hf_cloud and test_ai_store fail. No native C++ source changed.
- An accessibility-driven Chromium check encountered a CEF trap in a nested AppKit event loop. The user explicitly excluded Chromium investigation and verification for this session. No Chromium fix or successful Chromium verification is claimed.
- This release is Apple Silicon only and ad-hoc signed, without Developer ID notarization. Other component versions remain unchanged.
