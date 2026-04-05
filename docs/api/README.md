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
| [devtools.md](devtools.md) | Console/JS errors, network log, resource timeline, mutation observation, shadow DOM, request interception |
| [browser.md](browser.md) | Dialogs/alerts, tabs, iframes, cookies/storage, clipboard, geolocation, JS evaluation, renderer management |
| [ai.md](ai.md) | Local inference backends, model switching, inference, and audio recording endpoints |

---

## Protocol

- Base URL: `http://{device-ip}:{port}/v1/`
- Content-Type: `application/json`
- Auth: None (local network only)
- Default Port: `8420`
- Port fallback: if `8420` is already occupied, the app binds the next available local port and advertises that port via mDNS and `get-device-info`
- Concurrency: Requests are queued and processed sequentially per device. Rapid-fire commands are safe but will execute in order. No rate limiting enforced — the embedded HTTP server handles one command at a time.

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

| HTTP Endpoint | MCP Tool Name |
|---|---|
| `/v1/navigate` | `kelpie_navigate` |
| `/v1/back` | `kelpie_back` |
| `/v1/forward` | `kelpie_forward` |
| `/v1/reload` | `kelpie_reload` |
| `/v1/get-current-url` | `kelpie_get_current_url` |
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
| `/v1/get-resource-timeline` | `kelpie_get_resource_timeline` |
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
