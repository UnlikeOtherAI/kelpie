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
- The shell paints from one theme module (`apps/windows/src/theme/`) rather than from literal colours: a palette with light, dark and high-contrast variants named after the macOS semantic colours, per-window DPI metrics, a font cache keyed by DPI, size and weight, and antialiased rounded drawing through GDI+. Dark mode follows the system app theme, applies the immersive dark title bar, and rebuilds fonts and themed child controls on `WM_SETTINGCHANGE`, `WM_THEMECHANGED` and DPI changes. The traffic-light window controls keep their literal red, amber and green, which are the same in either appearance.
- Toolbar icons are Segoe Fluent Icons glyphs with a Segoe MDL2 Assets fallback, chosen to match the SF Symbols in the macOS toolbar. Icon buttons have hover, pressed, disabled and focused states. The address field shows the placeholder "Search or enter website name" and a lock glyph in a reserved left gutter. Unlike the macOS field, the lock is drawn only for `https`, so it never claims a secure transport that does not exist; the gutter is reserved either way so the text does not shift when the scheme changes.
- Tab pills share the strip like the macOS tab bar, clamped to 80–200 DIP so a single tab does not stretch across the window and a crowded strip stays readable. The strip is `TCS_FIXEDWIDTH`; without that style the tab control sizes every tab to its own label and the shared-width rule cannot apply. Pill width is recomputed when the tab set changes as well as on resize. The active pill is filled with the accent blended toward the canvas, so it follows the palette in both appearances.
- Tab pills show the page favicon, captured by Chromium itself through `OnFaviconURLChange` and `DownloadImage` (no cookies, capped at 32 DIP). The shell decodes it into a premultiplied 32-bpp bitmap in a 32-entry host-keyed LRU (`apps/windows/src/favicon_cache.{h,cpp}`) that deletes each bitmap on eviction. A site with no favicon falls back to a letter avatar (`apps/windows/src/letter_avatar.{h,cpp}`) using the same six colours and the same domain hash as the macOS `LetterAvatarView`, so one site is one colour on both platforms. A start page tab shows a star instead, matching macOS. `DrawTabIcon` is the single call the tab strip makes for the 14-DIP icon; it decides between star, favicon, and avatar in that order.
- New tabs open `kelpie://start`, Kelpie's start page, served as first-party content from a custom CEF scheme registered as standard, secure, CORS- and fetch-enabled. The page mirrors the macOS `StartPageView` — 120 px app icon with a 26 px corner radius and a soft shadow, an adaptive 72–96 px "Favourites" grid, a rounded "Recent" card of the last 20 history entries, the "Open a website to get started" empty state, and a 720 px content column — and follows light and dark through `prefers-color-scheme`. Its HTML, CSS, JS, and icon live in `native/engine-chromium-desktop/resources/start_page/` and are embedded at configure time. Bookmarks and history reach it as JSON on the same origin; no script is injected into any third-party page. The Windows page does not carry the macOS background watermark or the hover-to-delete control on history rows.
- The browser host can compile without a real CEF SDK. In that mode the shell still launches and the HTTP server still runs, but browser-engine methods that need the shared desktop Chromium runtime stay explicitly unsupported.
