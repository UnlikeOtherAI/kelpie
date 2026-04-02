# Mollotov — Feature Catalogue

Every user-facing feature is described here. When adding or changing a feature, update this file in the same commit.

For information about browser engine availability by platform and Apple's regulatory requirements for alternative engines, see [browser-engines.md](browser-engines.md).

---

## How It Works

Mollotov has two parts: **native browser apps** (iOS, Android, macOS, Linux, and an in-progress Windows shell) and a **Node.js CLI**. The apps run real browsers with embedded HTTP and MCP servers. The CLI discovers them on the local network via mDNS and sends commands. An LLM can control everything through the CLI's MCP server — or talk to device MCP servers directly.

No emulators, no cloud, no persistent scripts. Real browsers on real devices, fully controllable by language models.

## Device Discovery

Every running Mollotov app advertises itself via mDNS (`_mollotov._tcp`) on the local network. The CLI auto-discovers all devices and exposes their metadata: device name, model, platform, screen resolution, port, and app version. Devices can be targeted by name, ID, or IP address. Apps prefer port `8420`, but if that port is already occupied they bind the next available local port and advertise the actual port they chose.

Works identically with real devices, iOS Simulators, and Android Emulators — a developer with no phones can spin up multiple simulators at different screen sizes and control them all.

## Browser Control

Full navigation control: go to any URL, go back/forward, reload, get the current page URL and title. The browser uses Safari's user agent on iOS, Chrome's on Android, Chromium on Linux, and on macOS can switch between Safari/WebKit and Chrome/Chromium behavior so sites behave normally — Google OAuth, banking sites, and similar services work without being blocked as a WebView.

On macOS, the desktop URL bar stays synced with both API/MCP-triggered navigation and user-driven page navigation, uses compact Safari-style rounded chrome with coloured browser-brand renderer switches, supports native fullscreen toggling for the active window from the Window menu or with `Cmd+F`, and maps `Cmd+R` to a hard refresh in both WebKit and Chromium so cached desktop state can be cleared without switching renderers. On Linux, the GTK shell now uses matching rounded toolbar chrome, a Chromium brand badge in the URL field, and the same warm orange floating menu treatment as the macOS app instead of stock GTK buttons.

On Linux, the desktop shell runs in either GUI or headless mode. Both modes expose the same HTTP surface, advertise themselves over mDNS, persist profile-backed bookmarks/history/network/console state, support a persisted home page URL, and degrade cleanly when the CEF runtime is unavailable. In GUI mode, the browser window can also be toggled into fullscreen via API/MCP. Published GitHub releases now attach Linux `.tar.gz`, `.deb`, `.rpm`, and `.AppImage` artifacts automatically and refresh Debian/Ubuntu `apt` plus Fedora-compatible `dnf` package repositories on GitHub Pages from the same release event.

On Windows, the first desktop shell now exists under `apps/windows/`: Win32 main window, URL bar, native settings dialog, bookmarks/history/network inspector windows, native toast overlay, device info provider, optional CEF child host, and embedded `/v1/` HTTP server. Until the shared `engine-chromium-desktop` runtime lands, navigation and shell-state endpoints work, but screenshot/eval/DOM-heavy Chromium automation endpoints still return `PLATFORM_NOT_SUPPORTED` instead of faking incomplete behavior.

### Safari / Chrome Authentication

One-tap login using the device's saved passwords. On iOS, opens an ASWebAuthenticationSession (Safari's login sheet) that shares Safari's saved passwords and cookies. On Android, uses Chrome Custom Tabs. After login, cookies are synced back into the browser automatically.

## Renderer Switching (macOS)

Switch between Safari (WebKit), Chrome (Chromium/CEF), and Firefox (Gecko) rendering engines at runtime. Available via the UI segmented control and the `set-renderer` / `get-renderer` HTTP endpoints. Cookies are migrated automatically when switching to preserve login sessions.

Gecko uses a Firefox runtime bundled inside Mollotov.app (`Frameworks/MollotovGeckoHelper.app`) — no external Firefox installation required. Run `make gecko-runtime` once during setup to download and strip the runtime. The bundled binary is driven headless via the Firefox Remote Protocol (CDP-compatible WebSocket). The live view shows the Firefox-rendered page via screenshots at ~5fps.

## External Display — Apple TV (iOS)

When an iPhone or iPad running Mollotov connects to an Apple TV via AirPlay, the app automatically detects the external screen and displays a fullscreen WKWebView on it. This external browser appears as a separate device in mDNS discovery with the name "{device} (TV)" on port 8421, fully controllable from the CLI independently of the main device. No UI chrome — just the web content, controlled entirely via the API. The phone UI also exposes a sync control that mirrors the phone browser onto the TV: page URL, cookies, storage-backed session state, and scroll position all stay aligned so the TV follows the same browsing session instead of acting like a separate login context. A landscape touchpad remote with a visible cursor and inertial swipe scrolling is also available. When the AirPlay connection drops, the external server and window are torn down automatically.

## Screenshots

Capture viewport or full-page screenshots on demand in PNG or JPEG. Full-page mode stitches together the entire scrollable page. Quality is adjustable for JPEG.

### Annotated Screenshots

Take a screenshot with numbered labels overlaid on every interactive element (buttons, links, inputs). The LLM sees both the image and a structured list of what each number corresponds to. Then it can say "click element 5" or "fill element 12 with hello@example.com" — visual-first automation without needing CSS selectors.

## DOM Access and Queries

Full read access to the page DOM. Query elements by CSS selector, get their text, attributes, bounding boxes, and visibility. Retrieve the full DOM tree from any root element with configurable depth. All queries return structured data, not raw HTML.

## Element Interaction

Click elements by selector or tap at specific coordinates. Fill form inputs, type text character-by-character (simulating human typing with per-character delays), select dropdown options, check/uncheck checkboxes. Every interaction shows a blue touch indicator animation on the device so you can see what happened.

## Scrolling

Scroll by pixel deltas, scroll a specific element into view (with configurable alignment: top/center/bottom), or jump to the top or bottom of the page. The `scroll2` method is resolution-aware — it adapts its behavior based on the device's viewport size.

## Wait and Synchronisation

Wait for an element to appear, become visible, or disappear — with configurable timeout. Wait for page navigation to complete. Essential for reliable automation when pages load dynamically.

## JavaScript Evaluation

Execute arbitrary JavaScript in the page context and get the result back. Use it for anything the built-in methods don't cover.

## Console and Error Capture

Read console output (log, warn, error, info, debug) from the page. Get JavaScript errors with full stack traces. The console bridge captures everything including unhandled promise rejections. Messages buffer up to 5,000 entries — clearable on demand.

## Network Monitoring

Two levels of network visibility:

**Performance timeline** — uses the browser's Performance API to get resource loading data: URLs, methods, status codes, MIME types, sizes, and detailed timing breakdowns (DNS, TCP, TLS, waiting, download).

**Network Inspector** (new) — a Charles Proxy-style traffic viewer built into the app. See below.

## Network Inspector

A built-in network traffic viewer accessible from the floating menu. Captures all HTTP/HTTPS requests and responses flowing through the loaded website.

**List view:** every request shows its HTTP method (GET, POST, PUT, DELETE, OPTIONS, etc.), URL, status code, content type, category, duration, and size. The app records the top-level page document alongside fetch/XHR traffic, so a normal page load always appears in the inspector. Three filter dropdowns: **Method** (All Methods, GET, POST, PUT, DELETE), **Type** (All Types, HTML, JSON, JS, CSS, Image, Font, XML, Other), and **Source** (All Sources, Browser, JS (fetch/XHR)). The Source filter distinguishes browser-initiated requests (page loads, subresources) from JavaScript-initiated requests (fetch, XHR). URL search is also available. All three platforms (iOS, Android, macOS) have identical filter sets.

**Detail view:** drill into any request to see the full picture — request method, URL, headers, query parameters, and body. Response status, headers, and body (formatted for JSON). Timing: start time, duration, bytes transferred. On Android and Chromium-backed macOS views, top-level document rows may have partial metadata where the native web view does not expose a full response.

**LLM integration:** the LLM can list and filter captured traffic, navigate to a specific request by index or URL pattern, and read its full details. When the user is viewing a specific request in the inspector, the LLM knows exactly which one and can debug it — inspecting headers, payloads, and response data.

API: `network-list`, `network-detail`, `network-select`, `network-current`, `network-clear`.

## Bookmarks

Saved URLs accessible from the floating menu. Fully controllable through the MCP and CLI — an LLM or user can add, remove, list, and clear bookmarks remotely. Tapping a bookmark navigates the browser to that URL. Persisted across app restarts. Primary use case: push project URLs from the CLI so you can tap to navigate without typing.

API: `bookmarks-list`, `bookmarks-add`, `bookmarks-remove`, `bookmarks-clear`.

## History

Chronological log of every URL navigated to. Auto-recorded as you browse, deduplicating consecutive identical URLs. Viewable from the floating menu, clearable by the user or via API. Stores up to 500 entries, persisted across restarts. If a navigation is recorded before the page title settles, the latest history entry self-updates once the final title arrives, so rows do not stay blank or half-populated.

API: `history-list` (with limit), `history-clear`.

## Floating Menu

A 44-point circular flame button, vertically centered on the screen edge. Horizontally draggable — swipe it left or right so it's never in the way. Tap to expand a fan of icon-only menu items in a wide half-circle: reload, Safari/Chrome auth, bookmarks, history, network inspector, and settings. On tablets, the fan also includes a phone icon that opens a pill picker anchored off that icon instead of toggling immediately. The picker uses the same sorted fitting preset list shown by the iPad `View` menu and MCP APIs, including phone, tablet, and laptop classes when they fit the current device geometry. Pills use full visible labels such as `6.1" Compact`, `11" iPad Pro`, and `13" Laptop`, and they flow into extra columns outside the fan lane so they do not cover the action buttons. Tapping the active pill again returns the browser to full width. Opens with a blur overlay behind it.

## LLM-Optimised Queries

Purpose-built methods that return semantic data instead of raw HTML:

- **Accessibility tree** — ARIA roles, labels, states, and nesting. What a screen reader sees.
- **Visible elements** — only what's currently in the viewport, optionally filtered to interactive elements only. Up to 200 elements with positions.
- **Page text** — reader-mode text extraction: title, content, word count, language.
- **Form state** — snapshot of every form on the page: fields, values, validation state, which required fields are empty.
- **Smart find** — find a button, link, input, or any element by its visible text or label. No selectors needed.

## Local AI

On-device LLM inference across all platforms. Five HTTP endpoints (`ai-status`, `ai-load`, `ai-unload`, `ai-infer`, `ai-record`) and corresponding MCP tools let language models query local AI without sending data to the cloud.

**macOS — native GGUF + Ollama:** The CLI manages GGUF model downloads from HuggingFace (`mollotov ai pull`). The macOS app loads them via llama.cpp on Apple Silicon. An inference harness runs a lightweight agent loop (max 3 tool calls) so 2B models can request page data on demand instead of receiving everything upfront. Audio recording captures 16kHz mono PCM (max 30s) for voice input. Intel Macs get Ollama-only mode.

**iOS — Apple Intelligence + Ollama:** Platform AI (Foundation Models framework) is the default backend on supported hardware. Text-only until the iOS 26 SDK is linked. Users can switch to a remote Ollama model for vision-capable inference.

**Android — Gemini Nano + Ollama:** Platform AI (Google AI Edge SDK) is the default backend on Android 14+ hardware. Text-only until the SDK is integrated. Users can switch to a remote Ollama model for vision-capable inference.

**CLI model management:** `mollotov ai list` shows approved models and their download status, plus any locally running Ollama models. `mollotov ai pull/rm` manage downloads. `mollotov ai load/unload/status/ask` control inference on devices. All available as MCP tools (`mollotov_ai_models`, `mollotov_ai_pull`, `mollotov_ai_remove`, `mollotov_ai_status`, `mollotov_ai_load`, `mollotov_ai_unload`, `mollotov_ai_ask`, `mollotov_ai_record`).

## Annotated Screenshot Workflow

A visual-first automation loop designed for LLMs:

1. Take an annotated screenshot — get an image with numbered labels on interactive elements.
2. The LLM examines the image and decides what to do.
3. Click or fill by annotation index — "click 5" or "fill 12 with my@email.com".
4. Repeat.

No CSS selectors, no DOM knowledge. The LLM works from what it sees, like a human would.

## Mutation Observation

Watch the DOM for changes in real time. Start an observer on any element (or the whole document), specifying what to track: attributes, child nodes, subtree, text content. Retrieve accumulated mutations later. Stop when done. Useful for detecting dynamic UI updates, loading spinners, and AJAX content.

## Shadow DOM

Query elements inside shadow roots, even nested ones. List all shadow DOM hosts on the page. The `pierce` option recursively searches through nested shadow trees. Essential for modern web components (Lit, Stencil, etc.).

## Tabs

List open tabs, create new ones, switch between them, close them. Each tab tracks its URL, title, and active state.

## Iframes

List all iframes on the page with their URLs, names, positions, and cross-origin status. Switch context into an iframe to interact with its content, then switch back to the main frame.

## Cookies and Storage

Full read/write access to cookies (with domain, path, expiry, httpOnly, secure, sameSite attributes) and both localStorage and sessionStorage. Clear individual items or wipe everything.

## Clipboard

Read and write the device clipboard. On iOS, a system permission banner appears briefly.

## Keyboard and Viewport

Show or hide the soft keyboard, check its state, and see how it affects the visible viewport. Resize the viewport to simulate different screen conditions. Check whether a specific element is obscured (e.g., by the keyboard).

On iPad and Android tablets, the browser shell also has a floating-menu phone viewport picker that stages the live browser view inside a centered device-class viewport instead of stretching edge to edge. The staged viewport honors the current tablet orientation: portrait uses a portrait frame, landscape uses a landscape frame, and the preset list only shows the shared phone, tablet, and laptop sizes that fit the current device geometry. When staged mode is active, a persistent black close button with a white border sits outside the browser frame at the upper-left, and a centered black summary pill sits above the viewport with clear spacing and shows the simulated inches band and pixel range.

On macOS, the browser window and the browser viewport are separate concepts. `Full` mode fills the live stage, shared device presets create a centered simulated viewport inside that shell, and raw `resize-viewport` calls enter a `Custom` viewport mode instead of resizing the native window. The shell can grow larger, but never smaller than the configured minimum. The native titlebar uses the current page title, shows the live viewport resolution in a pill on the right, persists the user-resized shell window size across launches, and shows the same first-launch welcome card used on iOS. The macOS preset picker now uses the same shared categories as tablets, sorted by screen size: `Flip Fold (Cover)`, `Compact / Base`, `Standard / Pro`, `Book Fold (Cover)`, `Large / Plus`, `Flip Fold (Internal)`, `Ultra / Pro Max`, `Book Fold (Internal)`, and `Tri-Fold (Internal)`. If the window becomes too small for the active preset, Mollotov clears that preset and returns to `Full` mode instead of keeping a stale hidden selection. The same menu exposes links to the Mollotov website, the GitHub repository, and `unlikeotherai.com`. The floating menu shows custom short hover pills beside each action instead of native macOS tooltip strings, and its settings, bookmarks, history, and network entries now open native macOS sheets backed by the same stores and inspector data as iOS. The macOS bookmarks, history, and network sheets now use full-row hit targets rather than narrow text-only rows.

The browser HTTP API and MCP now expose named viewport presets directly via `get-viewport-presets` / `set-viewport-preset` and `mollotov_get_viewport_presets` / `mollotov_set_viewport_preset`, so an LLM can inspect the current preset catalog and activate one of the shared device classes remotely. Linux does not support named viewport presets yet.

## Orientation Control

Lock the device to portrait, landscape, or auto-rotate. Query the current orientation and lock state.

On macOS this applies to the staged viewport only, not the native window. A named viewport preset must be active before orientation can change, and the toolbar hides the portrait/landscape toggle unless such a preset is active. If automation asks for orientation while macOS is in `Full` mode or raw `Custom` viewport mode, Mollotov now returns an explicit explanatory error instead of pretending the feature is unsupported.

## Device Info

Get comprehensive metadata: device ID, name, model, platform, OS version, screen dimensions, pixel ratio, network address, port, app version. Query what capabilities each device supports (e.g., Android supports request interception, iOS does not).

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
    "mollotov": {
      "command": "mollotov",
      "args": ["mcp"]
    }
  }
}
```

All MCP tools use the `mollotov_` prefix and include JSON schemas with descriptions.

## LLM Help System

Every CLI command supports `--llm-help` for machine-readable documentation. `mollotov --llm-help` outputs the complete reference. `mollotov explain <command>` gives natural-language explanations. Designed so an LLM can teach itself the tool without human guidance.

The CLI also manages local macOS browser aliases under `~/.mollotov`. `mollotov browser register <name>` creates a reusable local alias, `mollotov browser launch <name>` starts a fresh Mollotov.app instance for that alias on an explicit or auto-assigned port, and the rest of the CLI can target that launched instance via `--device <name>` without relying on network discovery alone. Auto-assigned launch ports skip reserved ports such as `8421` so AppReveal and CLI MCP do not clash with launched browser instances.

Published GitHub releases also build Android release artifacts and publish the CLI packages to npm automatically, so the release page and npm stay aligned with the tagged version.

## Settings Panel

Slides in from the floating menu. Shows device info (name, model, platform, OS, resolution), connection status (IP, port, mDNS advertising, HTTP server running), and copyable connection URLs. Port and device name are editable.

On iOS and Android, the settings sheet also includes a `Help` section with the same support actions exposed on macOS: `Show Welcome Screen`, `Open Mollotov Website`, `Open GitHub Repository`, and `Open UnlikeOtherAI`. `Show Welcome Screen` is an explicit help action and still opens the welcome card even if the user previously chose not to show it automatically on launch.

On iPad, those same actions are also exposed directly from the app menu, immediately under the app `Settings` item, so keyboard-and-menu users do not need to open the settings sheet first. The iPad app also adds a `View` menu that lists the currently available staged phone, tablet, and laptop viewport presets plus `Full Width`, and those menu items are sourced from the same native preset catalog used by the floating menu and MCP APIs.

## Dialogs

Detect, accept, or dismiss JavaScript alerts, confirms, and prompts. Configure auto-handling (always accept, always dismiss, or queue for manual decision).

## Request Interception (Android)

Block requests matching a URL pattern, or mock responses with custom bodies and status codes. List active rules, clear them. Android-only via Chrome DevTools Protocol.

## Geolocation Override (Android)

Set a fake GPS location (latitude, longitude, accuracy). Clear to restore real location. Android-only via CDP.
