# Kelpie — UI Documentation

## Index

| Document | When to Read |
|---|---|
| [mobile.md](mobile.md) | Building or modifying the browser app UI on iOS or Android |

---

## Design Principles

- **Minimal chrome** — the browser content is the focus, not the app UI
- **LLM-first** — the UI exists for human setup and monitoring, not daily interaction
- **Platform native** — SwiftUI on iOS, Jetpack Compose on Android, following platform conventions
- **Status at a glance** — connection state and device info visible without digging

## macOS Shell Notes

- The macOS app uses a fixed minimum browser shell and a separate centered viewport model.
- The macOS shell can grow larger than the minimum size, but viewport changes never shrink the native window below that minimum.
- Device presets simulate phone, tablet, and laptop viewports inside the shell instead of resizing the native window, and oversized viewports scroll instead of scaling down.
- Tabs and the native close/minimize/maximize controls share the top 32-point row. Fullscreen keeps tabs pinned in the content chrome while macOS hides its native titlebar. The window retains its page title for system menus. Viewport resolution is shown in the three-dot popup.
- The macOS shell shows the same welcome card used on iOS until dismissed, including the persisted "Don't show this again" preference, and the card can be reopened from `Help > Show Welcome Screen` even when that preference is enabled.
- The macOS `Help` menu also links to the Kelpie website, the GitHub repository, and `unlikeotherai.com`.
- The active macOS browser scene maps `Cmd+R` to a hard refresh. WebKit uses `reloadFromOrigin()`, and Chromium uses CEF's cache-bypassing reload path.
- MCP and HTTP `toast` messages render as a native bottom card in the macOS shell, not as an injected page overlay.
- The macOS navigation row contains back, forward, reload, Home, bookmark, native sharing, history and a trailing vertical three-dot popup. The popup holds Safari authentication, bookmark management, network inspector, settings, AI, 3D inspection and its controls, renderer, viewport preset, orientation and scale. It scrolls within a constrained height.
- The navigation row is 44 points high with a 28-point address field; favourites use a 29-point row. Native within-window blur gives the chrome its translucent background. On macOS 26+ full-size WebKit pages paint beneath it using public obscured-content insets, preserving the visible CSS viewport and screenshot coordinates. Chromium, older macOS and staged device viewports keep their reserved content area.
- A 24-point bottom status bar shows link destinations on hover and clears on pointer exit, scrolling or navigation. The native tracker uses one-shot DOM hit tests, including open shadow roots and same-origin frames; cross-origin frame links are not inspectable through that path.
- The chrome palette follows a tiny native WebKit snapshot of the visible top page edge on navigation and throttled scroll, using a foreground-resistant median in sRGB. One 200 ms transition drives background, selected tabs, text and toolbar icons together; it does not poll while idle or persist snapshots.
- History opens in a 320-by-420-point anchored popover matching the additional menu, with native hit targets for navigation and Clear history. The vertical ellipsis is a centered template image rather than a rotated view.
- The favourites row shows real saved bookmarks and is absent when there are none. Cmd+D, Add bookmark in the application or three-dot menu, and the address-field star save the active window’s current web page and reveal the row. Duplicate URLs and start pages are not saved. Clicking a favourite opens its stored URL; removing the last bookmark hides the row. The divider follows the bottom of the visible navigation/favourites area and uses the adaptive foreground at 10% opacity. Native WebKit underlap shrinks by the row’s 29 points when it is absent.
- Tabs remain pinned. Downward vertical wheel/trackpad scrolling inside the page hides navigation and favourites; the first upward scroll reveals them. Horizontal scrolling, popup scrolling and other windows do not affect this state. Navigation, Home, reload and tab selection also reveal the rows.
- Chromium keeps a single live tab title and close-window action, while WebKit supports the tab strip and new-tab control. The mockup website and avatar are not application content.
- The toolbar bookmarks, history, network, and settings buttons open native macOS sheets instead of leaving those actions as placeholders.
- The macOS bookmarks, history, and network sheets use explicit full-row hit targets, and the network sheet uses a single method dropdown above the request list instead of a dense chip row.
- iOS and Android mirror the same network-inspector simplification: the page document is recorded in the inspector, and the in-app filter is a compact method dropdown rather than a crowded strip of category chips.

## Windows Shell Notes

- The Windows reference chrome places tabs in a 52-DIP title row, with a single
  new-tab plus on the far left and minimize, maximize/restore and close on the
  right. A reserved gap remains draggable even when tabs overflow. Right-click
  the plus (or Shift+F10 while focused) for isolated tabs; Ctrl+Shift+N remains.
- Selected tabs have curved shoulders and outward feet meeting the navigation
  surface. Inactive tabs and the caption stay static light gray with fine separators.
  Real favicons, start-page stars, letter fallbacks, names and partition stripes
  are retained. Native tab selection, overflow, close buttons and tooltips remain.
- The 72-DIP navigation row has unboxed Back, Forward, Reload/Stop and Home
  controls, a 44-DIP pill address field with a secure-transport lock and
  Add favorite star, followed by bookmarks, network inspector, history and
  account and settings. Home uses the persisted home URL. The star stores the
  current page once, locally when signed out or in UOA when signed in.
- The native EDIT preserves IME, text selection, accessibility and inline
  history completion. Escape rejects completion; Enter accepts. Ctrl+L focuses
  the address. Ctrl+T/W/Tab/Shift+Tab retain their tab behavior after page focus.
- Favorites use the active local or UOA bookmark list. The 44-DIP row exists only when it
  has entries, opens entries with one click and moves excess entries to a menu.
  Changes through HTTP/MCP refresh it without requiring navigation. Showing or
  hiding favorites changes the browser viewport height by 44 DIP, so automation
  should acquire fresh screenshot coordinates after changing the bookmark set.
- Chromium captures the current viewport without changing its dimensions,
  then samples the top 24 pixels into a soft chrome tint twice per second. This follows actual
  backgrounds, images, video and gradients as the page scrolls. A single bounded
  request runs off the CEF owner thread and drains before engine teardown. URL,
  document time origin, scroll position and navigation/selection epochs discard
  stale results. No listeners or persistent page scripts are installed. Colors
  ease over 220 ms; reduced animation and high contrast are respected. Utility
  panels continue to use the system palette.
- A single physical-pixel separator sits immediately above the browser. It is
  black over light chrome or white over dark chrome at 10% opacity, and follows
  the same color transition as the surrounding surface.
- Dimensions and fonts scale with each window's DPI. Caption controls retain
  native accessibility and keyboard focus. Maximize respects the monitor work
  area. The custom accessible caption buttons do not provide Windows 11's
  native Snap Layout hover flyout; dragging to screen edges remains available.
- New tabs open the shared Chromium start page at `kelpie://start`, with
  favorites and recent history. Settings retains **Isolate every new tab**,
  off by default. Panels, settings, native toasts, agent control and Chromium's
  sandbox continue to use the existing Windows runtime.

Windows remembers window size, position and maximized state in the profile.
Maximization preserves access to auto-hide taskbars.

The account menu opens hosted UOA sign-in in the external browser using PKCE.
It shows identity/avatar, pending sign-in, sync errors, refresh and sign-out.
Signed-in favorites preserve metadata and retry version conflicts; failed saves
retain the visible list. Sign-out restores local favorites without uploading
them. Tokens and account data remain in memory; only the public client ID and
callback port are cached. Signing in is deliberately outside browser-control APIs.

On Mac and Windows, only the selected tab carries the sampled page color.
Inactive tabs and the full title strip stay opaque light gray in every theme;
inactive labels and caption controls retain dark ink for contrast.

## Linux Shell Notes

The Chromium GTK shell follows the Windows geometry: a 52-pixel static gray title
strip with left-hand plus, curved active tab and right-hand window controls;
a 72-pixel navigation row and 44-pixel address pill; and a 44-pixel favorites row
that disappears when empty. Native GTK controls retain keyboard and IME input.
Tabs support favicons, names, close controls, overflow, isolated storage markers,
Ctrl+T/W/Tab/Shift+Tab and Ctrl+Shift+N. Settings includes Isolate every new tab.

Only the selected tab and rows below it adopt the active page's top-edge color.
The inactive tabs and title strip remain gray. Color changes ease over 220 ms,
and a one-pixel contrasting divider uses 10% opacity. Sampling reads the active
CEF paint buffer; background and stale-generation paints cannot replace it.
Native select popups compose separately from the page buffer.

The account menu provides hosted UOA PKCE sign-in in an external browser,
identity/avatar, favorites refresh and sign-out. Local favorites remain separate.
The shared desktop runtime provides authenticated HTTP/MCP, tab leases, storage
partitions, trusted input, DOM/evaluation, screenshots, dialogs and inspection.
Full persistent tab sessions restore on restart; transient partitions do not.
Shutdown drains account and browser work before removing readiness and GTK views.

For VNC verification on a host running both Wayland and X11, launch with
`GDK_BACKEND=x11 DISPLAY=:2` to select the VNC desktop explicitly.
