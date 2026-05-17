# Kelpie API — Browser Management Methods

Dialogs/alerts, tabs, iframes, cookies/storage, clipboard, geolocation, JS evaluation, bookmarks, history, fullscreen.

For protocol details, errors, and MCP tool names, see [README.md](README.md).

---

## Bookmarks

### `bookmarksAdd`
Add a bookmark and return the full bookmark list.

If `title` is omitted, Kelpie stores the `url` as the title.

```json
POST /v1/bookmarks-add
{
  "url": "https://example.com/docs",
  "title": "Example Docs"
}

Response:
{
  "success": true,
  "bookmarks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Example Docs",
      "url": "https://example.com/docs",
      "createdAt": "2026-04-13T10:20:30Z"
    }
  ]
}
```

### `bookmarksRemove`
Remove a bookmark by bookmark UUID and return the remaining bookmark list.

```json
POST /v1/bookmarks-remove
{
  "id": "550e8400-e29b-41d4-a716-446655440000"
}

Response:
{
  "success": true,
  "bookmarks": []
}
```

If `id` is missing or not a valid UUID, the endpoint returns:

```json
{
  "success": false,
  "error": {
    "code": "MISSING_PARAM",
    "message": "id is required"
  }
}
```

### `bookmarksList`
List all saved bookmarks.

```json
POST /v1/bookmarks-list

Response:
{
  "success": true,
  "bookmarks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Example Docs",
      "url": "https://example.com/docs",
      "createdAt": "2026-04-13T10:20:30Z"
    },
    {
      "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "title": "Kelpie",
      "url": "https://unlikeotherai.github.io/kelpie",
      "createdAt": "2026-04-13T10:21:11Z"
    }
  ]
}
```

### `bookmarksClear`
Remove all saved bookmarks.

```json
POST /v1/bookmarks-clear

Response:
{
  "success": true,
  "cleared": true
}
```

---

## History

### `historyList`
List browsing history entries, newest first.

`limit` is optional and defaults to `100`.

```json
POST /v1/history-list
{
  "limit": 2
}

Response:
{
  "success": true,
  "entries": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "url": "https://example.com/docs",
      "title": "Example Docs",
      "timestamp": "2026-04-13T10:33:12Z"
    },
    {
      "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "url": "https://example.com/",
      "title": "Example Domain",
      "timestamp": "2026-04-13T10:31:04Z"
    }
  ],
  "total": 24
}
```

### `historyClear`
Clear all browsing history.

```json
POST /v1/history-clear

Response:
{
  "success": true,
  "cleared": true
}
```

---

## Dialogs & Alerts

### `getDialog`
Check if a JavaScript dialog (alert, confirm, prompt) or browser-level popup is currently showing.

```json
POST /v1/get-dialog

Response:
{
  "success": true,
  "showing": true,
  "dialog": {
    "type": "confirm",         // "alert" | "confirm" | "prompt" | "beforeunload"
    "message": "Are you sure you want to leave?",
    "defaultValue": null        // only for prompt dialogs
  }
}
```

### `handleDialog`
Accept or dismiss the current dialog.

```json
POST /v1/handle-dialog
{
  "action": "accept",          // "accept" | "dismiss"
  "promptText": null            // optional, text to enter for prompt dialogs
}

Response:
{
  "success": true,
  "action": "accept",
  "dialogType": "confirm"
}
```

### `setDialogAutoHandler`
Configure automatic handling of dialogs so LLMs don't get blocked by unexpected alerts.

```json
POST /v1/set-dialog-auto-handler
{
  "enabled": true,
  "defaultAction": "accept",   // "accept" | "dismiss" | "queue"
  "promptText": ""              // default text for prompt dialogs
}

Response:
{
  "success": true,
  "enabled": true
}
```

When set to `"queue"`, dialogs are captured and returned by `getDialog` instead of being auto-handled.

Queued dialogs are tied to the current page. If a new navigation starts before the dialog is handled, Kelpie dismisses the pending dialog to avoid leaving the WebView blocked on a stale result.

---

## Tabs

Tab management is **WebKit-only**. In Chromium (CEF) mode, all tab endpoints return:

```json
{
  "success": false,
  "error": {
    "code": "WEBKIT_ONLY",
    "message": "Tab management is not available in Chromium (CEF) mode. ..."
  }
}
```

Switch to WebKit first: `kelpie_set_renderer({"engine": "webkit"})`

### Per-window tab routing (macOS)

macOS supports multiple browser windows that share one HTTP server. Each
window owns its own tab list, so a `tabId` value is only unique within a
single window. To target a specific window, include an optional `windowId`
field in any tab-related request body.

- `get-tabs` without `windowId`: returns a `windows` array containing every
  window's tabs when more than one window is open, otherwise the single
  window's tab list as before.
- `get-tabs` with `windowId`: returns only that window's tabs.
- `new-tab`, `switch-tab`, `close-tab` with `windowId`: targets that window.
- `new-tab`, `switch-tab`, `close-tab` without `windowId`: target the
  currently focused (key) window. If a `tabId` is supplied without a
  `windowId`, the server locates the window that owns that tab.
- Unknown `windowId` values respond with `WINDOW_NOT_FOUND`.

iOS and Android always report `windowId: "main"` because they only support a
single browser window.

### `getTabs`
List all open tabs.

```json
POST /v1/get-tabs
{"windowId": "<uuid>"}              // optional; macOS only

Response (single window or `windowId` supplied):
{
  "success": true,
  "windowId": "<uuid>",
  "tabs": [
    {"id": "550e8400-e29b-41d4-a716-446655440000", "windowId": "<uuid>", "url": "https://example.com", "title": "Example", "active": true, "isLoading": false},
    {"id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>", "url": "https://example.com/about", "title": "About", "active": false, "isLoading": false}
  ],
  "count": 2,
  "activeTab": "550e8400-e29b-41d4-a716-446655440000"
}

Response (macOS only, multiple windows open, no `windowId`):
{
  "success": true,
  "windows": [
    {"windowId": "<uuid-1>", "tabs": [...], "count": 1, "activeTab": "..."},
    {"windowId": "<uuid-2>", "tabs": [...], "count": 2, "activeTab": "..."}
  ]
}
```

### `newTab`
Open a new tab, optionally navigating to a URL.

```json
POST /v1/new-tab
{"url": "https://example.com/page", "windowId": "<uuid>"}  // both optional

Response:
{
  "success": true,
  "tabId": "...",
  "tab": {"id": "...", "windowId": "<uuid>", "url": "https://example.com/page", "title": ""},
  "tabCount": 3,
  "windowId": "<uuid>"
}
```

`tabId` is the identifier to pass into later requests. It is the same value as `tab.id`.

### `switchTab`
Switch the active tab by UUID.

```json
POST /v1/switch-tab
{"tabId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>"}  // windowId optional

Response:
{
  "success": true,
  "tab": {"id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>", "url": "https://example.com/about", "title": "About", "active": true},
  "windowId": "<uuid>"
}
```

### `closeTab`
Close a tab by UUID.

```json
POST /v1/close-tab
{"tabId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>"}  // windowId optional

Response:
{
  "success": true,
  "closed": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "tabCount": 1,
  "windowId": "<uuid>"
}
```

If the last tab is closed, a new blank tab replaces it — `tabCount` will be `1`, not `0`.

---

## Iframe Access

> **Cross-origin limitation:** Same-origin iframes work on both platforms. Cross-origin iframes (Stripe, YouTube, etc.) have severe limitations: iOS cannot evaluate JS in cross-origin iframes at all; Android CDP can access them via `contextId` but only if the iframe's domain allows debugging. The `IFRAME_ACCESS_DENIED` error is returned when cross-origin access fails.

### `getIframes`
List all iframes on the current page.

```json
POST /v1/get-iframes

Response:
{
  "success": true,
  "iframes": [
    {
      "id": 0,
      "src": "https://payments.stripe.com/checkout",
      "name": "stripe-frame",
      "selector": "iframe[name='stripe-frame']",
      "rect": {"x": 20, "y": 400, "width": 350, "height": 300},
      "visible": true,
      "crossOrigin": true
    },
    {
      "id": 1,
      "src": "https://www.youtube.com/embed/abc123",
      "name": "",
      "selector": "iframe:nth-of-type(2)",
      "rect": {"x": 20, "y": 750, "width": 350, "height": 200},
      "visible": false,
      "crossOrigin": true
    }
  ],
  "count": 2
}
```

### `switchToIframe`
Switch command context into an iframe. All subsequent DOM/interaction commands operate within this iframe until `switchToMain` is called.

```json
POST /v1/switch-to-iframe
{
  "iframeId": 0                // or "selector": "iframe[name='stripe-frame']"
}

Response:
{
  "success": true,
  "iframe": {"id": 0, "src": "https://payments.stripe.com/checkout"},
  "context": "iframe:0"
}
```

### `switchToMain`
Switch command context back to the main page.

```json
POST /v1/switch-to-main

Response:
{
  "success": true,
  "context": "main"
}
```

### `getIframeContext`
Get the current command context (main page or which iframe).

```json
POST /v1/get-iframe-context

Response:
{
  "success": true,
  "context": "iframe:0",
  "iframe": {"id": 0, "src": "https://payments.stripe.com/checkout"}
}
```

---

## Cookies & Storage

### `getCookies`
Read cookies for the current page.

```json
POST /v1/get-cookies
{
  "url": null,                 // optional, specific URL — defaults to current page
  "name": null                 // optional, filter by cookie name
}

Response:
{
  "success": true,
  "cookies": [
    {
      "name": "session_id",
      "value": "abc123...",
      "domain": "example.com",
      "path": "/",
      "expires": "2026-04-30T00:00:00.000Z",
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    },
    {
      "name": "theme",
      "value": "light",
      "domain": "example.com",
      "path": "/",
      "expires": null,
      "httpOnly": false,
      "secure": false,
      "sameSite": "None"
    }
  ],
  "count": 2
}
```

### `setCookie`
Set a cookie.

```json
POST /v1/set-cookie
{
  "name": "session_id",
  "value": "new_value",
  "domain": "example.com",
  "path": "/",
  "httpOnly": true,
  "secure": true,
  "sameSite": "Lax",
  "expires": "2026-12-31T00:00:00.000Z"
}

Response:
{
  "success": true
}
```

### `deleteCookies`
Delete cookies by name, domain, or all.

```json
POST /v1/delete-cookies
{
  "name": "session_id",       // optional, delete specific cookie
  "domain": "example.com",    // optional, scope deletion
  "deleteAll": false           // optional, delete all cookies
}

Response:
{
  "success": true,
  "deleted": 1
}
```

### `getStorage`
Read localStorage or sessionStorage.

```json
POST /v1/get-storage
{
  "type": "local",             // "local" | "session"
  "key": null                  // optional, specific key — returns all if null
}

Response:
{
  "success": true,
  "type": "local",
  "entries": {
    "user_preferences": "{\"theme\":\"dark\",\"lang\":\"en\"}",
    "auth_token": "eyJ...",
    "onboarding_complete": "true"
  },
  "count": 3
}
```

### `setStorage`
Write to localStorage or sessionStorage.

```json
POST /v1/set-storage
{
  "type": "local",
  "key": "theme",
  "value": "dark"
}

Response:
{
  "success": true
}
```

### `clearStorage`
Clear localStorage or sessionStorage.

```json
POST /v1/clear-storage
{
  "type": "local"              // "local" | "session" | "both"
}

Response:
{
  "success": true,
  "cleared": "local"
}
```

---

## Clipboard

> **Platform caveat:** Reading clipboard on iOS triggers a system paste permission banner. On Android 10+, background clipboard read is restricted. `getClipboard` may return empty or trigger a visible OS prompt. `setClipboard` works reliably on both platforms.

### `getClipboard`
Read the current clipboard contents.

```json
POST /v1/get-clipboard

Response:
{
  "success": true,
  "text": "copied text content",
  "hasImage": false
}
```

### `setClipboard`
Write to the clipboard.

```json
POST /v1/set-clipboard
{
  "text": "text to copy"
}

Response:
{
  "success": true
}
```

---

## Geolocation

> **Platform caveat:** Android supports geolocation override via CDP `Emulation.setGeolocationOverride`. iOS has no public WKWebView API for this — would require a bridge script overriding `navigator.geolocation`. Returns `PLATFORM_NOT_SUPPORTED` on iOS until a bridge implementation is added.

### `setGeolocation`
Override the browser's geolocation. Useful for testing location-dependent content without physical movement.

```json
POST /v1/set-geolocation
{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "accuracy": 10               // optional, meters
}

Response:
{
  "success": true,
  "geolocation": {"latitude": 37.7749, "longitude": -122.4194, "accuracy": 10}
}
```

### `clearGeolocation`
Remove the geolocation override, returning to real device location.

```json
POST /v1/clear-geolocation

Response:
{
  "success": true
}
```

---
## Page Evaluation

---

## Keyboard & Viewport Simulation

On Android, keyboard visibility and height are derived from live `WindowInsets` observation. Kelpie computes keyboard height as `ime.bottom - navigationBars.bottom`, clamps it at zero, and converts reported heights and visible viewport dimensions to dp.

### `showKeyboard`
Programmatically show the soft keyboard by focusing an input element. Simulates a real user tapping a text field — the keyboard appears, the viewport shrinks, and the page reflows exactly as it would on a real device. Essential for testing that form fields remain visible and accessible when the keyboard is open.

```json
POST /v1/show-keyboard
{
  "selector": "#email-input",  // optional, focus this element first
  "keyboardType": "default"    // optional, "default" | "email" | "number" | "phone" | "url"
}

Response:
{
  "success": true,
  "keyboardVisible": true,
  "keyboardHeight": 336,
  "visibleViewport": {"width": 390, "height": 508},
  "focusedElement": {"selector": "#email-input", "visibleInViewport": true}
}
```

### `hideKeyboard`
Dismiss the soft keyboard.

```json
POST /v1/hide-keyboard

Response:
{
  "success": true,
  "keyboardVisible": false,
  "visibleViewport": {"width": 390, "height": 844}
}
```

### `getKeyboardState`
Check whether the keyboard is currently showing and how it affects the viewport.

```json
POST /v1/get-keyboard-state

Response:
{
  "success": true,
  "visible": true,
  "height": 336,
  "type": "default",
  "visibleViewport": {"width": 390, "height": 508},
  "focusedElement": {
    "selector": "#email-input",
    "rect": {"x": 20, "y": 320, "width": 350, "height": 44},
    "visibleInViewport": true,
    "obscuredByKeyboard": false
  }
}
```

### `setFullscreen`
Enable or disable fullscreen mode for the desktop browser window.

This endpoint is macOS-only. It returns `NO_WINDOW` if there is no active browser window.

If `enabled` is omitted, Kelpie treats it as `true`.

```json
POST /v1/set-fullscreen
{
  "enabled": true
}

Response:
{
  "success": true,
  "enabled": true
}
```

### `getFullscreen`
Get whether the desktop browser window is currently fullscreen.

This endpoint is macOS-only. It returns `NO_WINDOW` if there is no active browser window.

```json
POST /v1/get-fullscreen

Response:
{
  "success": true,
  "enabled": false
}
```

### `resizeViewport`
Simulate a reduced viewport size — shrink the visible area as if the keyboard, a toolbar, or another overlay is present. This does NOT change the actual device resolution; it constrains the WebView's visible bounds. Useful for testing responsive layouts at arbitrary viewport dimensions.

On macOS this updates the hosted viewport inside the browser shell and does not resize the native window. If the requested viewport is larger than the visible stage, Kelpie keeps the full requested size and makes the shell scrollable instead of scaling the viewport down.

Any `resize-viewport` call clears the active named viewport preset and enters raw custom viewport mode on macOS.

```json
POST /v1/resize-viewport
{
  "width": 390,               // optional, null = keep current
  "height": 500               // optional, null = keep current
}

Response:
{
  "success": true,
  "viewport": {"width": 390, "height": 500},
  "originalViewport": {"width": 390, "height": 844},
  "activePresetId": null
}
```

### `resetViewport`
Restore the viewport to its original full-screen dimensions.

On every supported platform this also clears the active named viewport preset. On macOS it returns to the full shell viewport instead of re-applying the last preset.

```json
POST /v1/reset-viewport

Response:
{
  "success": true,
  "viewport": {"width": 390, "height": 844},
  "activePresetId": null
}
```

### `setViewportPreset`
Activate one of the shared named viewport presets returned by `getViewportPresets`.

Supported on iPad, Android tablets, and macOS. Linux does not support named viewport presets yet.

```json
POST /v1/set-viewport-preset
{
  "presetId": "compact-base"
}

Response:
{
  "success": true,
  "activePresetId": "compact-base",
  "preset": {
    "id": "compact-base",
    "name": "Compact / Base",
    "inches": "6.1\" - 6.3\"",
    "pixels": "1170 x 2532 - 1206 x 2622"
  },
  "viewport": {"width": 393, "height": 852}
}
```

### `setOrientation`
Force the current browser orientation when the platform supports explicit orientation changes.

On macOS this does not rotate the native window. It only changes the staged viewport orientation when a named viewport preset is active. `full` mode and raw `custom` viewport mode return `INVALID_STATE` with an explanation instead of silently failing. `auto` is not supported on macOS staged presets.

macOS error reasons:
- `full-viewport`: a named preset is required before orientation can change
- `custom-viewport`: raw custom sizes have no orientation control
- `auto-unsupported`: staged macOS presets only accept explicit `portrait` or `landscape`

```json
POST /v1/set-orientation
{
  "orientation": "landscape"
}

Response:
{
  "success": true,
  "orientation": "landscape",
  "locked": "landscape",
  "activePresetId": "compact-base",
  "viewport": {"width": 852, "height": 393}
}
```

### `getOrientation`
Get the current browser orientation and lock state.

On macOS the reported orientation always matches the current hosted viewport dimensions. `locked` is only set when a named viewport preset is active; `full` and raw `custom` viewport modes return `null` because there is no separate lock state there.

```json
POST /v1/get-orientation

Response:
{
  "success": true,
  "orientation": "portrait",
  "locked": null
}
```

### `isElementObscured`
Check whether a specific element is currently obscured by the keyboard or out of the visible viewport. The LLM can use this to verify that form fields are accessible before trying to interact with them.

```json
POST /v1/is-element-obscured
{
  "selector": "#password-input"
}

Response:
{
  "success": true,
  "element": {
    "selector": "#password-input",
    "rect": {"x": 20, "y": 620, "width": 350, "height": 44}
  },
  "obscured": true,
  "reason": "keyboard",
  "keyboardOverlap": 128,
  "suggestion": "scroll up 128px or hide keyboard to reveal element"
}
```

---

## Page Evaluation

### `evaluate`
Evaluate a JavaScript expression and return the result. Executed via native WebView bridge (iOS) or CDP `Runtime.evaluate` (Android).

```json
POST /v1/evaluate
{
  "expression": "document.title"
}

Response:
{
  "success": true,
  "result": "Example Domain"
}
```

---
