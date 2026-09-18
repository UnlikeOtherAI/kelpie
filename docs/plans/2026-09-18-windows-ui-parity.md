# Windows UI parity with macOS

**Goal:** Make the Windows Kelpie app look and behave like the macOS app: styled chrome
instead of stock Win32 controls, a Safari-style pill tab strip with favicons, a rounded
toolbar, light/dark theming, a start page, styled utility panels, and per-tab storage
isolation. Everything ships on the existing sandboxed CEF runtime and the reviewed
tab-lease / local-token contracts from
[2026-09-15-windows-shipping.md](2026-09-15-windows-shipping.md).

**Non-goals:** AI panel, 3D inspector, viewport presets/stage, renderer switching,
Safari auth, multi-window, pairing dialog. These are macOS features that either do
not apply on Windows or are separate feature work. They are listed at the end so the
parity gap stays visible; they are not part of this plan.

---

## 1. Where things stand (evidence, 2026-09-18)

### `main`

`apps/windows/` (~4.5k lines) has: the custom undecorated frame with macOS-style
close/minimize/maximize dots (`window_chrome.cpp`), a stock `SysTabControl32` tab strip
**above** the URL bar, stock `EDIT`/`BUTTON` controls with `DEFAULT_GUI_FONT`, a Menu
button that opens a popup menu, separate top-level windows for bookmarks/history/network,
a native settings dialog, and a toast. There is no theme module, no dark mode, no favicons,
no start page, and no runtime-style selection for child browsers. Every tab is created
with the global CEF request context (`CreateBrowserSync(..., nullptr)`), so all tabs share
one cookie jar and storage. This is the "WinForms" look the user rejected.

### Unmerged branches

| Branch | Ahead of main | What it holds |
|---|---|---|
| `codex/windows-browser-recovery` | 29 commits | **Superset** of `windows-visual-parity`, `windows-qualification-control`, `windows-mcp`, `windows-security-tests`, `windows-ship-plan`. Adds `ui_theme.h` / `panel_theme.h` (palette, DPI, Segoe UI fonts, rounded GDI paint, high-contrast), owner-drawn 40x34 DIP toolbar buttons, a 50 DIP toolbar **above** the tabs, per-tab close buttons and tooltips, Tab/Shift+Tab focus order, `owner_task_queue`, `windows_runtime.cpp` split out of `windows_app.cpp`, explicit Alloy-style child browsers, startup stage diagnostics, HTTP admission drain before close, input/cookie planners, DevTools network events, `scripts/{download-cef,build,package}-windows.ps1`, and 29 passing CTests. |
| `origin/codex/windows-qualification` | 13 commits, separate lineage | Release acceptance harness (`tests/windows/*.mjs`: process control, PNG decode, sandbox proof), strict Unicode helpers, navigation cancellation tests. Never integrated. |
| `codex/windows-runtime` (local) | 3 commits | `dd2423f`, `4e99aca`, `fe77559` — also present in the recovery branch's history. |

`git merge-tree main codex/windows-browser-recovery` conflicts in 10 files:
`apps/windows/CMakeLists.txt`, `resources/resource.h`, `src/session_snapshot.cpp`,
`src/win32_shell.{h,cpp}`, `src/window_chrome.{h,cpp}` (add/add), `src/windows_app.cpp`,
`tests/session_snapshot_test.cpp`, `docs/ui/README.md`.

Main's `6e88526` landed after the branch diverged and must survive the merge: the
`RunWinMain` export, the no-CEF build fix, `RequireBoundedInteger` widening,
`ParseSessionSnapshot` rejecting negative values, Windows-only tool availability, the CLI
`--tab-generation` and `--browser <alias> mcp` fixes, and the `screenshot-annotated`
support listing.

The branch's own review docs record that the last **live** preview (`cecd3e9`) failed:
gray content area, "Chromium runtime unavailable", stale readiness token. The later
commits (Alloy style, startup stages, close ordering) are the fix, but no live launch of
the combined build has been observed. Unit tests did not catch that failure.

### Per-tab partition contract

[2026-05-16-per-tab-partition-and-name.md](2026-05-16-per-tab-partition-and-name.md)
defines `new-tab { name, partition, persistent }`, `get-partitions`, `delete-partition`,
the partition validator, and error codes. `grep partition` finds **no implementation** in
`packages/shared`, `packages/cli`, `native/`, or `apps/macos`. macOS tabs share one
`WKWebView` data store today. Windows will be the first platform to implement it.

### Toolchain on this machine

VS 2026 Community is installed. The pinned CEF `152.0.6+g708dc14` SDK is already cached at
`.worktrees/windows-runtime/.cache/cef_binary_152.0.6+g708dc14+chromium-152.0.7977.83_windows64_minimal`.
The branch's `scripts/build-windows.ps1` initialises the VS environment via `vswhere`,
builds the wrapper with `USE_SANDBOX=ON` and `/MT`, and runs CTest.

---

## 2. The macOS reference, measured

Values come from `apps/macos/Kelpie/Views/{URLBarView,TabBarView,AppKitComponents,StartPageView}.swift`.
"DIP" on Windows equals "pt" on macOS at 100 %.

| Element | macOS spec | Windows target |
|---|---|---|
| Window | Standard titled window; title mirrors page title | Keep the existing custom frame and dots (already on `main`, matches Nessie); title mirrors page title; dark frame via `DWMWA_USE_IMMERSIVE_DARK_MODE` |
| Toolbar row | 12 pt horizontal / 8 pt vertical padding, 8 pt gaps, controls 34 pt tall | Same: 50 DIP row, 34 DIP controls, 8 DIP gaps, 12 DIP padding |
| Icon button | 40x34, corner 8, fill `controlBackgroundColor`, 0.5 pt border `separatorColor` at 45 %, 14 pt semibold SF Symbol, hover fill `separatorColor` at 18 %, disabled alpha 0.55, selected fill `selectedControlColor` at 92 % with white icon | Owner-drawn `BUTTON`, anti-aliased rounded rect, Segoe Fluent Icons glyph (MDL2 fallback), same states |
| Toolbar buttons | back, forward, reload, address, [AI pill], [3D], safari-auth, bookmarks, history, network, settings, [device preset], [renderer] | back, forward, reload/stop, address, bookmarks, history, network, settings. Bracketed items are macOS-only or out of scope |
| Address field | 34 pt, corner 15 continuous, lock glyph 10 pt, 13 pt text, placeholder "Search or enter website name", inline grey completion suffix, focus ring | Native `EDIT` inside an anti-aliased rounded surface; lock glyph only for `https`; 13 DIP Segoe UI; 2 DIP accent focus ring; inline completion stays the selected-suffix form that passed review (native `EDIT` cannot paint a grey ghost suffix without replacing the control) |
| Tab bar | 34 pt, **below** the toolbar, pills spread to fill and clamp 80–200 pt, scroll on overflow, + button 28 wide on the right | Same geometry; custom strip child window; horizontal scroll on overflow |
| Tab pill | corner 8; active fill `selectedControlColor` at 8 %; sliding indicator layer fill at 18 % / stroke at 35 %, 0.22 s ease-in-out; 14 pt favicon or letter avatar; 12 pt regular title truncating tail; 16 pt close "xmark" 8 pt bold; star for start page | Same; indicator animated with a 60 Hz timer for 220 ms; favicon from CEF or letter avatar |
| Letter avatar | 14 pt square, corner 3, 9 pt bold white letter, colour = `palette[hash(domain) % 6]` with the 6 HSB colours in `LetterAvatarView` | Same palette converted to RGB, same hash |
| Colours | System dynamic colours: light and dark follow the OS | Palette struct with light, dark, and high-contrast variants; switch on `WM_SETTINGCHANGE` (`ImmersiveColorSet`) |
| Start page | App icon 120 pt corner 26 with shadow; "Favourites" grid of bookmark tiles (72–96 pt adaptive); "Recent" list of the last 20 history rows on a rounded material card; empty state "Open a website to get started"; max width 720 | Same layout, served to the tab as a first-party page (see §3.7) |
| Utility panels | Native sheets over the window; full-row hit targets; network sheet has Method/Type/Source dropdowns | Owned, frameless, rounded panel windows styled from the same theme; full-row `ListView` hit targets; same three filters |
| Toast | Native bottom card, 3 s | Same, themed |
| Welcome card | Shared with iOS; "Don't show again"; reopen from Help | Phase 6, themed native dialog |

---

## 3. Decisions

### 3.1 Base: integrate `codex/windows-browser-recovery`, do not redo it

The recovery branch already contains the theme module, owner-drawn toolbar, focus order,
Alloy-style children, and the lifecycle fixes. Rewriting that from `main` would repeat two
weeks of work and re-introduce the failed-preview bugs. Phase 0 merges it onto `main`,
resolves the 10 conflicts in favour of keeping every `6e88526` fix, and proves the result
with a live launch before any visual work starts.

### 3.2 Rendering: native HWNDs, anti-aliased drawing

Keep native `BUTTON` / `EDIT` / `ListView` controls for accessibility, IME, keyboard, and
tooltips (the constraint the earlier reviews set). Replace the GDI `RoundRect` primitives
in `ui_theme.h` with GDI+ (`Gdiplus::Graphics` from the owner-draw `HDC`,
`SmoothingModeAntiAlias`, alpha fills) so rounded corners, borders, and hover states are
smooth like AppKit layers. Text stays on GDI `DrawText` with ClearType. GDI+ ships with
Windows; no new framework. Direct2D can replace it later behind the same primitives if
needed, but is not required for parity.

### 3.3 Tab strip: custom child window with native pills

`SysTabControl32` owner-draw still paints its own frame and cannot express pills, a
sliding indicator, or overflow scrolling the way `TabBarView` does. Replace it with a
`TabStripView` child window that:

- creates one owner-drawn `BUTTON` per tab (accessible name = tab title, tooltip = URL) and
  one owner-drawn close `BUTTON` per tab, so screen readers and Tab traversal work without
  a custom UI Automation provider;
- paints the indicator and pill backgrounds on the strip surface and animates the
  indicator with a 220 ms timer;
- computes widths exactly like `TabBarCoordinator.relayout` (spread, clamp 80–200,
  scroll when dense, keep the active pill visible);
- handles middle-click close, Ctrl+T / Ctrl+W / Ctrl+Tab / Ctrl+Shift+Tab (already wired),
  and Ctrl+1…9 to jump to a tab.

The strip moves **below** the toolbar (the recovery branch already did this; `main` has
tabs above).

### 3.4 Theme: light, dark, high-contrast

`ui_theme.h` grows into a `theme` module: `Palette` gets light and dark variants (dark
follows `HKCU\...\Themes\Personalize\AppsUseLightTheme`), high-contrast keeps system
colours, and the shell re-reads the palette, recreates fonts/brushes, applies
`DWMWA_USE_IMMERSIVE_DARK_MODE`, and calls `SetWindowTheme(hwnd, L"DarkMode_Explorer")` on
`EDIT`/`ListView` children on `WM_SETTINGCHANGE` and `WM_DPICHANGED`. All metrics use
per-window DPI (`GetDpiForWindow`), never `LOGPIXELSX`.

### 3.5 Icons

Replace the Unicode glyph buttons (`‹ › ↻ ★ ◷ ⌁ ⚙`) with Segoe Fluent Icons code points
(Windows 11) with a Segoe MDL2 Assets fallback (Windows 10), at 14 DIP semibold to match
SF Symbols weight. Mapping: back `E72B`, forward `E72A`, reload `E72C`, stop `E711`,
bookmarks `E734`, history `E81C`, network `E968`, settings `E713`, new tab `E710`,
close `E711`, lock `E72E`.

### 3.6 Favicons

`engine-chromium-desktop` implements `CefDisplayHandler::OnFaviconURLChange` and calls
`CefBrowserHost::DownloadImage` (16/32 px, PNG). `TabSnapshot` gains an optional
`favicon_png` field; the shell caches decoded `HBITMAP`s by host with a small LRU and
falls back to the letter avatar. macOS already does the equivalent in `FaviconExtractor`.

### 3.7 Start page

New tabs open `kelpie://start`, a custom CEF scheme (`CefRegisterSchemeHandlerFactory`)
that serves bundled HTML/CSS mirroring `StartPageView` (icon header, Favourites grid,
Recent list, empty state) and reads bookmarks/history from a JSON resource on the same
scheme backed by the shared stores. The tab pill shows the star, the address field shows
empty text, and `get-tabs` reports the URL as `kelpie://start`. This is first-party
content rendered by the same CEF process, not a content script injected into third-party
pages, so it does not violate the "no persistent content scripts" rule. A native GDI
start page was rejected: it would cost more and look worse than the SwiftUI original.

### 3.8 Per-tab isolation

Implement the reviewed 2026-05-16 contract on the shared desktop core so it later ports to
macOS unchanged:

- **Shared types and validator:** `packages/shared/src/partition.ts` (the validator from
  the plan), `NewTabRequest.{name,partition,persistent}`, `TabInfo.{name,partition}`,
  `get-partitions`, `delete-partition`, error codes `INVALID_PARTITION`,
  `PARTITION_UNSUPPORTED`, `PARTITION_DELETING`, `PARTITION_IN_USE`. CLI flags
  `kelpie tab new --name --partition --ephemeral`, MCP tool schemas, and docs.
- **CEF mapping:** one `CefRequestContext` per partition, created with
  `CefRequestContextSettings.cache_path = <profile>/partitions/<id>` for persistent
  partitions and an empty `cache_path` (in-memory) for ephemeral ones, passed as the
  `request_context` argument of `CreateBrowserSync`. Tabs without a partition keep the
  global context (shared, Chrome-like behaviour). Popups inherit the opener's context, so
  isolation holds across `window.open`. Cookies already go through per-tab DevTools
  sessions, so `get-cookies`/`set-cookies` are partition-scoped without changes.
  localStorage, IndexedDB, and cache follow `cache_path`.
- **Registry:** `PartitionRegistry` on the owner thread tracks id → context, tab count,
  persistent flag, and a `deleting` state. `delete-partition` closes the tabs, releases the
  context, deletes the directory; if Chromium still holds file locks the directory is
  renamed to `partitions/.trash/<id>-<epoch>` and purged on next launch. Snapshot
  persistence records each tab's partition so restore rebinds it.
- **Native UI:** the `+` button gets a split-menu "New tab / New isolated tab"; isolated
  pills carry a 2 DIP accent stripe under the avatar and show `name` instead of the title
  when set; the tooltip shows the partition id. Settings gains "Isolate every new tab"
  (default **off**) for users who want Nessie-style identities from the shell.

Default remains **shared**. Isolating every tab by default would break ordinary browsing
(logins would not carry into link-opened tabs) and diverge from what the API contract
promises other platforms. The settings toggle covers the opposite preference.

### 3.9 Utility panels stay owned windows, restyled

macOS uses sheets. On Windows, converting bookmarks/history/network/settings into
in-window overlays would mean fighting CEF's child HWND for z-order. Keep them as owned
windows but make them frameless, rounded (`DWMWCP_ROUND`), themed, with the
`PaintPanelHeader` hierarchy, full-row hit targets, empty states, and the three network
filters. Settings becomes a themed panel with the same sections as macOS minus
Renderer/AI/HuggingFace: Device, Network, Connect, App, Experimental.

---

## 4. Phases

Each phase is one PR from its own `.worktrees/<name>` checkout, small commits, pushed
immediately. Sizes: S ≈ a day, M ≈ 2–3 days, L ≈ a week, for one implementer.

### Phase 0 — Integrate and prove the baseline (M)

1. Merge `codex/windows-browser-recovery` onto `main`; resolve the 10 conflicts keeping every
   `6e88526` fix; confirm `git log main..codex/windows-runtime` is empty afterwards.
2. Cherry-pick the acceptance harness from `origin/codex/windows-qualification`
   (`tests/windows/**`, `tests/windows/README.md`) and make it run against the merged build.
3. `scripts/build-windows.ps1` Release with sandbox, all CTests, `pnpm lint && pnpm build && pnpm test`.
4. **Live launch** by the user of the packaged build: page pixels visible, fresh readiness
   record, authenticated `get-tabs` / `evaluate` / `screenshot` succeed, Ctrl+L focuses
   Kelpie's field, clean close. Screenshot recorded in the PR.
5. Delete `codex/windows-{visual-parity,ship-plan,browser-recovery,qualification,qualification-control,runtime,mcp,security-tests}`
   and `origin/codex/nessie-window-chrome` locally and remotely once their content is on `main`.

Gate: the previous failed-preview symptoms are gone on a real launch. No visual work starts
before this.

### Phase 1 — Theme and drawing foundation (M)

`apps/windows/src/theme/{palette,metrics,paint,icons}.{h,cpp}` replacing `ui_theme.h` and
`panel_theme.h`: light/dark/high-contrast palettes, per-window DPI, font cache, GDI+
rounded primitives, Fluent/MDL2 glyph lookup, theme-change notification. Dark-mode frame
and child controls. Tests: palette selection, DPI math, hidden-HWND paint smoke tests in
the `windows_shell_preview_test` style.

### Phase 2 — Toolbar parity (M)

Address surface, icon buttons, reload/stop swap, https-only lock, focus ring, hover/pressed/
disabled/selected states, tooltips, keyboard order. Remove the Menu button; the four action
buttons match macOS. Compare against the macOS toolbar at 100/150/200 %.

### Phase 3 — Tab strip parity (L)

`TabStripView` per §3.3, letter avatars, indicator animation, overflow scroll, middle-click,
Ctrl+1…9, strip below toolbar. `win32_shell.cpp` loses the `SysTabControl32` code and stays
under 500 lines. Tests: width math, active-pill visibility, keyboard cycling, hidden-HWND
paint.

### Phase 4 — Favicons and start page (M)

Engine favicon capture (§3.6), `kelpie://start` scheme and bundled page (§3.7), star pill
state, history/bookmark JSON resource, `new-tab` without URL opens the start page.

### Phase 5 — Per-tab isolation (L)

Shared types, validator, CLI/MCP, C++ mirror, `PartitionRegistry`, request-context mapping,
snapshot persistence, deletion with trash fallback, native "New isolated tab" and settings
toggle, docs (`docs/api/browser.md`, `docs/cli.md`, `docs/functionality.md`). Requires a
cross-provider review before implementation because it changes the HTTP/MCP surface.

### Phase 6 — Panels, toast, settings, welcome card (M)

Restyle per §3.9, themed toast card, first-launch welcome card with "Don't show again" and
a Help entry to reopen it.

### Phase 7 — Release (S)

Bump `VS_VERSION_INFO` to `0.2.0`, package via `scripts/package-windows.ps1`, date-tagged
GitHub release, install and re-run the acceptance harness against the published ZIP,
update `docs/ui/README.md` Windows notes and `README.md` status table.

---

## 5. Verification

Per phase:

- `scripts/build-windows.ps1` (Release, `USE_SANDBOX=ON`), full CTest, `pnpm lint && pnpm build && pnpm test`.
- Hidden-HWND layout/paint tests for every new surface; no test may pass by skipping when
  CEF is absent.
- Side-by-side screenshot of Windows vs macOS for the surface the phase touches at 100 %,
  150 %, 200 % DPI in light, dark, and high-contrast, attached to the PR.
- Accessibility: Inspect.exe shows names/roles for every button and tab pill; Narrator
  reads tab titles; Tab/Shift+Tab visits toolbar → strip → page and back.

Final (Phase 7):

- Acceptance harness over direct MCP and CLI stdio: tabs, navigation, eval, screenshot
  decode, cookies, dialogs, console/network, bookmarks/history.
- Isolation: two partitions on one origin, cookie set in A invisible in B; localStorage
  likewise; ephemeral partition empty after restart; persistent partition intact after
  restart; `delete-partition` wipes the directory; popup from an isolated tab stays isolated;
  `TAB_REQUIRED` and lease semantics unchanged.
- Sandbox proof on the packaged artifact (existing harness check).
- User-assisted live review against the macOS app on the same pages.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| Conflict resolution silently drops a `6e88526` fix | Enumerate each fix in the Phase 0 PR and point at the surviving line; `dumpbin /EXPORTS` and the no-CEF configure run in CI |
| Live preview still fails after merge | Phase 0 gate; startup-stage diagnostics from the branch identify the stage; nothing else proceeds |
| Custom strip loses accessibility vs `SysTabControl32` | Native `BUTTON` per pill; Inspect.exe check is a PR requirement |
| GDI+ paint cost on a 60 Hz indicator timer | Double-buffer the strip surface only; stop the timer when idle |
| Dark mode on native `EDIT`/`ListView` | `DarkMode_Explorer` theme plus `WM_CTLCOLOR*` brushes; verified at Phase 1 |
| Chromium holds partition files at delete time | Trash-rename and purge on next launch; `delete-partition` reports `existed`/`tabsClosed` truthfully |
| Per-monitor DPI with mixed child HWNDs | Manifest already declares PerMonitorV2; all metrics through `Dip(hwnd, …)`; 100/150/200 % checks per phase |
| `kelpie://start` leaks into history/bookmarks | History store ignores the `kelpie` scheme; macOS `isStartPage` semantics mirrored in `TabSnapshot` |

---

## 7. Parity backlog (not in this plan)

Welcome card and insecure-page warning could follow Phase 6 cheaply. AI panel, 3D
inspector, viewport presets and stage, orientation, renderer switch, Safari auth, multi-window
and `windowId`, pairing dialog, and scripted video recording remain macOS-only or are
platform-inapplicable. Keep `docs/functionality.md` honest about each.

---

## Cross-Provider Review

Pending. Per AGENTS.md this design needs an adversarial review from a different provider
before Phase 1 implementation starts (Phase 0 is integration of already-reviewed work).
Phase 5 additionally needs its own review because it changes the HTTP/MCP surface.
