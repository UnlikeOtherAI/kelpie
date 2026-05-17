# Kelpie — API Reference

All methods are available via three interfaces:
1. **HTTP REST** — `POST http://{device}:{port}/v1/{method}`
2. **Browser MCP** — each browser exposes these as MCP tools
3. **CLI MCP** — the CLI wraps these with device targeting and group semantics

## Index

| Document | When to Read |
|---|---|
| [core.md](core.md) | Navigation, screenshots, DOM access, interaction, scrolling, viewport/device info, wait/sync |
| [llm.md](llm.md) | LLM-optimized methods — accessibility tree, annotated screenshots, visible elements, page text, form state, smart queries |
| [devtools.md](devtools.md) | Console/JS errors, network log, network inspector, resource timeline, WebSocket monitoring, mutation observation, shadow DOM, request interception |
| [browser.md](browser.md) | Dialogs/alerts, tabs, iframes, cookies/storage, clipboard, geolocation, JS evaluation, bookmarks, history, fullscreen, renderer management |
| [ai.md](ai.md) | Local inference backends, model switching, inference, and audio recording endpoints |

---

## Protocol

- Base URL: `http://{device-ip}:{port}/v1/`
- Content-Type: `application/json`
- Auth: bearer token via `Authorization: Bearer <token>`. Tokens are issued by `POST /v1/pair` + on-device approval (see [Pairing & Auth](#pairing--auth) below). Deny-by-default — only `/v1/pair`, `/v1/pair/status`, `/v1/get-device-info`, and `/health` are reachable without a token.
- Default Port: `8420`
- Port fallback: if `8420` is already occupied, the app binds the next available local port and advertises that port via mDNS and `get-device-info`
- Concurrency: Requests are queued and processed sequentially per device. Rapid-fire commands are safe but will execute in order. No rate limiting enforced — the embedded HTTP server handles one command at a time.

---

## Pairing & Auth

The HTTP server denies every `/v1/*` and `/mcp` call by default. The CLI must obtain a bearer token via on-device approval before any automation works.

### Endpoints

| Method | Auth | Body | Response |
|---|---|---|---|
| `POST /v1/pair` | none + CSRF gate | `{clientId, clientName}` | `202 {status: "pending", requestId, expiresAt, sourceAddress}` |
| `GET /v1/pair/status?requestId=…` | none | — | `200 {status: "pending"\|"approved"\|"denied"\|"expired"\|"not_found", scope?, token?}` |
| `DELETE /v1/pair` | bearer | — | `200 {success: true}` — revokes the caller's own pairing |
| `GET /v1/get-device-info` | none | — | `200 {name, platform, version, requiresPairing: true}` |

The CSRF gate on `POST /v1/pair` requires `Content-Type: application/json`, an absent `Origin` header, single `Authorization` / `Content-Length` headers, and no `Transfer-Encoding`. Browsers cannot satisfy these constraints; the CLI's plain `fetch` does.

### Token lifecycle

1. CLI generates a stable `clientId` (per-install UUID) and sends `POST /v1/pair` with a self-reported `clientName`.
2. Device displays a modal showing `clientName` (labeled self-reported) and the socket peer address (authoritative).
3. User picks one of `Yes once` (in-memory session), `Always allow` (persistent), or `No` (suppresses re-prompts from that source for 10 minutes).
4. CLI polls `GET /v1/pair/status?requestId=…`. On approval, the plaintext bearer is returned **exactly once**, and the device persists only the SHA-256 hash. Token comparison on subsequent requests is constant-time over the 32-byte digest.

### Source-address binding

The server records the socket peer when `POST /v1/pair` is received. If a later status poll arrives from a different peer, the server returns `not_found` — the token is never disclosed to a third party even if they observe the `requestId`.

### Error codes specific to pairing

| Code | HTTP Status | When |
|---|---|---|
| `UNAUTHORIZED` | 401 | Missing/invalid/expired bearer token |
| `DENIED` | 403 | Pair requests from this source are currently suppressed |
| `MISSING_PARAM` | 400 | `POST /v1/pair` missing `clientId` or status poll missing `requestId` |
| `INVALID_JSON` | 400 | `POST /v1/pair` body was not valid JSON |
| `CSRF_REJECTED` | 400 | `POST /v1/pair` failed Content-Type / Origin / duplicate-header checks |

---

## Per-Tab Targeting (macOS only)

On macOS, every command that touches web content accepts an optional `tabId` parameter. This lets multiple LLMs control different tabs independently without switching the visible tab.

**How it works:**
1. Call `get-tabs` to list all open tabs with their IDs, URLs, and titles
2. Include `"tabId": "<uuid>"` in every subsequent command to target that specific tab
3. If only one tab is open and `tabId` is omitted, the command targets that tab automatically
4. If multiple tabs are open and `tabId` is omitted, the server returns a `TAB_REQUIRED` error listing available tabs

**Example:**
```json
POST /v1/get-tabs
Response: {
  "success": true,
  "tabs": [
    {"id": "A1B2...", "url": "https://google.com", "title": "Google", "active": true, "isLoading": false},
    {"id": "C3D4...", "url": "https://github.com", "title": "GitHub", "active": false, "isLoading": false}
  ]
}

POST /v1/click
{"tabId": "C3D4...", "selector": "#login-button"}
```

**Background tabs:** Commands execute on the target tab's WebView directly — no tab switching occurs. The visible tab stays unchanged. This enables concurrent control by multiple agents.

**Platform availability:** Per-tab targeting is currently macOS only. iOS and Android operate on the active tab implicitly and do not accept `tabId`.

---

## Platform Support Matrix

Not all methods have identical implementations on Android, iOS, and macOS. Android has CDP (Chrome DevTools Protocol) which gives deep access. iOS relies on WKWebView native APIs + ephemeral bridge scripts for features WebKit doesn't expose. macOS uses the same handler surface over two renderers: WKWebView for Safari/WebKit behavior and CEF for Chrome/Chromium behavior.

| Method | Android | iOS | macOS | Notes |
|---|---|---|---|---|
| Navigation, click, fill, type, scroll | Native | Native | Native | macOS routes commands through the active WebKit or CEF renderer |
| Screenshots (viewport) | Native | Native | Native | iOS uses `WKWebView.takeSnapshot`; macOS uses renderer-specific snapshot APIs |
| Screenshots (full page) | CDP | Bridge | App-managed | iOS requires scroll-and-stitch via bridge script; macOS captures through the active renderer pipeline |
| DOM access | CDP | Native | Native | iOS uses `evaluateJavaScript` via native bridge; macOS uses the active renderer's JS bridge |
| Console messages | CDP `Runtime.consoleAPICalled` | Bridge | Renderer-dependent | macOS uses a WebKit bridge on the WKWebView path and native callbacks on the CEF path |
| Network log | CDP `Network.*` | Partial | Partial | iOS: top-level nav via `WKNavigationDelegate`; macOS support depends on the active renderer, but the API surface stays the same |
| Resource timeline | CDP `Performance.*` | Partial | Partial | iOS is limited to `WKNavigationDelegate` events + `PerformanceObserver`; macOS mirrors the active renderer's capabilities |
| WebSocket monitoring (`get-websockets`, `get-websocket-messages`) | Bridge | Bridge | Renderer-dependent | Implemented by wrapping `window.WebSocket` at document start; macOS requires the WebKit renderer |
| Request interception | CDP `Fetch.*` | Not supported | Not supported | iOS `WKURLSchemeHandler` only works for custom schemes, not HTTP/HTTPS |
| Mutation observation | CDP `DOM.*` | Bridge | Renderer-dependent | iOS requires `MutationObserver` bridge script |
| Accessibility tree | CDP `Accessibility.*` | Bridge | Renderer-dependent | iOS requires DOM traversal bridge script querying ARIA attributes |
| Page text extraction | CDP + Readability | Bridge | Bridge | Both Apple-platform WebKit implementations rely on a Readability-style extraction path |
| Shadow DOM traversal | CDP `DOM.*` | Bridge | Renderer-dependent | Limited on all platforms for `mode: "closed"` shadow roots |
| Tabs | App-managed | App-managed | App-managed | All platforms manage multiple browser instances in app code |
| Iframes (same-origin) | CDP | Native | Native | |
| Iframes (cross-origin) | CDP (limited) | Not supported | Renderer-dependent | WebKit cannot evaluate JS in cross-origin iframes; Chromium-backed paths can expose more context |
| Cookies | CDP `Network.getCookies` | Native | Native | iOS uses `WKHTTPCookieStore`; macOS migrates cookies automatically on renderer switch |
| Storage (local/session) | CDP/evaluate | Bridge | Native | macOS storage access goes through the active renderer |
| Clipboard read | Native | Restricted | Native | iOS shows a system paste permission banner; Android 10+ restricts background access |
| Clipboard write | Native | Native | Native | |
| Geolocation override | CDP `Emulation.*` | Not supported | Not supported | No public WKWebView API; macOS does not expose a supported override path |
| Dialog handling | Native | Native | Native | All platforms have native dialog delegation APIs |
| Keyboard simulation | Native | Native | Not supported | macOS has no soft keyboard equivalent to show or hide |
| Named viewport presets (`get-viewport-presets`, `set-viewport-preset`) | Native (tablet only) | Native (iPad only) | Native | Linux does not support named viewport presets yet; phones return no preset support |
| Renderer switching (`set-renderer`, `get-renderer`) | Not supported | Not supported | Native | macOS switches between WebKit and Chromium/CEF at runtime and migrates cookies automatically |
| AI endpoints (`ai-status`, `ai-load`, `ai-unload`, `ai-infer`, `ai-record`) | App-managed | App-managed | App-managed | iOS/Android default to platform AI on supported hardware and can switch to remote Ollama; macOS uses native GGUF or Ollama |

**Legend:**
- **Native** — uses platform SDK APIs, no scripts needed
- **CDP** — uses Chrome DevTools Protocol (Android only)
- **Bridge** — uses ephemeral bridge script via `evaluateJavaScript` / `WKUserScript` (iOS)
- **Partial** — works but with reduced data compared to Android
- **Not supported** — no feasible implementation path; endpoint returns `PLATFORM_NOT_SUPPORTED` error
- **Restricted** — works but triggers OS-level permission UI the user must accept on-device
- **App-managed** — implemented in the app layer rather than by a single browser-engine API
- **Renderer-dependent** — behavior depends on whether macOS is using WKWebView or CEF, but the endpoint contract remains the same

---

## Error Responses

All errors follow the same format:

```json
{
  "success": false,
  "error": {
    "code": "ELEMENT_NOT_FOUND",
    "message": "No element matching selector '#nonexistent'",
    "selector": "#nonexistent"
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|---|---|---|
| `ELEMENT_NOT_FOUND` | 404 | Selector matched no elements |
| `ELEMENT_NOT_VISIBLE` | 400 | Element exists but is not visible/interactable |
| `TIMEOUT` | 408 | Operation timed out |
| `NAVIGATION_ERROR` | 502 | Page failed to load |
| `INVALID_SELECTOR` | 400 | CSS selector syntax error |
| `INVALID_PARAMS` | 400 | Missing or invalid request parameters |
| `WEBVIEW_ERROR` | 500 | Internal WebView/CDP error |
| `IFRAME_ACCESS_DENIED` | 403 | Cannot access closed shadow root or cross-origin iframe |
| `WATCH_NOT_FOUND` | 404 | Mutation watch ID does not exist |
| `ANNOTATION_EXPIRED` | 400 | Annotation index references a stale screenshotAnnotated result (invalidated by navigation or DOM change) |
| `RECORDING_IN_PROGRESS` | 409 | A script is currently playing; only `abort-script` and `get-script-status` are allowed |
| `SCRIPT_PARTIAL_FAILURE` | 200 | Script completed but one or more actions failed (when `continueOnError` is true) |
| `PLATFORM_NOT_SUPPORTED` | 501 | Method not available on this platform (e.g., request interception on iOS) |
| `PERMISSION_REQUIRED` | 403 | Operation requires user gesture or OS permission (e.g., clipboard read on iOS) |
| `SHADOW_ROOT_CLOSED` | 403 | Cannot traverse a closed shadow root |

---

## CLI Group Command Wrappers

When the CLI sends group commands, it wraps individual responses with device metadata:

```json
{
  "command": "findButton",
  "deviceCount": 3,
  "found": [
    {
      "device": {"name": "iPhone", "platform": "ios", "resolution": "390x844"},
      "element": {"tag": "button", "text": "Submit", "visible": true}
    },
    {
      "device": {"name": "Pixel", "platform": "android", "resolution": "412x915"},
      "element": {"tag": "button", "text": "Submit", "visible": true}
    }
  ],
  "notFound": [
    {
      "device": {"name": "iPad", "platform": "ios", "resolution": "1024x1366"},
      "reason": "Element not found — page may have different layout at this resolution"
    }
  ]
}
```

For non-query group commands (e.g., `group navigate`), partial failures return per-device status:

```json
{
  "command": "navigate",
  "deviceCount": 3,
  "results": [
    {"device": {"name": "iPhone"}, "success": true, "url": "https://example.com"},
    {"device": {"name": "iPad"}, "success": true, "url": "https://example.com"},
    {"device": {"name": "Pixel"}, "success": false, "error": {"code": "NAVIGATION_ERROR", "message": "DNS resolution failed"}}
  ],
  "succeeded": 2,
  "failed": 1
}
```

The CLI exit code is `0` if all succeeded, `1` if any failed.

---

## MCP Tool Names

When exposed via MCP, methods use the `kelpie_` prefix:

Internal HTTP-only debug surfaces are not exposed as MCP tools:

| HTTP Endpoint | Purpose |
|---|---|
| `/debug/coordinate-calibration` | Bundled local page for measuring manual taps and previewing calibrated raw taps |
| `/v1/get-tap-calibration` | Read saved raw-tap X/Y offsets |
| `/v1/set-tap-calibration` | Save raw-tap X/Y offsets |

| HTTP Endpoint | MCP Tool Name |
|---|---|
| `/v1/navigate` | `kelpie_navigate` |
| `/v1/back` | `kelpie_back` |
| `/v1/forward` | `kelpie_forward` |
| `/v1/reload` | `kelpie_reload` |
| `/v1/get-current-url` | `kelpie_get_current_url` |
| `/v1/set-home` | `kelpie_set_home` |
| `/v1/get-home` | `kelpie_get_home` |
| `/v1/set-renderer` | `kelpie_set_renderer` |
| `/v1/get-renderer` | `kelpie_get_renderer` |
| `/v1/screenshot` | `kelpie_screenshot` |
| `/v1/get-dom` | `kelpie_get_dom` |
| `/v1/query-selector` | `kelpie_query_selector` |
| `/v1/query-selector-all` | `kelpie_query_selector_all` |
| `/v1/get-element-text` | `kelpie_get_element_text` |
| `/v1/get-attributes` | `kelpie_get_attributes` |
| `/v1/click` | `kelpie_click` |
| `/v1/tap` | `kelpie_tap` |
| `/v1/fill` | `kelpie_fill` |
| `/v1/type` | `kelpie_type` |
| `/v1/select-option` | `kelpie_select_option` |
| `/v1/check` | `kelpie_check` |
| `/v1/uncheck` | `kelpie_uncheck` |
| `/v1/swipe` | `kelpie_swipe` |
| `/v1/show-commentary` | `kelpie_show_commentary` |
| `/v1/hide-commentary` | `kelpie_hide_commentary` |
| `/v1/highlight` | `kelpie_highlight` |
| `/v1/hide-highlight` | `kelpie_hide_highlight` |
| `/v1/play-script` | `kelpie_play_script` |
| `/v1/abort-script` | `kelpie_abort_script` |
| `/v1/get-script-status` | `kelpie_get_script_status` |
| `/v1/scroll` | `kelpie_scroll` |
| `/v1/scroll2` | `kelpie_scroll2` |
| `/v1/scroll-to-top` | `kelpie_scroll_to_top` |
| `/v1/scroll-to-bottom` | `kelpie_scroll_to_bottom` |
| `/v1/scroll-to-y` | `kelpie_scroll_to_y` |
| `/v1/get-viewport` | `kelpie_get_viewport` |
| `/v1/get-viewport-presets` | `kelpie_get_viewport_presets` |
| `/v1/get-device-info` | `kelpie_get_device_info` |
| `/v1/get-capabilities` | `kelpie_get_capabilities` |
| `/v1/wait-for-element` | `kelpie_wait_for_element` |
| `/v1/wait-for-navigation` | `kelpie_wait_for_navigation` |
| `/v1/find-element` | `kelpie_find_element` |
| `/v1/find-button` | `kelpie_find_button` |
| `/v1/find-link` | `kelpie_find_link` |
| `/v1/find-input` | `kelpie_find_input` |
| `/v1/evaluate` | `kelpie_evaluate` |
| `/v1/get-console-messages` | `kelpie_get_console_messages` |
| `/v1/get-js-errors` | `kelpie_get_js_errors` |
| `/v1/get-network-log` | `kelpie_get_network_log` |
| `/v1/network-list` | `kelpie_network_list` |
| `/v1/network-detail` | `kelpie_network_detail` |
| `/v1/network-current` | `kelpie_network_current` |
| `/v1/network-clear` | `kelpie_network_clear` |
| `/v1/network-select` | `kelpie_network_select` |
| `/v1/get-resource-timeline` | `kelpie_get_resource_timeline` |
| `/v1/get-websockets` | `kelpie_get_websockets` |
| `/v1/get-websocket-messages` | `kelpie_get_websocket_messages` |
| `/v1/clear-console` | `kelpie_clear_console` |
| `/v1/get-accessibility-tree` | `kelpie_get_accessibility_tree` |
| `/v1/screenshot-annotated` | `kelpie_screenshot_annotated` |
| `/v1/click-annotation` | `kelpie_click_annotation` |
| `/v1/fill-annotation` | `kelpie_fill_annotation` |
| `/v1/get-visible-elements` | `kelpie_get_visible_elements` |
| `/v1/get-page-text` | `kelpie_get_page_text` |
| `/v1/get-form-state` | `kelpie_get_form_state` |
| `/v1/get-dialog` | `kelpie_get_dialog` |
| `/v1/handle-dialog` | `kelpie_handle_dialog` |
| `/v1/set-dialog-auto-handler` | `kelpie_set_dialog_auto_handler` |
| `/v1/get-tabs` | `kelpie_get_tabs` |
| `/v1/new-tab` | `kelpie_new_tab` |
| `/v1/switch-tab` | `kelpie_switch_tab` |
| `/v1/close-tab` | `kelpie_close_tab` |
| `/v1/bookmarks-list` | `kelpie_bookmarks_list` |
| `/v1/bookmarks-add` | `kelpie_bookmarks_add` |
| `/v1/bookmarks-remove` | `kelpie_bookmarks_remove` |
| `/v1/bookmarks-clear` | `kelpie_bookmarks_clear` |
| `/v1/history-list` | `kelpie_history_list` |
| `/v1/history-clear` | `kelpie_history_clear` |
| `/v1/get-iframes` | `kelpie_get_iframes` |
| `/v1/switch-to-iframe` | `kelpie_switch_to_iframe` |
| `/v1/switch-to-main` | `kelpie_switch_to_main` |
| `/v1/get-iframe-context` | `kelpie_get_iframe_context` |
| `/v1/get-cookies` | `kelpie_get_cookies` |
| `/v1/set-cookie` | `kelpie_set_cookie` |
| `/v1/delete-cookies` | `kelpie_delete_cookies` |
| `/v1/get-storage` | `kelpie_get_storage` |
| `/v1/set-storage` | `kelpie_set_storage` |
| `/v1/clear-storage` | `kelpie_clear_storage` |
| `/v1/watch-mutations` | `kelpie_watch_mutations` |
| `/v1/get-mutations` | `kelpie_get_mutations` |
| `/v1/stop-watching` | `kelpie_stop_watching` |
| `/v1/query-shadow-dom` | `kelpie_query_shadow_dom` |
| `/v1/get-shadow-roots` | `kelpie_get_shadow_roots` |
| `/v1/get-clipboard` | `kelpie_get_clipboard` |
| `/v1/set-clipboard` | `kelpie_set_clipboard` |
| `/v1/set-geolocation` | `kelpie_set_geolocation` |
| `/v1/clear-geolocation` | `kelpie_clear_geolocation` |
| `/v1/set-request-interception` | `kelpie_set_request_interception` |
| `/v1/get-intercepted-requests` | `kelpie_get_intercepted_requests` |
| `/v1/clear-request-interception` | `kelpie_clear_request_interception` |
| `/v1/show-keyboard` | `kelpie_show_keyboard` |
| `/v1/hide-keyboard` | `kelpie_hide_keyboard` |
| `/v1/get-keyboard-state` | `kelpie_get_keyboard_state` |
| `/v1/set-fullscreen` | `kelpie_set_fullscreen` |
| `/v1/get-fullscreen` | `kelpie_get_fullscreen` |
| `/v1/resize-viewport` | `kelpie_resize_viewport` |
| `/v1/reset-viewport` | `kelpie_reset_viewport` |
| `/v1/set-viewport-preset` | `kelpie_set_viewport_preset` |
| `/v1/set-orientation` | `kelpie_set_orientation` |
| `/v1/get-orientation` | `kelpie_get_orientation` |
| `/v1/is-element-obscured` | `kelpie_is_element_obscured` |
| `/v1/ai-status` | `kelpie_ai_status` |
| `/v1/ai-load` | `kelpie_ai_load` |
| `/v1/ai-unload` | `kelpie_ai_unload` |
| `/v1/ai-infer` | `kelpie_ai_ask` |
| `/v1/ai-record` | `kelpie_ai_record` |

CLI MCP adds additional tools:

| MCP Tool Name | Description |
|---|---|
| `kelpie_discover` | Scan network for Kelpie browsers |
| `kelpie_list_devices` | List currently known devices |
| `kelpie_pair` | Pair the CLI with a device (blocks until on-device approval, denial, or timeout) |
| `kelpie_group_navigate` | Navigate all devices to a URL |
| `kelpie_group_screenshot` | Screenshot all devices |
| `kelpie_group_find_button` | Find button across all devices |
| `kelpie_group_fill` | Fill a field on all devices |
| `kelpie_group_click` | Click an element on all devices |
| `kelpie_group_scroll2` | Resolution-aware scroll on all devices |
| `kelpie_group_find_element` | Find element across all devices |
| `kelpie_group_find_link` | Find link across all devices |
| `kelpie_group_find_input` | Find input across all devices |
| `kelpie_group_a11y` | Get accessibility tree from all devices |
| `kelpie_group_dom` | Get DOM from all devices |
| `kelpie_group_eval` | Evaluate JS on all devices |
| `kelpie_group_console` | Get console messages from all devices |
| `kelpie_group_errors` | Get JS errors from all devices |
| `kelpie_group_form_state` | Get form state from all devices |
| `kelpie_group_visible` | Get visible elements from all devices |
| `kelpie_group_keyboard_show` | Show keyboard on all devices |
| `kelpie_group_keyboard_hide` | Hide keyboard on all devices |
| `kelpie_ai_models` | List approved models and download status |
| `kelpie_ai_pull` | Download a GGUF model from HuggingFace |
| `kelpie_ai_remove` | Delete a downloaded model |
