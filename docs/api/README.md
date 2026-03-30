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
| `ANNOTATION_EXPIRED` | 400 | Annotation index references a stale screenshotAnnotated result |

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

---

## MCP Tool Names

When exposed via MCP, methods use the `mollotov_` prefix:

| HTTP Endpoint | MCP Tool Name |
|---|---|
| `/v1/navigate` | `mollotov_navigate` |
| `/v1/screenshot` | `mollotov_screenshot` |
| `/v1/click` | `mollotov_click` |
| `/v1/fill` | `mollotov_fill` |
| `/v1/scroll2` | `mollotov_scroll2` |
| `/v1/find-button` | `mollotov_find_button` |
| `/v1/get-dom` | `mollotov_get_dom` |
| `/v1/get-device-info` | `mollotov_get_device_info` |
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
| `/v1/get-tabs` | `mollotov_get_tabs` |
| `/v1/new-tab` | `mollotov_new_tab` |
| `/v1/switch-tab` | `mollotov_switch_tab` |
| `/v1/close-tab` | `mollotov_close_tab` |
| `/v1/get-iframes` | `mollotov_get_iframes` |
| `/v1/switch-to-iframe` | `mollotov_switch_to_iframe` |
| `/v1/switch-to-main` | `mollotov_switch_to_main` |
| `/v1/get-cookies` | `mollotov_get_cookies` |
| `/v1/get-storage` | `mollotov_get_storage` |
| `/v1/set-storage` | `mollotov_set_storage` |
| `/v1/watch-mutations` | `mollotov_watch_mutations` |
| `/v1/get-mutations` | `mollotov_get_mutations` |
| `/v1/stop-watching` | `mollotov_stop_watching` |
| `/v1/query-shadow-dom` | `mollotov_query_shadow_dom` |
| `/v1/get-clipboard` | `mollotov_get_clipboard` |
| `/v1/set-clipboard` | `mollotov_set_clipboard` |
| `/v1/set-geolocation` | `mollotov_set_geolocation` |
| `/v1/clear-geolocation` | `mollotov_clear_geolocation` |
| `/v1/set-request-interception` | `mollotov_set_request_interception` |
| `/v1/get-intercepted-requests` | `mollotov_get_intercepted_requests` |
| `/v1/clear-request-interception` | `mollotov_clear_request_interception` |

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
