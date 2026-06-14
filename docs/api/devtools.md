# Kelpie API — DevTools Methods

Console/JS errors, network log, network inspector, resource timeline, WebSocket monitoring, mutation observation, shadow DOM, request interception.

> **iOS parity note:** Many DevTools features on iOS use ephemeral bridge scripts since WKWebView lacks CDP. See the [Platform Support Matrix](README.md) for per-method details. Network logging now reaches parity across iOS, Android, and macOS (filters and summary). Request interception is unimplemented on every platform (see below).

For protocol details, errors, and MCP tool names, see [README.md](README.md).

---

## Console & DevTools

### `getConsoleMessages`
Get JavaScript console messages (errors, warnings, logs) from the current page. The browser captures these in real time via an injected native bridge on Android and `WKScriptMessageHandler` console override on Apple platforms.

```json
POST /v1/get-console-messages
{
  "level": null,              // optional filter: "log" | "warn" | "error" | "info" | "debug"
  "since": null,              // optional, ISO timestamp — only messages after this time
  "limit": 100                // optional, max messages to return
}

Response:
{
  "success": true,
  "messages": [
    {
      "level": "error",
      "text": "Uncaught TypeError: Cannot read properties of undefined (reading 'map')",
      "source": "https://example.com/app.js",
      "line": 142,
      "column": 23,
      "timestamp": "2026-03-30T10:15:32.456Z",
      "stackTrace": "TypeError: Cannot read properties of undefined (reading 'map')\n    at render (app.js:142:23)\n    at ..."
    },
    {
      "level": "warn",
      "text": "Deprecation warning: ...",
      "source": "https://example.com/vendor.js",
      "line": 891,
      "column": 5,
      "timestamp": "2026-03-30T10:15:31.200Z",
      "stackTrace": null
    },
    {
      "level": "log",
      "text": "App initialized",
      "source": "https://example.com/app.js",
      "line": 10,
      "column": 1,
      "timestamp": "2026-03-30T10:15:30.100Z",
      "stackTrace": null
    }
  ],
  "count": 3,
  "hasMore": false
}
```

### `getJSErrors`
Shorthand for `getConsoleMessages` filtered to errors only. Includes uncaught exceptions, promise rejections, and `console.error` calls.

```json
POST /v1/get-js-errors

Response:
{
  "success": true,
  "errors": [
    {
      "type": "uncaught-exception",
      "text": "Uncaught TypeError: Cannot read properties of undefined (reading 'map')",
      "source": "https://example.com/app.js",
      "line": 142,
      "column": 23,
      "timestamp": "2026-03-30T10:15:32.456Z",
      "stackTrace": "..."
    },
    {
      "type": "unhandled-rejection",
      "text": "Unhandled Promise rejection: NetworkError: Failed to fetch",
      "source": "https://example.com/api.js",
      "line": 55,
      "column": 12,
      "timestamp": "2026-03-30T10:15:33.789Z",
      "stackTrace": "..."
    }
  ],
  "count": 2
}
```

### `getNetworkLog`
Get the full network activity log — every resource the page loaded, with timing data. Entries are derived from the page's Resource Timing API on all platforms.

```json
POST /v1/get-network-log
{
  "type": null,               // optional filter: "document" | "script" | "stylesheet" | "image" | "font" | "xhr" | "fetch" | "websocket" | "other"
  "status": null,             // optional filter: "success" (2xx–3xx), "error" (>=400 or failed), or "pending" (in-flight)
  "since": null,              // optional, epoch millis or ISO-8601 timestamp — only entries started at/after this time
  "limit": 200                // optional, max entries
}

Response:
{
  "success": true,
  "entries": [
    {
      "url": "https://example.com/",
      "type": "document",
      "method": "GET",
      "status": 200,
      "statusText": "OK",
      "mimeType": "text/html",
      "size": 45230,
      "transferSize": 12800,
      "timing": {
        "started": "2026-03-30T10:15:29.000Z",
        "dnsLookup": 12,
        "tcpConnect": 25,
        "tlsHandshake": 45,
        "requestSent": 2,
        "waiting": 180,
        "contentDownload": 35,
        "total": 299
      },
      "initiator": "navigation"
    },
    {
      "url": "https://example.com/app.js",
      "type": "script",
      "method": "GET",
      "status": 200,
      "statusText": "OK",
      "mimeType": "application/javascript",
      "size": 234567,
      "transferSize": 78200,
      "timing": {
        "started": "2026-03-30T10:15:29.300Z",
        "total": 145
      },
      "initiator": "parser:https://example.com/:12"
    },
    {
      "url": "https://example.com/styles.css",
      "type": "stylesheet",
      "method": "GET",
      "status": 200,
      "statusText": "OK",
      "mimeType": "text/css",
      "size": 18900,
      "transferSize": 5600,
      "timing": {
        "started": "2026-03-30T10:15:29.310Z",
        "total": 89
      },
      "initiator": "parser:https://example.com/:8"
    },
    {
      "url": "https://api.example.com/data",
      "type": "fetch",
      "method": "POST",
      "status": 500,
      "statusText": "Internal Server Error",
      "mimeType": "application/json",
      "size": 128,
      "transferSize": 128,
      "timing": {
        "started": "2026-03-30T10:15:30.500Z",
        "total": 2340
      },
      "initiator": "script:https://example.com/app.js:55"
    }
  ],
  "count": 4,
  "hasMore": false,
  "summary": {
    "totalRequests": 4,
    "totalSize": 298825,
    "totalTransferSize": 96728,
    "byType": {
      "document": 1,
      "script": 1,
      "stylesheet": 1,
      "fetch": 1
    },
    "errors": 1,
    "loadTime": 2640
  }
}
```

The `type`, `status`, and `since` filters are now honored on all platforms (iOS, Android, macOS), and all three return the `summary` aggregate (`totalRequests`, `totalSize`, `totalTransferSize`, `byType`, `errors`, `loadTime`) computed over the filtered entries. `hasMore` reflects whether the filtered set exceeded `limit`.

---

## Network Inspector

These endpoints expose the macOS network inspector state. They work against the inspector's captured request list and selection state rather than the cross-platform `get-network-log` payload.

### `networkList`
List captured network requests in summary form.

The request body is optional. The current implementation also accepts optional filters: `method`, `category`, `statusRange`, and `urlPattern`.

```json
POST /v1/network-list

Response:
{
  "success": true,
  "entries": [
    {
      "index": 0,
      "method": "GET",
      "url": "https://example.com/",
      "statusCode": 200,
      "contentType": "text/html",
      "category": "HTML",
      "duration": 142,
      "size": 45230
    },
    {
      "index": 1,
      "method": "POST",
      "url": "https://api.example.com/data",
      "statusCode": 500,
      "contentType": "application/json",
      "category": "JSON",
      "duration": 2340,
      "size": 128
    }
  ],
  "total": 2
}
```

### `networkDetail`
Get the full detail for a captured request by summary index.

```json
POST /v1/network-detail
{
  "index": 1
}

Response:
{
  "success": true,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "POST",
  "url": "https://api.example.com/data",
  "statusCode": 500,
  "contentType": "application/json",
  "category": "JSON",
  "initiator": "js",
  "requestHeaders": {
    "Content-Type": "application/json"
  },
  "responseHeaders": {
    "Content-Type": "application/json"
  },
  "requestBody": "{\"query\":\"status\"}",
  "responseBody": "{\"error\":\"Internal Server Error\"}",
  "startTime": "2026-04-13T10:35:12Z",
  "duration": 2340,
  "size": 128
}
```

If `index` is missing or out of range, the endpoint returns:

```json
{
  "success": false,
  "error": {
    "code": "INVALID_INDEX",
    "message": "index is required and must be valid"
  }
}
```

### `networkCurrent`
Get the currently selected request in the inspector.

```json
POST /v1/network-current

Response:
{
  "success": true,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "POST",
  "url": "https://api.example.com/data",
  "statusCode": 500,
  "contentType": "application/json",
  "category": "JSON",
  "initiator": "js",
  "requestHeaders": {
    "Content-Type": "application/json"
  },
  "responseHeaders": {
    "Content-Type": "application/json"
  },
  "requestBody": "{\"query\":\"status\"}",
  "responseBody": "{\"error\":\"Internal Server Error\"}",
  "startTime": "2026-04-13T10:35:12Z",
  "duration": 2340,
  "size": 128
}
```

If nothing is selected, the endpoint returns:

```json
{
  "success": false,
  "error": {
    "code": "NONE_SELECTED",
    "message": "No request currently selected"
  }
}
```

### `networkClear`
Clear the captured network inspector log.

```json
POST /v1/network-clear

Response:
{
  "success": true,
  "cleared": true
}
```

### `networkSelect`
Select a request for inspection.

The current implementation accepts either `index` or `urlPattern`. If both are omitted, the endpoint returns `MISSING_PARAM`.

```json
POST /v1/network-select
{
  "index": 1
}

Response:
{
  "success": true,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "POST",
  "url": "https://api.example.com/data",
  "statusCode": 500,
  "contentType": "application/json",
  "category": "JSON",
  "initiator": "js",
  "requestHeaders": {
    "Content-Type": "application/json"
  },
  "responseHeaders": {
    "Content-Type": "application/json"
  },
  "requestBody": "{\"query\":\"status\"}",
  "responseBody": "{\"error\":\"Internal Server Error\"}",
  "startTime": "2026-04-13T10:35:12Z",
  "duration": 2340,
  "size": 128
}
```

You can also select by URL substring:

```json
POST /v1/network-select
{
  "urlPattern": "/data"
}
```

### `getResourceTimeline`
Get a chronological timeline of all page resources with load ordering — useful for understanding page load performance and identifying bottlenecks.

```json
POST /v1/get-resource-timeline

Response:
{
  "success": true,
  "pageUrl": "https://example.com/",
  "navigationStart": "2026-03-30T10:15:29.000Z",
  "domContentLoaded": 450,
  "domComplete": 1200,
  "loadEvent": 1350,
  "resources": [
    {"url": "https://example.com/", "type": "document", "start": 0, "end": 299, "status": 200},
    {"url": "https://example.com/styles.css", "type": "stylesheet", "start": 310, "end": 399, "status": 200},
    {"url": "https://example.com/app.js", "type": "script", "start": 300, "end": 445, "status": 200},
    {"url": "https://fonts.googleapis.com/css2", "type": "stylesheet", "start": 400, "end": 520, "status": 200},
    {"url": "https://example.com/logo.svg", "type": "image", "start": 450, "end": 480, "status": 200},
    {"url": "https://api.example.com/data", "type": "fetch", "start": 500, "end": 2840, "status": 500}
  ]
}
```

### `getWebSockets`
List the active WebSocket connections visible to the current page. The bridge wraps the page `WebSocket` constructor at document start and tracks each live connection's current state and message counters.

```json
POST /v1/get-websockets

Response:
{
  "success": true,
  "connections": [
    {
      "url": "wss://example.com/socket",
      "readyState": 1,
      "protocol": "graphql-transport-ws",
      "messagesSent": 12,
      "messagesReceived": 18,
      "createdAt": "2026-04-13T09:15:02.111Z"
    }
  ],
  "count": 1
}
```

### `getWebSocketMessages`
Get recent WebSocket messages captured for active connections. Messages are normalized to bounded string previews and include direction and timestamp. Use `connectionIndex` to scope the response to one connection from `getWebSockets`.

```json
POST /v1/get-websocket-messages
{
  "connectionIndex": null,
  "limit": 100
}

Response:
{
  "success": true,
  "messages": [
    {
      "connectionIndex": 0,
      "direction": "sent",
      "data": "{\"type\":\"ping\"}",
      "timestamp": "2026-04-13T09:15:05.444Z"
    },
    {
      "connectionIndex": 0,
      "direction": "received",
      "data": "{\"type\":\"pong\"}",
      "timestamp": "2026-04-13T09:15:05.890Z"
    }
  ],
  "count": 2
}
```

### `clearConsole`
Clear the captured console messages buffer.

```json
POST /v1/clear-console

Response:
{
  "success": true,
  "cleared": 47
}
```

### `snapshot-3d-enter`
Enter 3D DOM inspection mode. Explodes the page into a layered depth view. Requires the 3D inspector feature flag to be enabled (Settings toggle or `KELPIE_3D_INSPECTOR=1` environment variable).

- Method: POST
- Body: none
- Response: `{success: true}` or error (`FEATURE_DISABLED`, `ALREADY_ACTIVE`, `ACTIVATION_FAILED`)

### `snapshot-3d-exit`
Exit 3D DOM inspection mode. Restores the page to its original state.

- Method: POST
- Body: none
- Response: `{success: true}` (idempotent)

### `snapshot-3d-status`
Check whether 3D DOM inspection mode is currently active.

- Method: GET
- Body: none
- Response: `{success: true, active: true|false}`

### `snapshot-3d-set-mode`
Switch the interaction mode of the active 3D inspector session between rotating the scene and scrolling the underlying page.

- Method: POST
- Body: `{mode: "rotate" | "scroll"}`
- Response: `{success: true, mode: "rotate" | "scroll"}` or error (`NOT_ACTIVE`, `INVALID_MODE`, `JS_ERROR`)

### `snapshot-3d-zoom`
Zoom the 3D inspector camera. Provide either a signed `delta` (positive zooms in, negative zooms out) or a `direction` shortcut.

- Method: POST
- Body: `{delta?: number}` or `{direction?: "in" | "out"}`
- Response: `{success: true, delta: number}` or error (`NOT_ACTIVE`, `INVALID_DIRECTION`, `MISSING_PARAM`, `JS_ERROR`)

### `snapshot-3d-reset-view`
Reset the 3D inspector camera rotation and scale to defaults.

- Method: POST
- Body: none
- Response: `{success: true}` or error (`NOT_ACTIVE`, `JS_ERROR`)

## Mutation Observation

### `watchMutations`
Start observing DOM mutations. Instead of polling with repeated screenshots, subscribe to changes and get notified when the page updates (SPA navigations, dynamic content, modals appearing).

```json
POST /v1/watch-mutations
{
  "selector": "body",          // optional, scope observation
  "attributes": true,          // watch attribute changes
  "childList": true,           // watch added/removed elements
  "subtree": true,             // watch entire subtree
  "characterData": false       // watch text content changes
}

Response:
{
  "success": true,
  "watchId": "mut_001",
  "watching": true
}
```

### `getMutations`
Get accumulated mutations since last check or since watch started.

```json
POST /v1/get-mutations
{
  "watchId": "mut_001",
  "clear": true                // optional, clear buffer after reading
}

Response:
{
  "success": true,
  "mutations": [
    {
      "type": "childList",
      "target": "div.results",
      "added": [{"tag": "div", "class": "result-item", "text": "New result"}],
      "removed": [],
      "timestamp": "2026-03-30T10:16:45.123Z"
    },
    {
      "type": "attributes",
      "target": "button#submit",
      "attribute": "disabled",
      "oldValue": "",
      "newValue": null,
      "timestamp": "2026-03-30T10:16:45.200Z"
    }
  ],
  "count": 2,
  "hasMore": false
}
```

### `stopWatching`
Stop a mutation observer.

```json
POST /v1/stop-watching
{
  "watchId": "mut_001"
}

Response:
{
  "success": true,
  "totalMutations": 47
}
```

---

## Shadow DOM

### `queryShadowDOM`
Query elements inside shadow DOM boundaries. Standard CSS selectors can't pierce shadow roots — this method traverses them.

```json
POST /v1/query-shadow-dom
{
  "hostSelector": "my-component",      // selector for the shadow host element
  "shadowSelector": ".inner-button",   // selector within the shadow root
  "pierce": true                        // optional, recursively pierce nested shadow DOMs
}

Response:
{
  "success": true,
  "found": true,
  "element": {
    "tag": "button",
    "text": "Click Me",
    "shadowHost": "my-component",
    "rect": {"x": 50, "y": 200, "width": 120, "height": 40},
    "visible": true,
    "interactable": true
  }
}
```

### `getShadowRoots`
List all elements on the page that have shadow DOM attached.

```json
POST /v1/get-shadow-roots

Response:
{
  "success": true,
  "hosts": [
    {"selector": "my-header", "tag": "my-header", "mode": "open", "childCount": 5},
    {"selector": "my-component", "tag": "my-component", "mode": "open", "childCount": 12},
    {"selector": "third-party-widget", "tag": "third-party-widget", "mode": "closed", "childCount": null}
  ],
  "count": 3
}
```

Note: Closed shadow roots cannot be traversed — `childCount` is `null` for closed mode.

---

## Request Interception

> **Not implemented on any platform.** `set-request-interception`, `get-intercepted-requests`, and `clear-request-interception` return `PLATFORM_NOT_SUPPORTED` on iOS, Android, and macOS. These tools are marked unsupported for every platform in the shared MCP catalog (`BrowserToolUnsupportedPlatforms`) and their MCP tools declare an empty supported-platforms list. The request/response shapes below describe the intended contract for when interception lands; do not rely on them today.

### `setRequestInterception`
Configure rules to block, modify, or mock outgoing network requests. Useful for blocking ads, mocking APIs, or testing error scenarios.

```json
POST /v1/set-request-interception
{
  "rules": [
    {
      "pattern": "*.doubleclick.net/*",
      "action": "block"
    },
    {
      "pattern": "https://api.example.com/data",
      "action": "mock",
      "mockResponse": {
        "status": 200,
        "headers": {"Content-Type": "application/json"},
        "body": "{\"items\": [{\"id\": 1, \"name\": \"Mocked Item\"}]}"
      }
    },
    {
      "pattern": "*.js",
      "action": "allow"         // explicit allow (default)
    }
  ]
}

Response:
{
  "success": true,
  "activeRules": 2
}
```

### `getInterceptedRequests`
Get requests that matched interception rules.

```json
POST /v1/get-intercepted-requests
{
  "since": null,
  "limit": 50
}

Response:
{
  "success": true,
  "requests": [
    {
      "url": "https://ad.doubleclick.net/track",
      "method": "GET",
      "action": "blocked",
      "rule": "*.doubleclick.net/*",
      "timestamp": "2026-03-30T10:15:30.500Z"
    },
    {
      "url": "https://api.example.com/data",
      "method": "GET",
      "action": "mocked",
      "rule": "https://api.example.com/data",
      "timestamp": "2026-03-30T10:15:31.200Z"
    }
  ],
  "count": 2
}
```

### `clearRequestInterception`
Remove all interception rules.

```json
POST /v1/clear-request-interception

Response:
{
  "success": true,
  "cleared": 2
}
```
