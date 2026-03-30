# Mollotov — Feature Catalogue

Every user-facing feature is described here. When adding or changing a feature, update this file in the same commit.

---

## How It Works

Mollotov has two parts: **native browser apps** (iOS and Android) and a **Node.js CLI**. The apps run real mobile browsers with embedded HTTP and MCP servers. The CLI discovers them on the local network via mDNS and sends commands. An LLM can control everything through the CLI's MCP server — or talk to device MCP servers directly.

No emulators, no cloud, no persistent scripts. Real browsers on real devices, fully controllable by language models.

## Device Discovery

Every running Mollotov app advertises itself via mDNS (`_mollotov._tcp`) on the local network. The CLI auto-discovers all devices and exposes their metadata: device name, model, platform, screen resolution, port, and app version. Devices can be targeted by name, ID, or IP address.

Works identically with real devices, iOS Simulators, and Android Emulators — a developer with no phones can spin up multiple simulators at different screen sizes and control them all.

## Browser Control

Full navigation control: go to any URL, go back/forward, reload, get the current page URL and title. The browser uses Safari's user agent on iOS and Chrome's on Android so sites behave normally — Google OAuth, banking sites, and similar services work without being blocked as a WebView.

### Safari / Chrome Authentication

One-tap login using the device's saved passwords. On iOS, opens an ASWebAuthenticationSession (Safari's login sheet) that shares Safari's saved passwords and cookies. On Android, uses Chrome Custom Tabs. After login, cookies are synced back into the browser automatically.

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

**List view:** every request shows its HTTP method (GET, POST, PUT, DELETE, OPTIONS, etc.), URL, status code, content type, category, duration, and size. Filter by HTTP method, content type (JSON, HTML, CSS, JS, images, fonts), or search by URL.

**Detail view:** drill into any request to see the full picture — request method, URL, headers, query parameters, and body. Response status, headers, and body (formatted for JSON). Timing: start time, duration, bytes transferred.

**LLM integration:** the LLM can list and filter captured traffic, navigate to a specific request by index or URL pattern, and read its full details. When the user is viewing a specific request in the inspector, the LLM knows exactly which one and can debug it — inspecting headers, payloads, and response data.

API: `network-list`, `network-detail`, `network-select`, `network-current`, `network-clear`.

## Bookmarks

Saved URLs accessible from the floating menu. Fully controllable through the MCP and CLI — an LLM or user can add, remove, list, and clear bookmarks remotely. Tapping a bookmark navigates the browser to that URL. Persisted across app restarts. Primary use case: push project URLs from the CLI so you can tap to navigate without typing.

API: `bookmarks-list`, `bookmarks-add`, `bookmarks-remove`, `bookmarks-clear`.

## History

Chronological log of every URL navigated to. Auto-recorded as you browse, deduplicating consecutive identical URLs. Viewable from the floating menu, clearable by the user or via API. Stores up to 500 entries, persisted across restarts.

API: `history-list` (with limit), `history-clear`.

## Floating Menu

A 44-point circular flame button, vertically centered on the screen edge. Horizontally draggable — swipe it left or right so it's never in the way. Tap to expand a fan of six icon-only menu items: reload, Safari/Chrome auth, bookmarks, history, network inspector, and settings. Opens with a blur overlay behind it.

## LLM-Optimised Queries

Purpose-built methods that return semantic data instead of raw HTML:

- **Accessibility tree** — ARIA roles, labels, states, and nesting. What a screen reader sees.
- **Visible elements** — only what's currently in the viewport, optionally filtered to interactive elements only. Up to 200 elements with positions.
- **Page text** — reader-mode text extraction: title, content, word count, language.
- **Form state** — snapshot of every form on the page: fields, values, validation state, which required fields are empty.
- **Smart find** — find a button, link, input, or any element by its visible text or label. No selectors needed.

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

## Orientation Control

Lock the device to portrait, landscape, or auto-rotate. Query the current orientation and lock state.

## Device Info

Get comprehensive metadata: device ID, name, model, platform, OS version, screen dimensions, pixel ratio, network address, port, app version. Query what capabilities each device supports (e.g., Android supports request interception, iOS does not).

## Toast Messages

Show a message overlay on the device screen — a blurred pill at the bottom that auto-dismisses after 3 seconds. Useful for feedback during automation ("Logging in..." or "Test passed"). Accessible via the `toast` endpoint.

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

## Settings Panel

Slides in from the floating menu. Shows device info (name, model, platform, OS, resolution), connection status (IP, port, mDNS advertising, HTTP server running), and copyable connection URLs. Port and device name are editable.

## Dialogs

Detect, accept, or dismiss JavaScript alerts, confirms, and prompts. Configure auto-handling (always accept, always dismiss, or queue for manual decision).

## Request Interception (Android)

Block requests matching a URL pattern, or mock responses with custom bodies and status codes. List active rules, clear them. Android-only via Chrome DevTools Protocol.

## Geolocation Override (Android)

Set a fake GPS location (latitude, longitude, accuracy). Clear to restore real location. Android-only via CDP.
