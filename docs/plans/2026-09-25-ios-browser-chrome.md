# Native iPhone and iPad browser chrome

Scope: the requested iPhone and iPad redesign. Android is outside this request;
this is an explicit platform-specific design, not a change to the browser API.

The existing bottom bar mixes tab management and navigation. It puts iPad tabs
at the bottom, adds a tab when the tab-count button is pressed, and offers no
overview. Its content-offset observer also treats viewport resizing and rubber
banding as scrolling, so animating its height can feed back into its own state.

## Design

- iPad owns a persistent top strip: curved shoulder tabs, page icon/title and
  close controls, plus New Tab. Tabs have bounded widths and horizontal overflow;
  selection scrolls the active tab into view. Closing the last tab uses the
  existing TabStore replacement behavior.
- Both devices own one bottom navigation surface: circular back/forward,
  capsule address and reload, Share, Bookmarks and More. More preserves history,
  settings, Safari authentication, AI, network inspection and viewport tools.
  Use native SwiftUI materials and SF Symbols; adapt spacing to real safe areas.
- User scrolling collapses the bottom surface to a small domain capsule. Tap
  expands it. Ignore layout-driven offsets, top/bottom bounce and background
  tabs. Navigation and tab selection expand it. Address editing locks it open.
- Upward drag from the phone address surface opens an in-app two-column tab
  overview; More also provides an accessible button entry. Native snapshots
  preview the tabs. Horizontal card swipes dismiss tabs; vertical motion scrolls
  the grid. Each card also has a close button. Selecting returns to browsing.
- Reuse the Mac RGB palette, median strip sampler and 200ms color transition by
  making their platform adapters explicit. No persistent page scripts or idle
  sampling. Capture completions must reject stale tab/navigation generations.
- Respect Reduce Motion, Dynamic Type, keyboard safe area, VoiceOver labels and
  44-point actions. Keep page content out from behind interactive controls.

## Verification

Targeted scroll-state and gesture-threshold tests, strict Swift lint, iOS
simulator build and native UI verification on iPhone and iPad: expanded and
collapsed toolbar, keyboard, overflow, active close, grid selection/swipe close,
and light/dark page-color transitions. A native app cannot be verified by a
Playwright screenshot of a substitute web page.

## Cross-Provider Review

Claude reviewed the design before implementation; a second independent review
examined the integration. Accepted: user-pan-only scroll detection, fixed WebView
geometry with overlay clearance, cached visible-tab previews, individual tab
observation, stale callback/removal guards, keyboard-safe layout, preservation
of all existing tools, and decomposition of BrowserView. The top strip remains
on iPad even in narrow windows as explicitly requested; its tabs scroll rather
than disappearing. Phone controls adapt by moving Share/Bookmarks into More
when the address would become too narrow. Native 44-point targets take priority
over the illustration's nonphysical scale.

The user's iPhone/iPad scope governs this change; no additional parity approval
is needed. Shared palette/sampling code uses explicit UIKit/AppKit adapters,
retaining the Mac transition clock to keep the requested transition identical.
On iPad we sample the visible top edge, as on Mac. iPhone uses neutral native
material. The WebView stays fixed during collapse; only bottom content/indicator
clearance changes. Preset geometry therefore stays stable. Native UIKit
directional pan recognizers arbitrate card swipes and address upward gestures
before recognition; the home-indicator safe area is never a gesture target.
`browser.tabs.count` now opens the overview and `browser.tabs.add` creates tabs.
Documentation and the iOS version update ship with the implementation.

## Implementation and verification

Implemented in SwiftUI/UIKit with shared Mac palette/sampler adapters. The iOS
bundle is 0.1.5 (5). Native unit tests, iPhone and iPad simulator journeys, strict
Swift lint, and pnpm lint/build/test pass on the development hosts. The iPad
journey covers eight overflowing tabs and the active close control. Both Debug
simulator and unsigned Release device builds compile. Generated projects now
receive the bundle identity/version and launch metadata required for installation.

The KiloMayo signing team is `59S95D279D`. Signed Release archive/export and
physical installation of 0.1.4 succeeded on the iPhone 16 Pro Max and iPad Air
13-inch (M3). Migrating the older apps from their previous signing team required
app container backups before reinstalling; settings and saved tab counts were
verified after restoration. The app and welcome icons match the current
multicolour K artwork.

Follow-up: the address capsule retains one view identity while its geometry
shrinks and moves. Surrounding controls and material fade out; no separate
compact view is inserted. Domain text stays centered through the motion;
editing reveals the complete URL. Version 0.1.5 carries this refinement.

The physical devices on iOS 26.6.2 reported UIKit touch-delay exceptions during
scroll-triggered toolbar replacement. The persistent address surface avoids
removing its recognizer mid-scroll. Directional observers do not delay or cancel
underlying control touches, and overview presentation waits until the current
touch dispatch finishes. The UI journey now repeats collapse/expand cycles and
asserts that the app remains in the foreground; physical-device runs are part
of verification for this regression.

The iPad palette applies only to the active tab. The remaining strip and inactive
tabs stay neutral. Browser keyboard avoidance uses UIKit's keyboard layout guide
with `followsUndockedKeyboard = false`, so floating keyboards do not create a
bottom gap. The native UI checks distinguish floating from docked keyboards.
