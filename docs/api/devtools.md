# Mollotov API — DevTools Methods

Console/JS errors, network log, resource timeline, mutation observation, shadow DOM, request interception.

For protocol details, errors, and MCP tool names, see [README.md](README.md).

---

## Console & DevTools

### `getConsoleMessages`
Get JavaScript console messages (errors, warnings, logs) from the current page. The browser captures these in real time via native console hooks (CDP `Runtime.consoleAPICalled` on Android, `WKScriptMessageHandler` console override on iOS).

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
Get the full network activity log — every resource the page loaded, with timing data. Uses CDP `Network.*` events on Android and `WKNavigationDelegate` + resource tracking on iOS.

```json
POST /v1/get-network-log
{
  "type": null,               // optional filter: "document" | "script" | "stylesheet" | "image" | "font" | "xhr" | "fetch" | "websocket" | "other"
  "status": null,             // optional filter: "success" | "error" | "pending"
  "since": null,              // optional, ISO timestamp
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

## Clipboard
## Clipboard

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
## Request Interception

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

