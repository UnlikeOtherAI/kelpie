# Kelpie API — Core Methods

Navigation, screenshots, DOM access, interaction, scrolling, viewport/device info, wait/sync.

For protocol details, errors, and MCP tool names, see [README.md](README.md).

---

## Navigation

### `navigate`
Navigate to a URL.

```json
POST /v1/navigate
{
  "url": "https://example.com"
}

Response:
{
  "success": true,
  "url": "https://example.com",
  "title": "Example Domain",
  "loadTime": 1243
}
```

### `back`
Go back in browser history.

```json
POST /v1/back

Response:
{
  "success": true,
  "url": "https://previous-page.com",
  "title": "Previous Page"
}
```

### `forward`
Go forward in browser history.

```json
POST /v1/forward

Response:
{
  "success": true,
  "url": "https://next-page.com",
  "title": "Next Page"
}
```

### `reload`
Reload the current page.

```json
POST /v1/reload

Response:
{
  "success": true,
  "url": "https://current-page.com",
  "loadTime": 890
}
```

### `getCurrentUrl`
Get the current page URL and title.

```json
POST /v1/get-current-url

Response:
{
  "url": "https://example.com/page",
  "title": "Page Title"
}
```

---

## Scripted Recording

### `swipe`
Swipe between two viewport coordinates and render a visible swipe trail. This dispatches synthetic pointer events to the page for JS-driven drag targets; it does not guarantee native browser scrolling or OS gesture behavior.

```json
POST /v1/swipe
{
  "from": { "x": 200, "y": 700 },
  "to": { "x": 200, "y": 200 },
  "durationMs": 500,
  "steps": 20,
  "color": "#3B82F6"
}
```

### `show-commentary` / `hide-commentary`
Show or hide a commentary pill inside the page viewport.

```json
POST /v1/show-commentary
{
  "text": "Watch the signup button",
  "position": "bottom",
  "durationMs": 0
}
```

```json
POST /v1/hide-commentary
```

### `highlight` / `hide-highlight`
Draw or remove a highlight ring around an element.

```json
POST /v1/highlight
{
  "selector": "#signup",
  "color": "#EF4444",
  "thickness": 3,
  "padding": 6,
  "animation": "draw",
  "durationMs": 2000
}
```

```json
POST /v1/hide-highlight
```

### `play-script`
Run a timed walkthrough script. While it is active, every request except `abort-script` and `get-script-status` is rejected with `RECORDING_IN_PROGRESS`.

```json
POST /v1/play-script
{
  "overlayColor": "#3B82F6",
  "defaultWaitBetweenActions": 500,
  "continueOnError": false,
  "actions": [
    { "action": "commentary", "text": "Welcome", "durationMs": 0 },
    { "action": "wait", "ms": 1500 },
    { "action": "hide-commentary" },
    { "action": "highlight", "selector": "#signup", "animation": "draw" },
    { "action": "click", "selector": "#signup" }
  ]
}
```

Successful responses return `actionsExecuted`, `totalDurationMs`, `errors`, and any screenshot temp-file paths captured during playback.

Inside a script, action names follow the recording-script contract rather than the raw endpoint names. For example, use `commentary` to show commentary and `hide-commentary` to dismiss it.

### `abort-script`
Abort the active script and return the partial playback result collected so far.

```json
POST /v1/abort-script
```

### `get-script-status`
Return whether a script is playing, the current action index, and the elapsed playback time.

```json
POST /v1/get-script-status
```

---

## External Display Debug

These methods exist to verify the iOS external-display sync flow without a real AirPlay target.

### `debug-attach-local-tv`
Create a debug-only local TV WebView and expose it on port `8421`, using the same sync path as the real external-display browser.

```json
POST /v1/debug-attach-local-tv

Response:
{
  "success": true,
  "connected": true,
  "attachPath": "debug-local",
  "port": 8421
}
```

### `debug-detach-tv`
Tear down the debug local TV WebView or any active external-display attachment.

```json
POST /v1/debug-detach-tv

Response:
{
  "success": true,
  "connected": false
}
```

### `set-tv-sync`
Enable or disable phone-to-TV sync programmatically. This drives the same state as the on-screen sync button.

```json
POST /v1/set-tv-sync
{
  "enabled": true
}

Response:
{
  "success": true,
  "enabled": true,
  "connected": true
}
```

### `get-tv-sync`
Read the current sync state and external-display attachment state.

```json
POST /v1/get-tv-sync

Response:
{
  "success": true,
  "enabled": true,
  "connected": true,
  "attachPath": "debug-local"
}
```

### `setHome`
Set the device's home page URL. Persisted across app restarts.

```json
POST /v1/set-home
{
  "url": "https://example.com"
}

Response:
{
  "success": true,
  "url": "https://example.com"
}
```

### `getHome`
Get the current home page URL.

```json
POST /v1/get-home

Response:
{
  "success": true,
  "url": "https://example.com"
}
```

### `setFullscreen`
Enable or disable fullscreen mode for the desktop browser window.

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

```json
POST /v1/get-fullscreen

Response:
{
  "success": true,
  "enabled": false
}
```

---

## Screenshots

### `screenshot`
Capture a screenshot of the current viewport. When `fullPage: true`, captures the entire scrollable page. On Android this uses CDP `Page.captureScreenshot` with `captureBeyondViewport`. On iOS, `WKWebView.takeSnapshot` only captures the visible viewport — full-page requires a scroll-and-stitch approach (slower, may have minor seam artifacts).

> **CLI note:** The HTTP API always returns base64. The CLI wraps this — it auto-saves to a file and returns the file path instead, so LLMs never handle raw base64 in conversation. See [cli.md](../cli.md) for `--output` and `--base64` flags.

```json
POST /v1/screenshot
{
  "fullPage": false,       // optional, default false
  "format": "png",         // optional, "png" | "jpeg"
  "quality": 80            // optional, jpeg only, 1-100
}

Response:
{
  "success": true,
  "image": "base64-encoded-image-data",
  "width": 390,
  "height": 844,
  "format": "png"
}
```

---

## DOM Access

### `getDOM`
Get the full DOM tree or a subtree.

```json
POST /v1/get-dom
{
  "selector": "body",      // optional, default "html"
  "depth": 5               // optional, max depth, default unlimited
}

Response:
{
  "success": true,
  "html": "<body>...</body>",
  "nodeCount": 342
}
```

### `querySelector`
Find a single element matching a CSS selector.

```json
POST /v1/query-selector
{
  "selector": "#submit-btn"
}

Response:
{
  "success": true,
  "found": true,
  "element": {
    "tag": "button",
    "id": "submit-btn",
    "text": "Submit",
    "classes": ["btn", "btn-primary"],
    "attributes": {"type": "submit", "disabled": null},
    "rect": {"x": 120, "y": 580, "width": 200, "height": 44},
    "visible": true
  }
}
```

### `querySelectorAll`
Find all elements matching a CSS selector.

```json
POST /v1/query-selector-all
{
  "selector": "a.nav-link"
}

Response:
{
  "success": true,
  "count": 5,
  "elements": [
    {
      "tag": "a",
      "text": "Home",
      "attributes": {"href": "/"},
      "rect": {"x": 20, "y": 60, "width": 60, "height": 24},
      "visible": true
    }
  ]
}
```

### `getElementText`
Get the text content of an element.

```json
POST /v1/get-element-text
{
  "selector": "h1"
}

Response:
{
  "success": true,
  "text": "Welcome to Example"
}
```

### `getAttributes`
Get all attributes of an element.

```json
POST /v1/get-attributes
{
  "selector": "#email-input"
}

Response:
{
  "success": true,
  "attributes": {
    "type": "email",
    "name": "email",
    "placeholder": "Enter your email",
    "required": "",
    "aria-label": "Email address"
  }
}
```

---

## Interaction

### `click`
Click an element.

```json
POST /v1/click
{
  "selector": "#submit-btn",  // CSS selector
  "timeout": 5000             // optional, wait for element, ms
}

Response:
{
  "success": true,
  "element": {
    "tag": "button",
    "text": "Submit"
  }
}
```

### `tap`
Tap at specific coordinates (for elements that are hard to select).

```json
POST /v1/tap
{
  "x": 195,
  "y": 420
}

Response:
{
  "success": true,
  "x": 195,
  "y": 420
}
```

### `fill`
Fill a form field with text. Clears existing content first. Supports two modes: `instant` (default) sets the value immediately, `typing` types character by character with configurable delay.

```json
POST /v1/fill
{
  "selector": "#email-input",
  "value": "user@example.com",
  "mode": "instant",          // optional: "instant" (default) or "typing"
  "delay": 50,                // optional: ms between keystrokes when mode is "typing" (default 50)
  "timeout": 5000             // optional
}

Response:
{
  "success": true,
  "selector": "#email-input",
  "value": "user@example.com"
}
```

When `mode` is `"typing"`, the field is cleared first, then each character is typed with `keydown`, `keypress`, `input`, and `keyup` events. The action blocks until all characters are typed. Speed guidelines for `delay`: 30 = fast, 50 = natural (default), 80-100 = deliberate, 150+ = dramatic.

### `type`
Type text character by character (triggers key events).

```json
POST /v1/type
{
  "selector": "#search-box",  // optional, focuses element first
  "text": "search query",
  "delay": 50                 // optional, ms between keystrokes
}

Response:
{
  "success": true,
  "typed": "search query"
}
```

### `selectOption`
Select an option from a `<select>` element.

```json
POST /v1/select-option
{
  "selector": "#country",
  "value": "us"               // by value attribute
}

Response:
{
  "success": true,
  "selected": {"value": "us", "text": "United States"}
}
```

### `check`
Check a checkbox or radio button.

```json
POST /v1/check
{
  "selector": "#agree-terms"
}

Response:
{
  "success": true,
  "checked": true
}
```

### `uncheck`
Uncheck a checkbox.

```json
POST /v1/uncheck
{
  "selector": "#agree-terms"
}

Response:
{
  "success": true,
  "checked": false
}
```

---

## Scrolling

### `scroll`
Scroll by a fixed amount.

```json
POST /v1/scroll
{
  "deltaX": 0,              // horizontal scroll
  "deltaY": 500             // vertical scroll (positive = down)
}

Response:
{
  "success": true,
  "scrollX": 0,
  "scrollY": 500
}
```

### `scroll2`
**Resolution-aware scroll** — scrolls to make a target element visible, adapting to the device's viewport size. Unlike `scroll`, this method calculates the correct scroll distance for the specific device resolution.

```json
POST /v1/scroll2
{
  "selector": "#footer",          // scroll until this element is visible
  "position": "center",           // optional, "top" | "center" | "bottom"
  "maxScrolls": 10                // optional, safety limit
}

Response:
{
  "success": true,
  "element": {
    "tag": "footer",
    "visible": true,
    "rect": {"x": 0, "y": 400, "width": 390, "height": 200}
  },
  "scrollsPerformed": 3,
  "viewport": {"width": 390, "height": 844}
}
```

### `scrollToTop`

```json
POST /v1/scroll-to-top

Response:
{
  "success": true,
  "scrollY": 0
}
```

### `scrollToBottom`

```json
POST /v1/scroll-to-bottom

Response:
{
  "success": true,
  "scrollY": 4200
}
```

### `scrollToY`
Scroll to an absolute pixel offset. On macOS this also syncs the 3D inspector's stored scroll state so the operation works while the inspector is active.

```json
POST /v1/scroll-to-y
{
  "y": 800,
  "x": 0
}

Response:
{
  "success": true,
  "scrollX": 0,
  "scrollY": 800,
  "maxScrollY": 4200
}
```

Errors: `MISSING_PARAM` (y is required), `EVAL_ERROR`.

---

## Viewport & Device Info

### `getViewport`
Get current viewport dimensions and device info.

On macOS this reports the live hosted browser viewport, not the outer app window size. Preset device modes can therefore return a viewport smaller than the outer shell without resizing the native window.

```json
POST /v1/get-viewport

Response:
{
  "width": 390,
  "height": 844,
  "devicePixelRatio": 3,
  "platform": "ios",
  "deviceName": "iPhone 15 Pro",
  "orientation": "portrait"
}
```

### `getViewportPresets`
List the named viewport presets available for the current device or window geometry.

On iPad and Android, this is only supported on tablets. Phones return `supportsViewportPresets: false`. On macOS this reports the shared preset catalog that fits the current shell window. Linux does not support named viewport presets yet.

```json
POST /v1/get-viewport-presets

Response:
{
  "success": true,
  "supportsViewportPresets": true,
  "presets": [
    {
      "id": "compact-base",
      "name": "Compact / Base",
      "inches": "6.1\" - 6.3\"",
      "pixels": "1170 x 2532 - 1206 x 2622",
      "viewport": {
        "portrait": {"width": 393, "height": 852},
        "landscape": {"width": 852, "height": 393}
      }
    }
  ],
  "availablePresetIds": ["compact-base", "standard-pro", "large-plus"],
  "activePresetId": "compact-base"
}
```

### `getOrientation`
Get the current orientation and lock state.

On macOS the orientation is derived from the hosted browser viewport, not the native window. `locked` is only non-null when a named viewport preset is active.

```json
POST /v1/get-orientation

Response:
{
  "success": true,
  "orientation": "landscape",
  "locked": "landscape"
}
```

### `getDeviceInfo`
Get comprehensive device metadata. This is the primary endpoint for LLMs to understand what device they're talking to. Returns everything the platform can report.

```json
POST /v1/get-device-info

Response:
{
  "device": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "My iPhone",
    "model": "iPhone 15 Pro",
    "manufacturer": "Apple",
    "platform": "ios",
    "osName": "iOS",
    "osVersion": "17.4",
    "osBuild": "21E219",
    "architecture": "arm64",
    "isSimulator": false,
    "isTablet": false
  },
  "display": {
    "width": 390,
    "height": 844,
    "physicalWidth": 1170,
    "physicalHeight": 2532,
    "devicePixelRatio": 3,
    "orientation": "portrait",
    "refreshRate": 120,
    "screenDiagonal": 6.1,
    "safeAreaInsets": {"top": 59, "bottom": 34, "left": 0, "right": 0}
  },
  "network": {
    "ip": "192.168.1.42",
    "port": 8420,
    "mdnsName": "my-iphone._kelpie._tcp.local",
    "networkType": "wifi",
    "ssid": "MyNetwork"
  },
  "browser": {
    "engine": "WebKit",
    "engineVersion": "617.1.17",
    "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) ...",
    "viewportWidth": 390,
    "viewportHeight": 750
  },
  "app": {
    "version": "1.0.0",
    "build": "1",
    "httpServerActive": true,
    "mcpServerActive": true,
    "mdnsActive": true,
    "uptime": 3600
  },
  "system": {
    "locale": "en_US",
    "timezone": "America/Los_Angeles",
    "batteryLevel": 0.85,
    "batteryCharging": true,
    "thermalState": "nominal",
    "availableMemory": 2048,
    "totalMemory": 6144
  }
}
```

**iOS-specific fields:** `thermalState`, `safeAreaInsets`, `screenDiagonal`
**Android-specific fields:** `manufacturer`, `osBuild`, `architecture`, `refreshRate`
**Simulator-only fields:** `isSimulator: true` — the LLM should know it's not a real device

All fields are best-effort — if a value is unavailable on the platform, it returns `null` rather than being omitted.

### `getCapabilities`
Get which API methods this browser instance supports. Enables capability negotiation — the CLI or LLM can check before sending commands that may not be available on a given platform/version.

Named viewport preset support appears in the capability map as `viewportPresets`.

```json
POST /v1/get-capabilities

Response:
{
  "success": true,
  "version": "1.0.0",
  "platform": "ios",
  "supported": [
    "navigate", "back", "forward", "reload", "screenshot", "click", "fill",
    "type", "scroll", "scroll2", "getDOM", "querySelector", "getDeviceInfo",
    "getAccessibilityTree", "screenshotAnnotated", "getVisibleElements",
    "getPageText", "getFormState", "getTabs", "getCookies", "getStorage",
    "showKeyboard", "hideKeyboard", "evaluate", "getDialog", "handleDialog"
  ],
  "partial": [
    "getConsoleMessages", "getNetworkLog", "getResourceTimeline",
    "watchMutations", "getClipboard"
  ],
  "unsupported": [
    "setRequestInterception", "setGeolocation"
  ]
}
```

`partial` means the feature works but with reduced data compared to Android (see Platform Support Matrix in [README.md](README.md)).

---

## Wait / Sync

### `waitForElement`
Wait for an element to appear in the DOM.

```json
POST /v1/wait-for-element
{
  "selector": ".results-loaded",
  "timeout": 10000,           // ms, default 5000
  "state": "visible"          // "attached" | "visible" | "hidden"
}

Response:
{
  "success": true,
  "element": {
    "tag": "div",
    "classes": ["results-loaded"],
    "visible": true
  },
  "waitTime": 2340
}
```

### `waitForNavigation`
Wait for a navigation event to complete.

```json
POST /v1/wait-for-navigation
{
  "timeout": 10000
}

Response:
{
  "success": true,
  "url": "https://example.com/dashboard",
  "title": "Dashboard",
  "loadTime": 1560
}
```

---
