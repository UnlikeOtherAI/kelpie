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
- The native window title mirrors the current page title, and the titlebar shows the live viewport resolution in a pill aligned to the right.
- The macOS shell shows the same welcome card used on iOS until dismissed, including the persisted "Don't show this again" preference, and the card can be reopened from `Help > Show Welcome Screen` even when that preference is enabled.
- The macOS `Help` menu also links to the Kelpie website, the GitHub repository, and `unlikeotherai.com`.
- The active macOS browser scene maps `Cmd+R` to a hard refresh. WebKit uses `reloadFromOrigin()`, and Chromium uses CEF's cache-bypassing reload path.
- MCP and HTTP `toast` messages render as a native bottom card in the macOS shell, not as an injected page overlay.
- macOS has no floating menu: Safari/Chrome auth, bookmarks, history, network inspector, and settings are AppKit-backed icon buttons in the top toolbar, next to reload, the AI status pill, and the 3D inspector.
- The toolbar bookmarks, history, network, and settings buttons open native macOS sheets instead of leaving those actions as placeholders.
- The macOS bookmarks, history, and network sheets use explicit full-row hit targets, and the network sheet uses a single method dropdown above the request list instead of a dense chip row.
- iOS and Android mirror the same network-inspector simplification: the page document is recorded in the inspector, and the in-app filter is a compact method dropdown rather than a crowded strip of category chips.

## Windows Shell Notes

- The Windows shell uses the shared custom frame with normal Windows resize, maximize, and system-menu behavior. Its native toolbar follows the desktop visual system: 34-DIP icon controls on a 50-DIP row, 12-DIP outer padding, and a separate rounded tab row. Native buttons retain accessible names, tooltips, and keyboard focus; bare `Tab` / `Shift+Tab` traverse native chrome once it has focus and stay with the renderer during ordinary page form traversal. Tabs have native close buttons tied to their stable tab models. The shell also hosts the child browser, a native settings dialog, a native toast card, and separate bookmarks/history/network inspector utility windows. `Ctrl+T`, `Ctrl+W`, `Ctrl+Tab`, `Ctrl+Shift+Tab`, and `Ctrl+L` remain available after page focus.
- The URL bar keeps a native `EDIT` control for IME, selection, and UI Automation, inside a painted rounded surface with a focus ring. Its history completion is an inline selected suffix, offered only for a typed insertion at the end of unselected text; deletion, paste, IME composition, and text replacement do not offer a completion. Escape rejects and Enter accepts it. Browser chrome and panel controls use the owning window's DPI, support per-monitor moves, and use system colors in high contrast. Bookmarks, history, network, settings, and toast surfaces use the same native color, spacing, and typography helpers. The network inspector mirrors the three desktop/mobile filter groups: Method, Type, and Source.
- Per-tab storage isolation is reachable from the chrome, not only the API. The `+` control is a split button: the plus opens an ordinary tab, the chevron beside it offers "New tab" and "New isolated tab", and `Ctrl+Shift+N` opens an isolated one directly. An isolated tab gets a freshly generated partition id, so each one is a separate identity.
- A partitioned pill carries a 2-DIP accent stripe along its foot — the always-visible sign that the tab does not share the default store — and prints the tab's `name` in place of the page title when one was set. Its tooltip shows the real page title, the partition id, and whether that partition is in memory only. In high contrast the stripe uses the system highlight colour so it never disappears into the fill.
- Settings has an **Isolate every new tab** toggle, off by default. Isolating every tab would break ordinary browsing — a login would not carry into a tab opened from a link — so the shared store stays the default and the toggle is the opt-in for separate identities.
- The browser host can compile without a real CEF SDK. In that mode the shell still launches and the HTTP server still runs, but browser-engine methods that need the shared desktop Chromium runtime stay explicitly unsupported.
