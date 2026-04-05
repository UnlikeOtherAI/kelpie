# Task 13: Android App — Command Handlers + MCP Server

**Component:** Android
**Depends on:** Task 12
**Estimated size:** ~1000 lines (split across many handler files)

## Goal

Implement all HTTP API endpoint handlers for the Android app using CDP (Chrome DevTools Protocol) as the primary mechanism, and the MCP server.

## Files to Create

```
apps/android/app/src/main/java/com/kelpie/browser/
  handlers/
    NavigationHandler.kt          # navigate, back, forward, reload, getCurrentUrl
    ScreenshotHandler.kt          # screenshot via CDP Page.captureScreenshot
    DOMHandler.kt                 # getDOM, querySelector, etc. via CDP DOM.*
    InteractionHandler.kt         # click, tap, fill, type via CDP Input.*
    ScrollHandler.kt              # scroll, scroll2, scrollToTop, scrollToBottom
    DeviceHandler.kt              # getViewport, getDeviceInfo, getCapabilities
    WaitHandler.kt                # waitForElement, waitForNavigation
    EvaluateHandler.kt            # evaluate via CDP Runtime.evaluate
    DialogHandler.kt              # getDialog, handleDialog, setDialogAutoHandler
    TabHandler.kt                 # getTabs, newTab, switchTab, closeTab
    IframeHandler.kt              # getIframes, switchToIframe, switchToMain
    CookieHandler.kt              # getCookies, setCookie, deleteCookies via CDP Network
    StorageHandler.kt             # getStorage, setStorage, clearStorage
    ClipboardHandler.kt           # getClipboard, setClipboard
    GeoHandler.kt                 # setGeolocation, clearGeolocation via CDP Emulation
    KeyboardHandler.kt            # showKeyboard, hideKeyboard, getKeyboardState
    ViewportHandler.kt            # resizeViewport, resetViewport, isElementObscured
    InterceptHandler.kt           # setRequestInterception, getIntercepted, clear via CDP Fetch

  llm/
    AccessibilityHandler.kt       # getAccessibilityTree via CDP Accessibility.*
    AnnotationHandler.kt          # screenshotAnnotated, clickAnnotation, fillAnnotation
    VisibleHandler.kt             # getVisibleElements
    PageTextHandler.kt            # getPageText
    FormStateHandler.kt           # getFormState
    FindHandler.kt                # findElement, findButton, findLink, findInput

  devtools/
    ConsoleHandler.kt             # getConsoleMessages, getJSErrors via CDP Runtime
    NetworkLogHandler.kt          # getNetworkLog, getResourceTimeline via CDP Network
    MutationHandler.kt            # watchMutations, getMutations, stopWatching via CDP DOM

  cdp/
    CDPClient.kt                  # CDP WebSocket client
    CDPSession.kt                 # Session management, command/response correlation
    CDPDomains.kt                 # Typed wrappers for CDP domains (DOM, Page, Runtime, etc.)

  tabs/
    TabManager.kt                 # Multiple WebView instance management

  mcp/
    MCPServer.kt                  # MCP server over Ktor HTTP
    MCPToolRegistry.kt            # All tool definitions
```

## Implementation Notes

### CDP Client (`cdp/CDPClient.kt`)

Android WebView exposes CDP when `setWebContentsDebuggingEnabled(true)`. Connect via local Unix socket or DevTools protocol URL.

Key CDP domains used:
- `DOM.*` — getDocument, querySelector, getOuterHTML
- `Page.*` — captureScreenshot, navigate, reload
- `Runtime.*` — evaluate, consoleAPICalled events
- `Input.*` — dispatchTouchEvent, dispatchKeyEvent
- `Network.*` — getCookies, requestWillBeSent events
- `Accessibility.*` — getFullAXTree
- `Emulation.*` — setGeolocationOverride
- `Fetch.*` — request interception

### CDP vs evaluateJavascript

CDP is preferred for DOM operations (no scripts enter the page context). `evaluateJavascript()` is the fallback for simpler queries.

### Full Platform Support

Android supports ALL documented API methods — no `PLATFORM_NOT_SUPPORTED` responses:
- Request interception via CDP `Fetch.*`
- Geolocation override via CDP `Emulation.setGeolocationOverride`
- Console via CDP `Runtime.consoleAPICalled`
- Network log via CDP `Network.*`
- Accessibility tree via CDP `Accessibility.getFullAXTree`

### Tab Management (`TabManager.kt`)

Same approach as iOS: array of WebView instances, each with its own CDP session. Operations: create, switch, close, list.

### Annotated Screenshots

1. Take screenshot via CDP `Page.captureScreenshot`
2. Get interactive elements via CDP DOM queries
3. Overlay numbered labels using Android Canvas/Bitmap drawing
4. Return annotated image + annotation metadata

### MCP Server

Runs on the same Ktor server at `/mcp` path. Streamable HTTP (SSE) transport. All tools registered with `kelpie_` prefix.

## Tests (via AppReveal)

In debug builds, AppReveal gives agents access to:
- App UI inspection (Compose view tree)
- Screenshots of the app chrome (not just WebView)
- Navigation state verification
- Network call monitoring

Test scenarios:
1. Navigate → verify URL changed via AppReveal `get_state`
2. Screenshot → verify response is valid PNG
3. CDP DOM queries → verify element data matches page content
4. Tabs: create/switch/close → verify via AppReveal
5. Request interception → verify blocked requests don't load
6. Geolocation override → verify via `navigator.geolocation` in WebView

## Acceptance Criteria

- [ ] All navigation endpoints work: navigate, back, forward, reload, getCurrentUrl
- [ ] `screenshot` returns valid base64 PNG via CDP `Page.captureScreenshot`
- [ ] `screenshot` with `fullPage: true` uses `captureBeyondViewport`
- [ ] DOM queries work via CDP: getDOM, querySelector, querySelectorAll
- [ ] `click` dispatches touch event at element coordinates via CDP Input
- [ ] `fill` clears and enters text via CDP
- [ ] `scroll2` scrolls until target element is visible
- [ ] `getDeviceInfo` returns all documented fields
- [ ] `getCapabilities` lists all methods as `supported` (no `unsupported` on Android)
- [ ] Console messages captured via CDP `Runtime.consoleAPICalled`
- [ ] Network log captured via CDP `Network.*` events
- [ ] `getAccessibilityTree` returns semantic tree via CDP `Accessibility.*`
- [ ] `screenshotAnnotated` overlays numbered labels on interactive elements
- [ ] Request interception works via CDP `Fetch.*`: block, mock, allow
- [ ] Geolocation override works via CDP `Emulation.setGeolocationOverride`
- [ ] Tab management: create, switch, close; `getTabs` returns correct list
- [ ] Dialog handling: detect, accept, dismiss, auto-handler
- [ ] Cookie CRUD via CDP `Network.getCookies` / `Network.setCookie`
- [ ] MCP server accessible at `/mcp` endpoint
- [ ] All MCP tool names match docs/api/README.md table
- [ ] AppReveal can discover and interact with the app in debug builds
- [ ] CDP connection is stable — no crashes on rapid commands

---

- [ ] **Have you run an adversarial review with Codex?**
