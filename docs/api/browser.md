# Mollotov API — Browser Management Methods

Dialogs/alerts, tabs, iframes, cookies/storage, clipboard, geolocation, JS evaluation.

For protocol details, errors, and MCP tool names, see [README.md](README.md).

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

---

## Tabs

### `getTabs`
List all open tabs.

```json
POST /v1/get-tabs

Response:
{
  "success": true,
  "tabs": [
    {"id": 0, "url": "https://example.com", "title": "Example", "active": true},
    {"id": 1, "url": "https://example.com/about", "title": "About", "active": false}
  ],
  "count": 2,
  "activeTab": 0
}
```

### `newTab`
Open a new tab.

```json
POST /v1/new-tab
{
  "url": "https://example.com/page"  // optional, blank tab if omitted
}

Response:
{
  "success": true,
  "tab": {"id": 2, "url": "https://example.com/page", "title": "Page"},
  "tabCount": 3
}
```

### `switchTab`
Switch to a tab by ID.

```json
POST /v1/switch-tab
{
  "tabId": 1
}

Response:
{
  "success": true,
  "tab": {"id": 1, "url": "https://example.com/about", "title": "About"}
}
```

### `closeTab`
Close a tab by ID.

```json
POST /v1/close-tab
{
  "tabId": 1
}

Response:
{
  "success": true,
  "closed": 1,
  "tabCount": 2
}
```

---

## Iframe Access

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
## Geolocation

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

### `evaluate`
Evaluate a JavaScript expression and return the result. Executed via native bridge (not injection).

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
