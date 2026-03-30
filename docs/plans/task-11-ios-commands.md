# Task 11: iOS App — Command Handlers + MCP Server

**Component:** iOS
**Depends on:** Task 10
**Estimated size:** ~1000 lines (split across many handler files)

## Goal

Implement all HTTP API endpoint handlers for the iOS app, including bridge scripts for iOS-specific features, and the MCP server.

## Files to Create

```
apps/ios/Mollotov/
  Handlers/
    NavigationHandler.swift        # navigate, back, forward, reload, getCurrentUrl
    ScreenshotHandler.swift        # screenshot (viewport + full-page stitch)
    DOMHandler.swift               # getDOM, querySelector, querySelectorAll, getElementText, getAttributes
    InteractionHandler.swift       # click, tap, fill, type, selectOption, check, uncheck
    ScrollHandler.swift            # scroll, scroll2, scrollToTop, scrollToBottom
    DeviceHandler.swift            # getViewport, getDeviceInfo, getCapabilities
    WaitHandler.swift              # waitForElement, waitForNavigation
    EvaluateHandler.swift          # evaluate
    DialogHandler.swift            # getDialog, handleDialog, setDialogAutoHandler
    TabHandler.swift               # getTabs, newTab, switchTab, closeTab
    IframeHandler.swift            # getIframes, switchToIframe, switchToMain, getIframeContext
    CookieHandler.swift            # getCookies, setCookie, deleteCookies
    StorageHandler.swift           # getStorage, setStorage, clearStorage
    ClipboardHandler.swift         # getClipboard, setClipboard
    KeyboardHandler.swift          # showKeyboard, hideKeyboard, getKeyboardState
    ViewportHandler.swift          # resizeViewport, resetViewport, isElementObscured

  LLM/
    AccessibilityHandler.swift     # getAccessibilityTree
    AnnotationHandler.swift        # screenshotAnnotated, clickAnnotation, fillAnnotation
    VisibleHandler.swift           # getVisibleElements
    PageTextHandler.swift          # getPageText
    FormStateHandler.swift         # getFormState
    FindHandler.swift              # findElement, findButton, findLink, findInput

  DevTools/
    ConsoleHandler.swift           # getConsoleMessages, getJSErrors, clearConsole
    NetworkHandler.swift           # getNetworkLog, getResourceTimeline
    MutationHandler.swift          # watchMutations, getMutations, stopWatching

  Bridge/
    BridgeScripts.swift            # All ephemeral JS bridge scripts
    ConsoleCapture.js              # console.log/warn/error override
    MutationObserver.js            # MutationObserver injection
    AccessibilityTree.js           # ARIA attribute traversal
    PageTextExtractor.js           # Readability-style extraction
    FormStateCollector.js          # Form field state collection
    VisibleElements.js             # Viewport visibility check
    NetworkTracker.js              # fetch/XMLHttpRequest wrapper (partial)

  Tabs/
    TabManager.swift               # Multiple WKWebView instance management

  MCP/
    MCPServer.swift                # MCP server over HTTP transport
    MCPToolRegistry.swift          # Tool definitions matching docs/api/README.md
```

## Implementation Notes

### Native API Handlers (no bridge scripts needed)

These use `WKWebView` native APIs directly:
- **Navigation:** `webView.load()`, `webView.goBack()`, `webView.goForward()`, `webView.reload()`
- **Screenshot (viewport):** `webView.takeSnapshot(with:)`
- **DOM:** `webView.evaluateJavaScript()` for querySelector, getElementText, etc.
- **Interaction:** `evaluateJavaScript` to find element, then tap at coordinates
- **Scrolling:** `webView.scrollView.setContentOffset()` or `evaluateJavaScript`
- **Cookies:** `WKHTTPCookieStore`
- **Dialogs:** `WKUIDelegate` methods

### Bridge Script Handlers (ephemeral JS injection)

From docs/architecture.md — features WKWebView doesn't expose natively:
- **Console capture:** Override `console.log/warn/error` to forward to native via `WKScriptMessageHandler`
- **Mutation observation:** Inject `MutationObserver`, results sent via message handler
- **Accessibility tree:** DOM traversal querying ARIA attributes
- **Page text:** Readability-style algorithm
- **Network logging:** Limited — only `WKNavigationDelegate` for top-level nav + optional fetch/XHR wrapper
- **Visible elements:** IntersectionObserver or bounding rect check

Bridge scripts are injected via `WKUserScript` or `evaluateJavaScript`, cleared on navigation.

### Platform-Unsupported Endpoints

These return `PLATFORM_NOT_SUPPORTED` on iOS:
- `setRequestInterception` / `getInterceptedRequests` / `clearRequestInterception`
- `setGeolocation` / `clearGeolocation`

### Tab Management

`TabManager` maintains an array of `WKWebView` instances. Operations:
- `newTab()` — create new WKWebView, optionally navigate
- `switchTab(id)` — swap active WebView in the UI
- `closeTab(id)` — destroy WebView, update array
- `getTabs()` — return metadata for all tabs

### MCP Server

Reuses the same HTTP server (different path: `/mcp`). Implements MCP protocol over Streamable HTTP. Registers all tools with `mollotov_` prefix matching docs/api/README.md tool name table.

## Tests (via AppReveal)

In debug builds, AppReveal gives external agents access to:
- Take screenshots of the Mollotov app itself (not just the WebView)
- Inspect UI elements (URL bar, settings panel, WebView state)
- Verify navigation state after commands

Test scenarios to verify manually or via AppReveal:
1. Navigate to a URL → AppReveal `get_screen` confirms browser screen, `screenshot` shows page
2. Click a button → AppReveal verifies DOM change
3. Screenshot → verify base64 response is valid PNG
4. Tabs: create, switch, close → AppReveal verifies tab count
5. Dialog: trigger alert → handle it → verify dismissed

## Acceptance Criteria

- [ ] All navigation endpoints work: navigate, back, forward, reload, getCurrentUrl
- [ ] `screenshot` returns valid base64 PNG for viewport
- [ ] `screenshot` with `fullPage: true` returns stitched full-page image
- [ ] DOM queries work: getDOM, querySelector, querySelectorAll return correct data
- [ ] `click` finds element and taps at its coordinates
- [ ] `fill` clears existing text and enters new value
- [ ] `scroll2` scrolls until target element is visible
- [ ] `getDeviceInfo` returns all documented fields (nulls for unavailable)
- [ ] `getCapabilities` correctly lists supported/partial/unsupported methods
- [ ] Console capture bridge script works — `getConsoleMessages` returns messages
- [ ] `getAccessibilityTree` returns semantic tree via bridge script
- [ ] `screenshotAnnotated` overlays numbered labels on interactive elements
- [ ] `clickAnnotation` and `fillAnnotation` work with annotation indices
- [ ] Tab management: create, switch, close tabs; `getTabs` returns correct list
- [ ] Dialog handling: detect, accept, dismiss, auto-handler modes
- [ ] Cookie CRUD works via `WKHTTPCookieStore`
- [ ] Storage read/write works via `evaluateJavaScript`
- [ ] `setRequestInterception` returns `PLATFORM_NOT_SUPPORTED`
- [ ] `setGeolocation` returns `PLATFORM_NOT_SUPPORTED`
- [ ] MCP server accessible at `/mcp` endpoint
- [ ] All MCP tool names match docs/api/README.md table
- [ ] AppReveal can discover and interact with the app in debug builds
- [ ] Bridge scripts are ephemeral — cleared on navigation

---

- [ ] **Have you run an adversarial review with Codex?**
