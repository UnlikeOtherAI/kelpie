# Mollotov — API Reference

All methods are available via three interfaces:
1. **HTTP REST** — `POST http://{device}:{port}/v1/{method}`
2. **Browser MCP** — each browser exposes these as MCP tools
3. **CLI MCP** — the CLI wraps these with device targeting and group semantics

## Index

| Document | When to Read |
|---|---|
| [core.md](core.md) | Navigation, screenshots, DOM access, interaction, scrolling, viewport/device info, wait/sync |
| [llm.md](llm.md) | LLM-optimized methods — accessibility tree, annotated screenshots, visible elements, page text, form state, smart queries |
| [devtools.md](devtools.md) | Console/JS errors, network log, resource timeline, mutation observation, shadow DOM, request interception |
| [browser.md](browser.md) | Dialogs/alerts, tabs, iframes, cookies/storage, clipboard, geolocation, JS evaluation |

---

## Protocol

- Base URL: `http://{device-ip}:{port}/v1/`
- Content-Type: `application/json`
- Auth: None (local network only)
- Default Port: `8420`
- Concurrency: Requests are queued and processed sequentially per device. Rapid-fire commands are safe but will execute in order. No rate limiting enforced — the embedded HTTP server handles one command at a time.

---

## Platform Support Matrix

Not all methods have identical implementations on iOS and Android. Android has CDP (Chrome DevTools Protocol) which gives deep access. iOS relies on WKWebView native APIs + ephemeral bridge scripts for features WebKit doesn't expose.

| Method | Android | iOS | iOS Notes |
|---|---|---|---|
| Navigation, click, fill, type, scroll | Native | Native | |
| Screenshots (viewport) | Native | Native | `WKWebView.takeSnapshot` |
| Screenshots (full page) | CDP | Bridge | iOS requires scroll-and-stitch via bridge script |
| DOM access | CDP | Native | `evaluateJavaScript` via native bridge |
| Console messages | CDP `Runtime.consoleAPICalled` | Bridge | iOS requires `console.*` override bridge script |
| Network log | CDP `Network.*` | Partial | iOS: only top-level nav via `WKNavigationDelegate`; XHR/fetch tracking requires bridge script wrapping `fetch`/`XMLHttpRequest` |
| Resource timeline | CDP `Performance.*` | Partial | iOS: limited to `WKNavigationDelegate` events + `PerformanceObserver` bridge |
| Request interception | CDP `Fetch.*` | Not supported | iOS `WKURLSchemeHandler` only works for custom schemes, not HTTP/HTTPS |
| Mutation observation | CDP `DOM.*` | Bridge | iOS requires `MutationObserver` bridge script |
| Accessibility tree | CDP `Accessibility.*` | Bridge | iOS requires DOM traversal bridge script querying ARIA attributes |
| Page text extraction | CDP + Readability | Bridge | Both platforms need a Readability-style algorithm (bridge script or native port) |
| Shadow DOM traversal | CDP `DOM.*` | Bridge | Limited on both platforms for `mode: "closed"` shadow roots |
| Tabs | App-managed | App-managed | Both platforms must manage multiple WebView instances — no native tab API |
| Iframes (same-origin) | CDP | Native | |
| Iframes (cross-origin) | CDP (limited) | Not supported | iOS cannot evaluate JS in cross-origin iframes; Android CDP can with `contextId` |
| Cookies | CDP `Network.getCookies` | Native | `WKHTTPCookieStore` |
| Storage (local/session) | CDP/evaluate | Bridge | Both use `evaluateJavaScript` |
| Clipboard read | Native | Restricted | iOS shows system paste permission banner; Android 10+ restricts background access |
| Clipboard write | Native | Native | |
| Geolocation override | CDP `Emulation.*` | Not supported | No public WKWebView API; would require `navigator.geolocation` bridge override |
| Dialog handling | Native | Native | Both platforms have native dialog delegation APIs |
| Keyboard simulation | Native | Native | Both can programmatically focus/blur inputs |

**Legend:**
- **Native** — uses platform SDK APIs, no scripts needed
- **CDP** — uses Chrome DevTools Protocol (Android only)
- **Bridge** — uses ephemeral bridge script via `evaluateJavaScript` / `WKUserScript` (iOS)
- **Partial** — works but with reduced data compared to Android
- **Not supported** — no feasible implementation path; endpoint returns `PLATFORM_NOT_SUPPORTED` error
- **Restricted** — works but triggers OS-level permission UI the user must accept on-device

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

When exposed via MCP, methods use the `mollotov_` prefix:

| HTTP Endpoint | MCP Tool Name |
|---|---|
| `/v1/navigate` | `mollotov_navigate` |
| `/v1/back` | `mollotov_back` |
| `/v1/forward` | `mollotov_forward` |
| `/v1/reload` | `mollotov_reload` |
| `/v1/get-current-url` | `mollotov_get_current_url` |
| `/v1/screenshot` | `mollotov_screenshot` |
| `/v1/get-dom` | `mollotov_get_dom` |
| `/v1/query-selector` | `mollotov_query_selector` |
| `/v1/query-selector-all` | `mollotov_query_selector_all` |
| `/v1/get-element-text` | `mollotov_get_element_text` |
| `/v1/get-attributes` | `mollotov_get_attributes` |
| `/v1/click` | `mollotov_click` |
| `/v1/tap` | `mollotov_tap` |
| `/v1/fill` | `mollotov_fill` |
| `/v1/type` | `mollotov_type` |
| `/v1/select-option` | `mollotov_select_option` |
| `/v1/check` | `mollotov_check` |
| `/v1/uncheck` | `mollotov_uncheck` |
| `/v1/scroll` | `mollotov_scroll` |
| `/v1/scroll2` | `mollotov_scroll2` |
| `/v1/scroll-to-top` | `mollotov_scroll_to_top` |
| `/v1/scroll-to-bottom` | `mollotov_scroll_to_bottom` |
| `/v1/get-viewport` | `mollotov_get_viewport` |
| `/v1/get-device-info` | `mollotov_get_device_info` |
| `/v1/get-capabilities` | `mollotov_get_capabilities` |
| `/v1/wait-for-element` | `mollotov_wait_for_element` |
| `/v1/wait-for-navigation` | `mollotov_wait_for_navigation` |
| `/v1/find-element` | `mollotov_find_element` |
| `/v1/find-button` | `mollotov_find_button` |
| `/v1/find-link` | `mollotov_find_link` |
| `/v1/find-input` | `mollotov_find_input` |
| `/v1/evaluate` | `mollotov_evaluate` |
| `/v1/get-console-messages` | `mollotov_get_console_messages` |
| `/v1/get-js-errors` | `mollotov_get_js_errors` |
| `/v1/get-network-log` | `mollotov_get_network_log` |
| `/v1/get-resource-timeline` | `mollotov_get_resource_timeline` |
| `/v1/clear-console` | `mollotov_clear_console` |
| `/v1/get-accessibility-tree` | `mollotov_get_accessibility_tree` |
| `/v1/screenshot-annotated` | `mollotov_screenshot_annotated` |
| `/v1/click-annotation` | `mollotov_click_annotation` |
| `/v1/fill-annotation` | `mollotov_fill_annotation` |
| `/v1/get-visible-elements` | `mollotov_get_visible_elements` |
| `/v1/get-page-text` | `mollotov_get_page_text` |
| `/v1/get-form-state` | `mollotov_get_form_state` |
| `/v1/get-dialog` | `mollotov_get_dialog` |
| `/v1/handle-dialog` | `mollotov_handle_dialog` |
| `/v1/set-dialog-auto-handler` | `mollotov_set_dialog_auto_handler` |
| `/v1/get-tabs` | `mollotov_get_tabs` |
| `/v1/new-tab` | `mollotov_new_tab` |
| `/v1/switch-tab` | `mollotov_switch_tab` |
| `/v1/close-tab` | `mollotov_close_tab` |
| `/v1/get-iframes` | `mollotov_get_iframes` |
| `/v1/switch-to-iframe` | `mollotov_switch_to_iframe` |
| `/v1/switch-to-main` | `mollotov_switch_to_main` |
| `/v1/get-iframe-context` | `mollotov_get_iframe_context` |
| `/v1/get-cookies` | `mollotov_get_cookies` |
| `/v1/set-cookie` | `mollotov_set_cookie` |
| `/v1/delete-cookies` | `mollotov_delete_cookies` |
| `/v1/get-storage` | `mollotov_get_storage` |
| `/v1/set-storage` | `mollotov_set_storage` |
| `/v1/clear-storage` | `mollotov_clear_storage` |
| `/v1/watch-mutations` | `mollotov_watch_mutations` |
| `/v1/get-mutations` | `mollotov_get_mutations` |
| `/v1/stop-watching` | `mollotov_stop_watching` |
| `/v1/query-shadow-dom` | `mollotov_query_shadow_dom` |
| `/v1/get-shadow-roots` | `mollotov_get_shadow_roots` |
| `/v1/get-clipboard` | `mollotov_get_clipboard` |
| `/v1/set-clipboard` | `mollotov_set_clipboard` |
| `/v1/set-geolocation` | `mollotov_set_geolocation` |
| `/v1/clear-geolocation` | `mollotov_clear_geolocation` |
| `/v1/set-request-interception` | `mollotov_set_request_interception` |
| `/v1/get-intercepted-requests` | `mollotov_get_intercepted_requests` |
| `/v1/clear-request-interception` | `mollotov_clear_request_interception` |
| `/v1/show-keyboard` | `mollotov_show_keyboard` |
| `/v1/hide-keyboard` | `mollotov_hide_keyboard` |
| `/v1/get-keyboard-state` | `mollotov_get_keyboard_state` |
| `/v1/resize-viewport` | `mollotov_resize_viewport` |
| `/v1/reset-viewport` | `mollotov_reset_viewport` |
| `/v1/is-element-obscured` | `mollotov_is_element_obscured` |

CLI MCP adds additional tools:

| MCP Tool Name | Description |
|---|---|
| `mollotov_discover` | Scan network for Mollotov browsers |
| `mollotov_list_devices` | List currently known devices |
| `mollotov_group_navigate` | Navigate all devices to a URL |
| `mollotov_group_screenshot` | Screenshot all devices |
| `mollotov_group_find_button` | Find button across all devices |
| `mollotov_group_fill` | Fill a field on all devices |
| `mollotov_group_click` | Click an element on all devices |
| `mollotov_group_scroll2` | Resolution-aware scroll on all devices |
| `mollotov_group_find_element` | Find element across all devices |
| `mollotov_group_find_link` | Find link across all devices |
| `mollotov_group_find_input` | Find input across all devices |
| `mollotov_group_a11y` | Get accessibility tree from all devices |
| `mollotov_group_dom` | Get DOM from all devices |
| `mollotov_group_eval` | Evaluate JS on all devices |
| `mollotov_group_console` | Get console messages from all devices |
| `mollotov_group_errors` | Get JS errors from all devices |
| `mollotov_group_form_state` | Get form state from all devices |
| `mollotov_group_visible` | Get visible elements from all devices |
| `mollotov_group_keyboard_show` | Show keyboard on all devices |
| `mollotov_group_keyboard_hide` | Hide keyboard on all devices |
