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
- Floating menu actions show custom black hover pills with a grey border and short labels instead of native macOS tooltips.
- The floating menu now opens native macOS sheets for bookmarks, history, network inspection, and settings instead of leaving those actions as placeholders.
- The macOS bookmarks, history, and network sheets use explicit full-row hit targets, and the network sheet uses a single method dropdown above the request list instead of a dense chip row.
- iOS and Android mirror the same network-inspector simplification: the page document is recorded in the inspector, and the in-app filter is a compact method dropdown rather than a crowded strip of category chips.

## Windows Shell Notes

- The Windows shell is a Win32 `WS_OVERLAPPEDWINDOW` host with a 32px toolbar, child browser host, native settings dialog, native toast card, and separate bookmarks/history/network inspector utility windows.
- The URL bar uses native `EDIT` and `BUTTON` controls, and the network inspector mirrors the three desktop/mobile filter groups: Method, Type, and Source.
- The browser host can compile without a real CEF SDK. In that mode the shell still launches and the HTTP server still runs, but browser-engine methods that need the shared desktop Chromium runtime stay explicitly unsupported.
