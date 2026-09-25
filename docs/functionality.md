# Kelpie — Feature Catalogue

Every user-facing feature is described here. When adding or changing a feature, update this file in the same commit.

For information about browser engine availability by platform and Apple's regulatory requirements for alternative engines, see [browser-engines.md](browser-engines.md).

---

## How It Works

Kelpie has two parts: **native browser apps** (iOS, Android, macOS, Linux, and an in-progress Windows shell) and a **Node.js CLI**. The apps run real browsers with embedded HTTP and MCP servers. The CLI discovers them on the local network via mDNS and sends commands. An LLM can control everything through the CLI's MCP server — or talk to device MCP servers directly.

No emulators, no cloud, no persistent scripts. Real browsers on real devices, fully controllable by language models.

## Device Discovery

Every running Kelpie app advertises itself via mDNS (`_kelpie._tcp`) on the local network. The CLI auto-discovers all devices and exposes their metadata: device name, model, platform, screen resolution, port, and app version. Devices can be targeted by name, ID, or IP address. Apps prefer port `8420`, but if that port is already occupied they bind the next available local port and advertise the actual port they chose. When mDNS misses a same-host macOS browser, the CLI probes recorded local ports plus `8420`–`8429` and accepts only targets whose automation API answers `/v1/get-device-info`; `discover`, `devices`, `info`, and untargeted commands all share that fallback. On macOS, advertisement remains up for the lifetime of the running app instance. On iOS and Android, the app re-establishes mDNS advertisement whenever it returns to the foreground so discovery recovers after background suspension.

Works identically with real devices, iOS Simulators, and Android Emulators — a developer with no phones can spin up multiple simulators at different screen sizes and control them all.

## Pairing & Authentication

Every Kelpie device denies API and MCP traffic by default. Only the discovery endpoints (`/v1/pair`, `/v1/pair/status`, `/v1/get-device-info`, `/health`) accept unauthenticated requests; everything else requires a bearer token issued by the on-device user.

**Pairing flow.** When the CLI hits an unauthenticated endpoint and gets a `401`, or when the user runs `kelpie pair <device>` explicitly, the CLI posts a pairing request to the device. The device shows a modal with the requester's self-reported client name and offers three responses:

- **No** — the device denies the request. The CLI surfaces `PAIR_DENIED` and stores nothing.
- **Yes, once** — the device issues a session-scope token. The CLI keeps it in process memory and drops it at exit. The user must re-approve on the next CLI invocation.
- **Always** — the device issues a persistent-scope token. The CLI writes it to `~/.kelpie/tokens.json` (mode `0600`, directory `0700`) keyed by `deviceId:host:port`. Subsequent invocations reuse it transparently.

The device returns the plaintext token exactly once; only a SHA-256 hash is persisted on the device. Status polling is keyed by a 32-byte CSPRNG `requestId` and bound to the source address that started the request, so a different host cannot collect the resulting token. Pinning the stored token to `deviceId:host:port` defends against mDNS TXT-record spoofing — if a device id reappears at a different socket address, the CLI refuses to send the stored token and forces re-pairing.

**Paired clients list.** Every platform's settings panel shows the list of currently paired clients (name, scope, last seen) and lets the user revoke any of them, which immediately invalidates that token on the device.

**MCP transport.** The CLI's `kelpie mcp --http` mode binds `127.0.0.1` by default. Binding to a non-loopback address requires the explicit `--unsafe-host` flag, which prints a warning before listening. Stdio transport is unchanged.

API: `POST /v1/pair`, `GET /v1/pair/status?requestId=…`; CLI: `kelpie pair`; MCP: `kelpie_pair`.

## Browser Control

Full navigation control: go to any URL, go back/forward, reload, get the current page URL and title. The browser uses Safari's user agent on iOS, Chrome's on Android, Chromium on Linux, and on macOS can switch between Safari/WebKit and Chrome/Chromium behavior so sites behave normally — Google OAuth, banking sites, and similar services work without being blocked as a WebView.

On macOS, the desktop URL bar stays synced with both API/MCP-triggered navigation and user-driven page navigation, uses a pale top tab strip alongside the native close/minimize/maximize controls, an outlined navigation row and rounded address field, autocompletes previously visited URLs inline as you type, supports native fullscreen toggling for the active window from the Window menu or with `Cmd+F`, and maps `Cmd+R` to a hard refresh in both WebKit and Chromium so cached desktop state can be cleared without switching renderers. On Linux, the GTK shell matches the Windows title-strip tabs, outlined navigation controls, rounded address field, conditional favorites row and UOA account menu.

On Linux, the desktop shell runs in either GUI or headless mode. Both Chromium modes expose the shared authenticated loopback HTTP/MCP surface, persist profile-backed bookmarks, history, full tab sessions and a home page URL. They do not advertise the loopback listener over mDNS. The no-CEF build retains its limited legacy runtime. In GUI mode, the browser window can also be toggled into fullscreen via API/MCP. Published GitHub releases now attach Linux `.tar.gz`, `.deb`, `.rpm`, and `.AppImage` artifacts automatically and refresh Debian/Ubuntu `apt` plus Fedora-compatible `dnf` package repositories on GitHub Pages from the same release event.

On Windows, the desktop shell under `apps/windows/` now combines an undecorated rounded Win32 frame (maximized, it fills the monitor's work area exactly, clearing the taskbar and leaving an auto-hide taskbar reachable) with Windows-style minimize/maximize/close controls, a native tab strip, URL bar, native settings dialog, bookmarks/history/network inspector windows, native toast overlay, and the shared Chromium desktop runtime. Like macOS, it remembers the window size, on-screen position, and maximized state across launches in the profile's `settings.json`: the saved position is reused only when at least 120x40 px of the window still lands on a connected monitor, otherwise Windows places it, and explicit `--width`/`--height` flags override the remembered size. A failed startup (for example an occupied `--port`) shows its reason in the window; a launch started hidden exits with a failure code instead. Its agent-control server listens only on loopback and requires the per-launch capability from the protected readiness file. Windows screenshots are viewport PNG only; full-page, JPEG, and annotated screenshot requests return an explicit unsupported-parameter error. Console/network logs and viewport size are browser-wide state, so those methods reject `tabId` and `generation` rather than silently using a different tab.

The Windows shell places curved tabs in the title bar, a new-tab plus at the top left, and window controls at the top right. The navigation row has unboxed controls and an IME-capable rounded address field. Home opens the saved home URL; the address-field star adds the current page to favorites. The favorites row disappears when empty and offers an overflow menu when crowded. Rendered page-edge colors animate into the chrome, with a one-pixel separator at 10% contrasting opacity. Native accessibility, high contrast, DPI scaling, tab shortcuts and inline history completion remain available. See [Windows shell notes](ui/README.md#windows-shell-notes) for sampling limits and viewport behavior.

### Safari / Chrome Authentication

One-tap login using the device's saved passwords. On iOS, opens an ASWebAuthenticationSession (Safari's login sheet) that shares Safari's saved passwords and cookies. On Android, uses Chrome Custom Tabs. After login, cookies are synced back into the browser automatically.

### Persistent Home Page

Every platform keeps a persisted home page URL. Fresh launches load that URL instead of a hard-coded blank tab, and automation can change it remotely with `set-home` / `get-home` or the matching CLI commands `kelpie home set` / `kelpie home get`.

## Renderer Switching (macOS)

Switch between Safari (WebKit), Chrome (Chromium/CEF), and Firefox (Gecko) rendering engines at runtime. Available via the UI segmented control and the `set-renderer` / `get-renderer` HTTP endpoints. Cookies are migrated automatically when switching to preserve login sessions.

Gecko uses a Firefox runtime bundled inside Kelpie.app (`Frameworks/KelpieGeckoHelper.app`) — no external Firefox installation required. Run `make gecko-runtime` once during setup to download and strip the runtime. The bundled binary is driven headless via the Firefox Remote Protocol (CDP-compatible WebSocket). The live view shows the Firefox-rendered page via screenshots at ~5fps.

## External Display — Apple TV (iOS)

When an iPhone or iPad running Kelpie connects to an Apple TV via AirPlay, the app automatically detects the external screen and displays a fullscreen WKWebView on it. This external browser appears as a separate device in mDNS discovery with the name "{device} (TV)" on port 8421, fully controllable from the CLI independently of the main device. No UI chrome — just the web content, controlled entirely via the API. The phone UI also exposes a sync control that mirrors the phone browser onto the TV: page URL, cookies, storage-backed session state, and scroll position all stay aligned so the TV follows the same browsing session instead of acting like a separate login context. A landscape touchpad remote with a visible cursor and inertial swipe scrolling is also available. When the AirPlay connection drops, the external server and window are torn down automatically.

## Screenshots

Capture viewport or full-page screenshots on demand in PNG or JPEG. Full-page mode now works across iOS, Android, and macOS, each using its renderer's native mechanism: iOS takes an unclipped `WKWebView` snapshot of the full content, Android paints the whole document into a full-height bitmap via `WebView.draw`, and macOS scrolls-and-stitches the page viewport-by-viewport (covering both the WebKit and Chromium renderers). Quality is adjustable for JPEG. Screenshot responses now include explicit viewport-mapping metadata: viewport width and height, device pixel ratio, and computed image-to-viewport scale factors. That makes the coordinate space visible to LLMs instead of forcing them to guess from image size alone.

### Annotated Screenshots

Take a screenshot with numbered labels overlaid on every interactive element (buttons, links, inputs). The LLM sees both the image and a structured list of what each number corresponds to, plus an annotation session ID and validity hint. Then it can say "click element 5" or "fill element 12 with hello@example.com" — visual-first automation without needing CSS selectors. For LLM use, Kelpie prefers CSS-pixel/non-retina annotated screenshots so the image payload is smaller and the coordinate system lines up with interaction APIs more directly. Annotation indices are valid until the page URL changes; after navigation, Kelpie returns `ANNOTATION_EXPIRED` and expects a fresh annotated screenshot.

## DOM Access and Queries

Full read access to the page DOM. Query elements by CSS selector, get their text, attributes, bounding boxes, and visibility. Retrieve the full DOM tree from any root element with configurable depth. All queries return structured data, not raw HTML.

## Element Interaction

Click elements by selector or tap at specific coordinates. Fill form inputs, type text character-by-character (simulating human typing with per-character delays), select dropdown options, check/uncheck checkboxes. Every interaction shows a blue touch indicator animation on the device so you can see what happened.

For LLM-driven automation, the intended order is semantic first: read the accessibility tree or use the smart find endpoints, then interact by selector. If the model needs to reason over an image after it already knows the selector, Kelpie can draw a visible highlight box/ring around that exact DOM element and then capture a screenshot, which keeps the visual target and the selector aligned. Annotated screenshots are the broader visual fallback when semantic targeting fails. Raw coordinate taps exist for edge cases and are intentionally the least-preferred option because they drift with viewport changes, scrolling, and overlays. Selector clicks and annotation clicks now dispatch coordinate-bearing pointer and mouse events at the rendered hit target instead of shortcutting through `el.click()`, so DOM-targeted automation exercises the same observable interaction path as raw taps and fails with a visibility error when the target center is obscured. When raw taps do drift, every shipped app build now includes a bundled local calibration page at `/debug/coordinate-calibration` that shows manual tap coordinates, previews requested versus applied automation taps, and persists additive X/Y offsets used by the raw `tap` endpoint.

Swipe gestures are first-class too: give Kelpie start and end viewport coordinates and it renders a visible swipe trail while dispatching synthetic pointer events to JS-driven touch listeners. For native scrolling, use the scroll endpoints instead.

For regression debugging, `coordinate-diagnostics` combines hit-test samples, page-side event logs, optional tap/swipe/scroll actions, viewport metadata, optional oracle JavaScript, and optional screenshot capture into one structured response. It reports `inputSource` and `inputCapabilities` explicitly; today the mirrored iOS, macOS, and Android implementation uses page-synthesized coordinate events, not trusted OS-level input.

## Scripted Video Recording

Kelpie can run a whole walkthrough as one timed script instead of one command at a time. A script enters recording mode, hides the browser chrome, locks the normal controls, and leaves only a stop button visible while it plays. Actions can mix navigation, taps, typing, swipes, waits, screenshots, viewport changes, commentary pills, and element highlights. This scripted-recording surface is now aligned across Android and iOS, with the same HTTP, CLI, and MCP entry points.

The main use case is support and presentation work: record a few clean steps that show a customer exactly where to click, how to reach a setting, or how to complete a workflow, then hand over the resulting walkthrough video instead of writing a long email.

The feature is exposed through `play-script`, `abort-script`, and `get-script-status`, with matching CLI commands (`kelpie script run`, `kelpie script status`, `kelpie script abort`) and MCP tools. Commentary and highlight overlays are also available as standalone commands and tools, so an LLM can narrate or spotlight a page without running a full script.

## Scrolling

Scroll by pixel deltas, scroll a specific element into view (with configurable alignment: top/center/bottom), or jump to the top or bottom of the page. The `scroll2` method is resolution-aware — it adapts its behavior based on the device's viewport size.

## Wait and Synchronisation

Wait for an element to appear, become visible, or disappear — with configurable timeout. Wait for page navigation to complete. Essential for reliable automation when pages load dynamically.

## JavaScript Evaluation

Execute arbitrary JavaScript in the page context and get the result back. Use it for anything the built-in methods don't cover.

## Console and Error Capture

Read console output (log, warn, error, info, debug) from the page. Get JavaScript errors with full stack traces. The console bridge captures everything including unhandled promise rejections on iOS, macOS, and Android. Messages buffer up to 5,000 entries — clearable on demand.

## Network Monitoring

Two levels of network visibility:

**Performance timeline** — uses the browser's Performance API to get resource loading data: URLs, methods, status codes, MIME types, sizes, and detailed timing breakdowns (DNS, TCP, TLS, waiting, download). The `get-network-log` `type`, `status`, and `since` filters and the aggregate `summary` block are now honored consistently across iOS, Android, and macOS.

**WebSocket monitoring** — tracks active WebSocket connections created by the page, including URL, ready state, negotiated protocol, sent/received message counters, and a bounded recent-message buffer with timestamps and direction. The monitoring data is best-effort page observability rather than an authoritative packet trace, and on macOS it is available on the WebKit renderer path.

**Network Inspector** (new) — a Charles Proxy-style traffic viewer built into the app. See below.

## Network Inspector

A built-in network traffic viewer accessible from the floating menu. Captures all HTTP/HTTPS requests and responses flowing through the loaded website.

**List view:** every request shows its HTTP method (GET, POST, PUT, DELETE, OPTIONS, etc.), URL, status code, content type, category, duration, and size. The app records the top-level page document alongside fetch/XHR traffic, so a normal page load always appears in the inspector. Three filter dropdowns: **Method** (All Methods, GET, POST, PUT, DELETE), **Type** (All Types, HTML, JSON, JS, CSS, Image, Font, XML, Other), and **Source** (All Sources, Browser, JS (fetch/XHR)). The Source filter distinguishes browser-initiated requests (page loads, subresources) from JavaScript-initiated requests (fetch, XHR). URL search is also available. All three platforms (iOS, Android, macOS) have identical filter sets.

**Detail view:** drill into any request to see the full picture — request method, URL, headers, query parameters, and body. Response status, headers, and body (formatted for JSON). Timing: start time, duration, bytes transferred. On Android and Chromium-backed macOS views, top-level document rows may have partial metadata where the native web view does not expose a full response.

**LLM integration:** the LLM can list and filter captured traffic, navigate to a specific request by index or URL pattern, and read its full details. When the user is viewing a specific request in the inspector, the LLM knows exactly which one and can debug it — inspecting headers, payloads, and response data.

API: `network-list`, `network-detail`, `network-select`, `network-current`, `network-clear`.

## 3D DOM Inspector

**Experimental**. On iOS and Android the 3D inspector is visible by default and can be turned off in Settings. On macOS it stays opt-in until enabled in Settings (Experimental section) or with `KELPIE_3D_INSPECTOR=1`. No restart required.

A visual debugging tool for inspecting element stacking and layer order. Click the 3D button in the floating menu (or call the `snapshot-3d-enter` endpoint) to explode the page DOM into a 3D layered view. Every element is pushed along the Z-axis based on its depth in the DOM tree, making it easy to see which elements overlap, identify invisible overlays blocking interaction, and understand the page structure.

**Controls:**
- **Native rotate mode** (`hand` tool) — pointer drag or one-finger drag rotates the scene
- **Native scroll mode** (`vertical arrows` tool) — pointer drag or one-finger drag scrolls the underlying page while staying in 3D mode
- **Pinch** on iPad and Android tablets — zoom the 3D camera in either mode
- **Scroll wheel / trackpad scroll** — zoom in rotate mode, scroll the page in scroll mode
- **Native `Zoom +`, `Zoom -`, `Reset`, and `Exit` controls** — available from the shell instead of injected page chrome
- **Hover** — highlight element and show tag, classes, dimensions, position, z-index, stacking context
- **+ / -** keys — increase or decrease layer spacing
- **R** key — reset rotation and zoom to default
- **Escape** or native exit button — exit 3D mode and restore the page

The 3D view shows DOM depth (tree nesting), not CSS paint order. Position, z-index, and whether the element creates a stacking context appear in the hover info panel. User interactions are suppressed while in 3D mode, but background page logic (timers, network callbacks) may still execute. The page is restored to its original state on exit. Works with both WebKit and Chromium renderers.

**Limitations:** Canvas, WebGL, and video elements appear as opaque layers. Cross-origin iframes appear as labeled blocks (showing the iframe's domain). Closed shadow DOM roots are not traversable. Hover detection degrades at steep rotation angles. Pages with more than 5,000 visible elements are capped with a warning toast.

API: `snapshot-3d-enter`, `snapshot-3d-exit`, `snapshot-3d-status`, `snapshot-3d-set-mode`, `snapshot-3d-zoom`, `snapshot-3d-reset-view` (MCP: `kelpie_snapshot_3d_enter`, `kelpie_snapshot_3d_exit`, `kelpie_snapshot_3d_status`, `kelpie_snapshot_3d_set_mode`, `kelpie_snapshot_3d_zoom`, `kelpie_snapshot_3d_reset_view`).

## Bookmarks

Saved URLs accessible from the floating menu. Fully controllable through the MCP and CLI — an LLM or user can add, remove, list, and clear bookmarks remotely. Tapping a bookmark navigates the browser to that URL. Persisted across app restarts. Primary use case: push project URLs from the CLI so you can tap to navigate without typing.

API: `bookmarks-list`, `bookmarks-add`, `bookmarks-remove`, `bookmarks-clear`.

## History

Chronological log of every URL navigated to. Auto-recorded from real navigation changes inside each tab or browser surface instead of from tab selection state, so switching tabs does not create false history writes and revisiting a URL moves it back to the top cleanly. Viewable from the floating menu, clearable by the user or via API. Stores up to 500 entries, persisted across restarts. If a navigation is recorded before the page title settles, the latest history entry self-updates once the final title arrives, so rows do not stay blank or half-populated.

API: `history-list` (with limit), `history-clear`.

## Start Page (macOS, Windows, Linux)

New tabs open Kelpie's own start page instead of a blank document. It shows the
app icon, a "Favourites" grid of bookmark tiles, a "Recent" list of the last 20
history entries, and the "Open a website to get started" empty state when both
are empty. It follows the system light and dark appearance. Clicking a tile or a
row navigates that tab.

On macOS the page is the SwiftUI `StartPageView`. On Windows and Linux it is the same
layout served to the tab as first-party content from Kelpie's own `kelpie://`
scheme, which the browser registers as standard, secure, CORS- and
fetch-enabled. The page reads its bookmarks and history from `data.json` on that
same origin — it is not a script injected into a third-party page, and no bridge
script is involved. Favicons already downloaded this session appear on the tiles
and rows; a site without one shows a coloured letter tile.

A tab on the start page reports its URL as `kelpie://start` from `get-tabs`, and
its tab pill shows a star instead of a favicon. `new-tab` without a `url` opens
it, as does the `+` button, the first tab at launch when no home page is set, and
the replacement tab left behind after the last tab is closed.

The `kelpie` scheme is never recorded in history and cannot be bookmarked, so the
start page never appears inside its own Favourites grid or Recent list.

## Favicons (macOS, Windows, Linux)

Each tab shows the page's favicon in its pill. macOS fetches it per host and
caches it on disk; Windows takes it from Chromium itself — the browser reports
the page's icon URLs and downloads them without sending cookies, keeping the 32
px representation where the site offers one and the 16 px one otherwise. Icons
are cached by host, so every tab on a site and every start page row for it share
one image.

A tab whose site has no favicon yet shows a letter avatar: the first letter of
the host, white on one of six colours chosen deterministically from the host
name. macOS and Windows use the same palette and the same hash, so a given site
is the same colour on both.

## Floating Menu

The floating menu is used on iOS and Android. On macOS these same actions live as icon buttons directly in the top toolbar instead (see the macOS section below).

A 44-point circular flame button, vertically centered on the screen edge. Horizontally draggable — swipe it left or right so it's never in the way. Tap to expand a fan of icon-only menu items in a wide half-circle: reload, Safari/Chrome auth, bookmarks, history, network inspector, AI status, 3D inspector, and settings. The fan radius grows automatically with the number of visible actions so newly added buttons do not overlap. On tablets, the fan also includes a phone icon that opens a pill picker anchored off that icon instead of toggling immediately. The picker uses the same sorted fitting preset list shown by the iPad `View` menu and MCP APIs, including phone, tablet, and laptop classes when they fit the current device geometry. Pills use full visible labels such as `6.1" Compact`, `11" iPad Pro`, and `13" Laptop`, and they flow into extra columns outside the fan lane so they do not cover the action buttons. Tapping the active pill again returns the browser to full width. Opens with a blur overlay behind it.

## LLM-Optimised Queries

Purpose-built methods that return semantic data instead of raw HTML:

- **Accessibility tree** — ARIA roles, labels, states, and nesting. What a screen reader sees.
- **Visible elements** — only what's currently in the viewport, optionally filtered to interactive elements only. Up to 200 elements with positions.
- **Page text** — reader-mode text extraction: title, content, word count, language.
- **Form state** — snapshot of every form on the page: fields, values, validation state, which required fields are empty.
- **Smart find** — find a button, link, input, or any element by its visible text or label. No selectors needed.

When those semantic methods are not enough, Kelpie also provides an annotated screenshot workflow: the app returns a screenshot plus numbered interactive elements, and the LLM can act on those indices with `click-annotation` or `fill-annotation` instead of guessing raw coordinates.

## Local AI

On-device LLM inference across all platforms. Seven HTTP endpoints (`ai-status`, `ai-load`, `ai-unload`, `ai-infer`, `ai-record`, `ai-catalog`, `ai-fitness`) and corresponding MCP tools let language models query local AI without sending data to the cloud. `ai-catalog` returns the approved on-device model catalog and `ai-fitness` scores a model against a device's RAM/disk — both are supported on iOS, Android, and macOS and require a HuggingFace token configured on the device. On iOS and Android, AI remains available from the browser shell while the visible URL-bar shortcut is reserved for the 3D inspector.

**macOS — native GGUF + Ollama + HF Cloud:** The CLI manages GGUF model downloads from HuggingFace (`kelpie ai pull`). The macOS app loads them via llama.cpp on Apple Silicon. An inference harness runs a lightweight agent loop (max 3 tool calls) so 2B models can request page data on demand instead of receiving everything upfront. Audio recording captures 16kHz mono PCM (max 30s) for voice input. Intel Macs get Ollama-only mode. HF cloud inference is available as a third backend when a token is set.

**iOS — Apple Intelligence + Ollama:** Platform AI (Foundation Models framework) is the default backend on supported hardware. Text-only until the iOS 26 SDK is linked. Users can switch to a remote Ollama model for vision-capable inference.

**Android — Gemini Nano + Ollama:** Platform AI (Google AI Edge SDK) is the default backend on Android 14+ hardware. Text-only until the SDK is integrated. Users can switch to a remote Ollama model for vision-capable inference.

**Hugging Face Token:** Gated models (e.g. Gemma) require a HF access token. On macOS, a "Set HF Token" button appears in the AI panel's Models tab (NATIVE section header). When a download fails due to missing auth, the browser navigates to `huggingface.co/settings/tokens` and the error message guides the user to set their token. The token is stored in UserDefaults and sent as a `Bearer` header on all HF download and cloud inference requests.

**HF Cloud Inference:** When a HF token is set, models available on the HF Inference API can be queried remotely without downloading. The cloud client posts to `api-inference.huggingface.co/models/{id}` and returns the generated text with timing metadata. Supports prompt, chat-message, and raw HF input formats.

**Shared AI Library (`native/core-ai`):** Model catalog, fitness evaluation, HF token management, and shared model-store helpers live in a shared C++ library. Apple apps use URLSession for authenticated downloads, Ollama, and HF cloud inference; Linux and Windows keep the cpp-httplib path.

**CLI model management:** `kelpie ai list` shows approved models and their download status, plus any locally running Ollama models. `kelpie ai pull/rm` manage downloads. `kelpie ai load/unload/status/ask` control inference on devices. `kelpie ai catalog` lists a device's approved model catalog and `kelpie ai fitness <model>` scores a model against a device's RAM/disk. All available as MCP tools (`kelpie_ai_models`, `kelpie_ai_pull`, `kelpie_ai_remove`, `kelpie_ai_status`, `kelpie_ai_load`, `kelpie_ai_unload`, `kelpie_ai_ask`, `kelpie_ai_record`, `kelpie_ai_catalog`, `kelpie_ai_fitness`).

## Annotated Screenshot Workflow

A visual-first automation loop designed for LLMs:

1. Take an annotated screenshot — get an image with numbered labels on interactive elements.
2. The LLM examines the image and decides what to do.
3. Click or fill by annotation index — "click 5" or "fill 12 with my@email.com".
4. Repeat.

No CSS selectors, no DOM knowledge. The LLM works from what it sees, like a human would.

## Mutation Observation

Watch the DOM for changes in real time. Start an observer on any element (or the whole document), specifying what to track: attributes, child nodes, subtree, text content. Retrieve accumulated mutations later. Stop when done. Useful for detecting dynamic UI updates, loading spinners, and AJAX content across iOS, macOS, and Android.

## Shadow DOM

Query elements inside shadow roots, even nested ones. List all shadow DOM hosts on the page. The `pierce` option recursively searches through nested shadow trees. Essential for modern web components (Lit, Stencil, etc.) on iOS, macOS, and Android.

## Tabs

List open tabs, create new ones, switch between them, close them. Each tab tracks its URL, title, and active state. Each tab owns its own WebView instance so page state, scroll position, and history are preserved across tab switches.

On macOS, Windows and Linux, every tab-scoped browser command accepts an optional `tabId` and `generation` lease so multiple agents can control different tabs without switching the visible tab. When only one tab is open, `tabId` can be omitted; when multiple tabs are open, it is required and the server returns `TAB_REQUIRED` if it is missing. `new-tab` returns the tab identifier and generation. Background tabs are fully controllable: JavaScript evaluation, clicks, fills, screenshots, cookies, storage, and dialogs execute against the resolved lease. iOS and Android always operate on the active tab.

macOS also supports multiple top-level windows. Each window has its own tab list, and tab IDs are scoped per window. Tab-related requests accept an optional `windowId` field, and `get-tabs` returns a `windows` array enumerating every window when more than one is open. iOS and Android only ever expose one window and report `windowId: "main"`.

Tabs can carry an optional display **name** and an optional storage **partition**. A name is a free-form label (up to 200 characters) that replaces the page title in the tab bar and comes back in `get-tabs`, so an orchestrator can find the tab it means without matching on URLs. A partition binds the tab to its own cookie / localStorage / IndexedDB container: tabs created with the same partition string share storage, tabs with different strings are fully isolated, and tabs created without one keep using the shared default container exactly as before. That makes N independent logins to the same origin possible on a single device — twelve employee identities on one Mac, each with its own session. Partitions can also be non-persistent, in which case their storage is in-memory only and disappears with their tabs. `kelpie partitions` lists what exists and `kelpie partition delete <id>` closes the partition's tabs and wipes its storage.

This delivers isolated identities, **not** parallel execution: commands still serialise on each app's main thread, so an orchestrator drives twelve partitions in turn rather than all at once.

Storage partitioning is available on **macOS with the WebKit engine** and on **Windows and Linux with the Chromium (CEF) engine**. macOS on the Chromium engine, iOS and Android reject `partition` with `PARTITION_UNSUPPORTED` and a `reason` field saying why. On macOS, partitioned tabs are excluded from the shared cookie jar, and switching to the Chromium engine is blocked while any partitioned tab is open because partitioned storage cannot be migrated into CEF. On Windows and Linux each partition is a separate `CefRequestContext` — persistent ones stored as a Chromium profile directory `<profile>/cache/partition-<id>`, non-persistent ones in memory — `window.open` inherits the opener's partition, and each tab's partition is recorded in the session snapshot and rebound on restart.

The Windows shell exposes the same feature without the API: the top-left `+` creates a tab, and its context menu offers "New tab" and "New isolated tab" (`Ctrl+Shift+N`), an isolated pill carries a 2-DIP accent stripe and shows its `name` in place of the page title, its tooltip spells out the partition id, and Settings has an **Isolate every new tab** toggle that is off by default.

On iOS, Android, macOS, and Linux, the current tab set is also persisted automatically while the browser is running and restored automatically on the next app launch. Restarting the browser reopens the same tabs and URLs that were active before exit instead of dropping back to a blank start state.

On iOS and Android, the URL bar and tab strip are positioned at the bottom of the screen in a Safari-style bottom bar. The bar collapses to a compact domain pill when the user scrolls down, freeing screen space for the page content, and expands back to the full URL field and navigation controls when the user scrolls up or taps the pill. When more than one tab is open, a horizontally scrollable tab strip appears above the URL field showing tab pills with titles and close buttons. The mobile URL bar now also autocompletes previously visited URLs inline as you type and resolves the best history match on submit, so typing a remembered prefix like `deepwater` can reopen the prior page without retyping the full address.

## Iframes

List all iframes on the page with their URLs, names, positions, and cross-origin status. Switch context into an iframe to interact with its content, then switch back to the main frame.

## Cookies and Storage

Full read/write access to cookies (with domain, path, expiry, httpOnly, secure, sameSite attributes) and both localStorage and sessionStorage. Clear individual items or wipe everything.

Cookies are read from and written to the platform's native cookie store (`WKHTTPCookieStore` on iOS/macOS, `CookieManager` on Android), not through JavaScript. This means **httpOnly cookies are fully settable and readable** — the common case for session auth — which `eval` / `document.cookie` can never do. To start automation from an authenticated session, set the session cookie with `set-cookie` (CLI `cookies set --http-only`, MCP `kelpie_set_cookie`) before navigating; no external proxy is required. See the CLI reference's "Authentication / session state" section.

## Clipboard

Read and write the device clipboard. On iOS, a system permission banner appears briefly.

## Keyboard and Viewport

Show or hide the soft keyboard, check its state, and see how it affects the visible viewport. Resize the viewport to simulate different screen conditions. Check whether a specific element is obscured (e.g., by the keyboard).

On Android, keyboard visibility and height now come from live `WindowInsets` tracking instead of a stubbed value. Kelpie subtracts the navigation-bar inset from the IME inset and reports the resulting keyboard height plus the remaining visible viewport in dp.

On iPad and Android tablets, the browser shell also has a floating-menu phone viewport picker that stages the live browser view inside a centered device-class viewport instead of stretching edge to edge. The staged viewport honors the current tablet orientation: portrait uses a portrait frame, landscape uses a landscape frame, and the preset list only shows the shared phone, tablet, and laptop sizes that fit the current device geometry. When staged mode is active, a persistent black close button with a white border sits outside the browser frame at the upper-left, and a centered black summary pill sits above the viewport with clear spacing and shows the simulated inches band and pixel range.

On macOS, the browser window and the browser viewport are separate concepts. `Full` mode fills the live stage, shared device presets create a centered simulated viewport inside that shell, and raw `resize-viewport` calls enter a `Custom` viewport mode instead of resizing the native window. The shell can grow larger, but never smaller than the configured minimum. The native window retains the current page title for system menus; the tabs show it visually, and the three-dot popup shows the live viewport resolution. The shell persists the user-resized shell window size and on-screen position across launches — the saved position is restored only when it still lands on a connected screen, otherwise the window is re-centered — and shows the same first-launch welcome card used on iOS. The macOS preset picker now uses the same shared categories as tablets, sorted by screen size: `Flip Fold (Cover)`, `Compact / Base`, `Standard / Pro`, `Book Fold (Cover)`, `Large / Plus`, `Flip Fold (Internal)`, `Ultra / Pro Max`, `Book Fold (Internal)`, and `Tri-Fold (Internal)`. If the window becomes too small for the active preset, Kelpie clears that preset and returns to `Full` mode instead of keeping a stale hidden selection. The same menu exposes links to the Kelpie website, the GitHub repository, and `unlikeotherai.com`. macOS keeps back, forward, reload, Home, bookmark, native page sharing and history in the navigation row. The right-hand three-dot popup contains bookmark management, Safari authentication, network inspector, settings, AI, 3D inspection, renderer selection, viewport presets, orientation and scale. All chrome controls use AppKit-backed hit targets. Tabs stay pinned while downward page scrolling hides the address and favourites rows; the first upward scroll reveals them, as do navigation, Home, reload and tab selection. The compact bars use native translucent blur. On macOS 26+ in full-size WebKit mode, page content renders beneath that blur while native insets keep fixed/sticky headers and the visible automation viewport correctly positioned. Other engines, older macOS and staged viewports retain their reserved content area. Chrome samples a narrow visible WebKit page strip during navigation and throttled scrolling, then transitions background, selected tabs, text and toolbar icons together over 200 ms. Sampling stays in memory, ignores bright foreground details when choosing the background, and stops when idle. A bottom status bar shows hovered link destinations, including same-origin frames and open shadow roots, and clears on exit, scrolling or navigation; cross-origin frame links cannot be inspected through the native tracker’s one-shot DOM query. The favourites row contains real saved bookmarks and is hidden while the store is empty. Cmd+D, Add bookmark in the application or three-dot menu, and the address star save the current window’s page, avoiding duplicates and start pages, and reveal the row. Favourites open their saved URLs; removing the last bookmark removes the row and its 29-point WebKit underlap. The divider moves with the bottom of the visible rows and uses adaptive foreground colour at 10% opacity. History opens in an anchored 320-by-420-point popover matching the additional-controls menu, retaining entry navigation and Clear history with AppKit-backed hit targets. Bookmarks, network and settings open native macOS sheets backed by the same stores and inspector data as iOS, with full-row hit targets.

The browser HTTP API and MCP now expose named viewport presets directly via `get-viewport-presets` / `set-viewport-preset` and `kelpie_get_viewport_presets` / `kelpie_set_viewport_preset`, so an LLM can inspect the current preset catalog and activate one of the shared device classes remotely. Linux does not support named viewport presets yet.

## Orientation Control

Lock the device to portrait, landscape, or auto-rotate. Query the current orientation and lock state.

On macOS this applies to the staged viewport only, not the native window. A named viewport preset must be active before orientation can change, and the three-dot popup hides the portrait/landscape toggle unless such a preset is active. If automation asks for orientation while macOS is in `Full` mode or raw `Custom` viewport mode, Kelpie now returns an explicit explanatory error instead of pretending the feature is unsupported.

## Device Info

Get comprehensive metadata: device ID, name, model, platform, OS version, screen dimensions, pixel ratio, network address, port, app version. Query what capabilities each device supports (e.g., on-screen keyboard control is mobile-only; renderer switching is macOS-only).

## Toast Messages

Show a message overlay on the device screen — a blurred pill at the bottom that auto-dismisses after 3 seconds. Useful for feedback during automation ("Logging in..." or "Test passed"). Accessible via the `toast` endpoint. On macOS the toast is rendered as a native shell card over the browser window instead of being injected into the page DOM.

## Group Commands

Send the same command to every discovered device simultaneously — or filter by platform, device name, or ID. Navigate all devices to the same URL, take screenshots from all of them at once, fill the same form on every screen. Results come back per-device.

**Smart group queries** go further: "find the login button on all devices" returns which devices found it and which didn't. The LLM can then decide what to do per-device.

Filtering: `--platform ios`, `--exclude "iPad Air"`, `--include "a1b2c3d4,My iPhone"`.

## MCP Server

The CLI runs as an MCP server (stdio or HTTP/SSE transport) exposing 100+ tools — every browser command plus discovery and group operations. Add it to Claude Desktop, Cursor, or any MCP-compatible client:

```json
{
  "mcpServers": {
    "kelpie": {
      "command": "kelpie",
      "args": ["mcp"]
    }
  }
}
```

All MCP tools use the `kelpie_` prefix and include JSON schemas with descriptions.

## Install Description (`kelpie describe`)

One machine-readable document answering what an external integrator needs to know before it can drive anything: which CLI version is answering, where its binary lives, how to start its MCP server over stdio or HTTP, how large the tool catalog is (with a digest so a poller notices an upgrade that changed the tool surface), and every instance currently visible — from the mDNS browse *and* the loopback probe, since a Kelpie on the same host is routinely missed by the announcement.

```bash
kelpie describe                        # human-readable summary
kelpie describe --json                 # the integration contract
kelpie describe --json --include-tools # embed every tool schema
```

`--json` is a stability contract: readers must tolerate unknown fields and unknown enum values, and nothing is removed or repurposed without raising `schemaVersion`. It exits 0 with a valid document even when nothing is found, and distinguishes "looked and found nothing" from "could not look". Pairing travels as a boolean per instance and never as a token. See [docs/cli.md](cli.md) for the full grammar.

## LLM Help System

Every CLI command supports `--llm-help` for machine-readable documentation. `kelpie --llm-help` outputs the complete reference, including guidance on reporting unexpected automation failures or missing capabilities to the GitHub issue tracker. `kelpie explain <command>` gives natural-language explanations. Designed so an LLM can teach itself the tool without human guidance.

The CLI manages local browser aliases under `~/.kelpie`. On macOS, `kelpie browser register <name>` and `kelpie browser launch <name>` start a fresh Kelpie.app instance on an explicit or auto-assigned port. On Windows, users extract the release ZIP into a current-user-owned directory, register the executable with an absolute profile directory, and launch it through the same alias commands. Windows aliases use a protected readiness file and `kelpie --browser <name> mcp` for local agent stdio. Auto-assigned launch ports skip reserved ports such as `8421` so AppReveal and CLI MCP do not clash with launched browser instances.

Published GitHub releases also build Android release artifacts and publish the CLI packages to npm automatically, so the release page and npm stay aligned with the tagged version.

## Settings Panel

Slides in from the floating menu. The current settings surfaces are primarily status and control panels, not device-identity editors: they show device info, network status, and version/build information, plus platform-specific help and experimental controls.

On iOS, the settings sheet shows device and network details, a copyable connection URL, a `Debug Overlay` toggle for external-display diagnostics, an `Experimental` toggle for the 3D DOM inspector, the shared help actions (`Show Welcome Screen`, `Open Kelpie Website`, `Open GitHub Repository`, and `Open UnlikeOtherAI`), and app version/build details.

On Android, the settings sheet mirrors the same core device and network status, the shared help actions, and an `Experimental` 3D DOM inspector toggle.

On macOS, the settings sheet adds renderer status plus a native AI section: active model picker, Ollama endpoint field, reachability test, and local-model status summary, alongside the same network/app information and the `Experimental` 3D DOM inspector toggle.

On iPad, the same help actions are also exposed directly from the app menu, immediately under the app `Settings` item, so keyboard-and-menu users do not need to open the settings sheet first. The iPad app also adds a `View` menu that lists the currently available staged phone, tablet, and laptop viewport presets plus `Full Width`, and those menu items are sourced from the same native preset catalog used by the floating menu and MCP APIs.

## Dialogs

Detect, accept, or dismiss JavaScript alerts, confirms, and prompts. Configure auto-handling (always accept, always dismiss, or queue for manual decision). Queued dialogs are cleared if a new navigation starts so the browser never stays blocked on a stale native dialog callback. Dialog handling now has full parity across iOS, Android, and macOS — the macOS WebKit renderer enqueues dialogs into a shared store the handler reads, so it is no longer a stub.

## Request Interception

Blocking requests by URL pattern and mocking responses (custom bodies and status codes) is part of the API surface, but is **not currently implemented on any platform** — `set-request-interception`, `get-intercepted-requests`, and `clear-request-interception` return `PLATFORM_NOT_SUPPORTED` on iOS, Android, and macOS alike.

## Geolocation Override

Overriding the device GPS location (latitude, longitude, accuracy) is part of the API surface, but is **not currently implemented on any platform** — `set-geolocation` and `clear-geolocation` return `PLATFORM_NOT_SUPPORTED` on iOS, Android, and macOS alike.

## Windows local control

Windows `0.1.4` uses the shared CEF desktop runtime for tabs, navigation, trusted input,
DOM/evaluation, screenshots, cookies, storage, dialogs, console and network inspection.
The GUI listens only on loopback. Each launch writes a current-user ACL-protected readiness
file at `<profile-dir>/readiness.json`; it holds the bound port and per-launch bearer token. Public device discovery reports only `127.0.0.1`, the actual bound port, and loopback MCP transport.
`kelpie browser register <name> --platform windows --app-path <Kelpie.exe> --profile-dir <absolute>`
creates an alias, `kelpie browser launch <name>` starts it, and `kelpie --browser <name> mcp`
provides a token-free stdio bridge for local development agents and local Nessie executors.
`kelpie browser stop <name>` requests orderly app shutdown and clears its alias state only after
that launch removes readiness. Windows home, native toast, and fullscreen are callable through
HTTP and MCP; remote browser control is not shipped.

On macOS, Windows and Linux, the selected tab carries the sampled page colour continuously into the navigation area below. Inactive tabs and the entire title strip stay static light gray, including on dark pages. Page colours animate while the gray strip remains unchanged. On macOS, a bounded trailing sample catches sticky-header colour transitions after the last scroll event.

### Desktop UOA account and favourites

On macOS, Windows and Linux, the circular account control between History and More opens an account popup. Sign in
with UOA opens the system authentication browser at authentication.unlikeotherai.com,
using a public OAuth client and S256 PKCE. Password and authenticator verification stay
on UOA's hosted screen. The popup displays the authoritative UOA name/email and avatar,
with Sign out and Refresh favourites actions. Session expiry asks the user to sign in
again; the public profile does not issue refresh tokens.

While signed in, favourites load and save directly in UOA's personal settings store
(`browser` / `bookmarks`). Add, remove and clear wait for durable saves; conflicts fetch
the current server list and reapply the intended change. Sync failures appear in the
account popup and are returned by bookmark API mutations. Refresh favourites reloads
changes from another device. Signed-out favourites remain local and are restored on
sign-out; they are never silently uploaded. Tokens, identity, avatar and signed-in
favourites remain in memory and are cleared on sign-out, account change or expiry.

