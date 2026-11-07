# Core Parity Gap: macOS → C++ Native

**Date:** 2026-04-06
**Status:** Draft — **Extended with adversarial review findings from 9 simultaneous agents**

> **Summary of 9-agent review:** 107 total issues found across all components. 8 critical security/correctness bugs. The document's core direction (move logic to core) is correct but several items are understated or missing. The C++ implementations are significantly less complete than the document implies.

This document catalogues everything in the macOS Swift app that should live in the core C++ project (`core/native/`), either because it is already implemented in `core/native/` and the macOS app isn't using it, or because it is platform-agnostic and belongs in `core/native/` even if it isn't there yet.

---

## 1. Already in `core/native/`, Not Yet Wired in macOS Swift

The `engine-chromium-desktop` C++ module has complete handler implementations for most automation methods. The macOS Swift handlers below implement the same methods but with inferior or incomplete JS — the C++ versions should be the source of truth and the macOS app should call into them via the C API.

### 1.1 Interaction — `engine-chromium-desktop/src/handlers/interaction_handler.cpp`

**C++ status:** Complete (click, tap, fill, type, select-option, check, uncheck)
**macOS status:** `core/apple/macos/Handlers/InteractionHandler.swift` — same methods, different JS

**Gap:** The C++ implementation has all 7 methods. The macOS Swift version has the same 7. The macOS app is not calling into the C++ core. This means the macOS app is maintaining duplicate logic.

**Action:** Wire `InteractionHandler.swift` to call `kelpie_interaction_*` C API functions instead of executing JS directly. The JS that implements the interaction logic (native setters for `fill`, keyboard events for `type`, etc.) lives in the C++ source and can be extracted to a shared string constant in `core-automation`.

### 1.2 Scroll — `engine-chromium-desktop/src/handlers/scroll_handler.cpp`

**C++ status:** `scroll`, `scroll-to-top`, `scroll-to-bottom` implemented. `scroll2` and `scroll-to-y` return `UNSUPPORTED`.
**macOS status:** `core/apple/macos/Handlers/ScrollHandler.swift` — `scroll`, `scroll2`, `scroll-to-top`, `scroll-to-bottom`, `scroll-to-y` all implemented with full JS

**Gap:** The macOS app has `scroll2` (scroll element into view with position) and `scroll-to-y` (absolute Y scroll) which are absent from C++. The C++ version has only basic scroll methods.

**Action:** Port `scroll2` and `scroll-to-y` JS from Swift to C++. Then wire macOS to the C++ implementation.

### 1.3 Evaluate — `engine-chromium-desktop/src/handlers/evaluate_handler.cpp`

**C++ status:** `evaluate` and `wait-for-element` implemented.
**macOS status:** `core/apple/macos/Handlers/EvaluateHandler.swift` — same methods.

**Action:** Wire macOS `EvaluateHandler.swift` to C++. The `wait-for-element` polling loop pattern is reusable.

### 1.4 DOM — `engine-chromium-desktop/src/handlers/dom_handler.cpp`

**C++ status:** `query-selector`, `query-selector-all`, `get-element-text`, `get-attributes`, `get-dom` all implemented.
**macOS status:** `core/apple/macos/Handlers/DOMHandler.swift` — same methods.

**Action:** macOS Swift should call into C++ for DOM operations. The JS (querying `getBoundingClientRect`, `innerText`, attributes, etc.) is already in C++ and should not be duplicated in Swift.

### 1.5 Network (Performance API) — `engine-chromium-desktop/src/handlers/network_handler.cpp`

**C++ status:** `get-network-log` and `get-resource-timeline` implemented. Uses `performance.getEntriesByType('resource')` and `performance.getEntriesByType('navigation')`.
**macOS status:** `core/apple/macos/Handlers/NetworkHandler.swift` — same methods. The JS for `buildSummary()` is in Swift.

**Gap:** `buildSummary()` Swift logic (categorizing by content-type, filtering by method/status/url) is not in C++.

**Action:** Move `buildSummary()` logic to `core-automation`. macOS calls C++ for all network log operations.

### 1.6 Navigation — `engine-chromium-desktop/src/handlers/navigation_handler.cpp`

**C++ status:** `navigate`, `back`, `forward`, `reload`, `get-current-url`, `set-home`, `get-home` all implemented. Cookie migration on navigate is in C++.
**macOS status:** `core/apple/macos/Handlers/NavigationHandler.swift` — same methods plus `context.persistRendererCookiesToSharedJar()`.

**Gap:** Cookie migration (`persistRendererCookiesToSharedJar`) is in Swift. Should be in `core-automation`.

**Action:** Move cookie migration logic to `core-automation`. Wire macOS navigation to C++.

### 1.7 Console — `engine-chromium-desktop/src/handlers/console_handler.cpp`

**C++ status:** `get-console-messages`, `get-js-errors`, `clear-console` implemented. Uses the injected bridge script.
**macOS status:** `core/apple/macos/Handlers/ConsoleHandler.swift` — same methods. Bridge script (`bridgeScript`) is a static Swift string.

**Gap:** The console bridge JS intercepts `console.*` and `window.onerror`. The JS itself is portable. The injection mechanism (via `WKUserScript` or CDP `Page.addScriptToEvaluateOnNewDocument`) is platform-specific. The JS string constant should be in `core-automation`.

**Action:** Extract `bridgeScript` JS string to `core-automation/include/kelpie/bridge_scripts.h`. Platform code injects via its own mechanism.

### 1.8 Screenshot — `engine-chromium-desktop/src/handlers/screenshot_handler.cpp`

**C++ status:** `screenshot` implemented (PNG/JPEG via CDP `Page.captureScreenshot`).
**macOS status:** `core/apple/macos/Handlers/ScreenshotHandler.swift` — same method using `context.takeSnapshot()` and `NSBitmapImageRep`.

**Action:** Keep platform-specific capture (CEF uses CDP, WebKit uses `takeSnapshot()`). The response format (width/height/format/base64) is already consistent.

---

## 2. Not in `core/native/`, Should Be Added

These are macOS Swift components that are platform-agnostic and should be implemented in `core/native/`.

### 2.1 MutationHandler — `core/apple/macos/Handlers/MutationHandler.swift`

**What it does:** Injects a `MutationObserver` bridge script that buffers DOM mutations (childList, attributes, characterData) in `window.__kelpieMutations`. Provides `watch-mutations`, `get-mutations`, `stop-watching`.

**Why it belongs in core:** Uses the standard `MutationObserver` Web API — identical on all browser engines. The in-page JS (buffering, serialization, `observe()` configuration) is 100% portable. Only the injection mechanism differs (WKUserScript vs CDP `Page.addScriptToEvaluateOnNewDocument`).

**What to move:** The JS string constant (lines 24–67 of `MutationHandler.swift`) to `core-automation/include/kelpie/bridge_scripts.h`. The handler state management (`window.__kelpieMutations` watch tracking) stays in Swift or moves to `core-automation` as a C++ class.

### 2.2 ShadowDOMHandler — `core/apple/macos/Handlers/ShadowDOMHandler.swift`

**What it does:** Queries shadow DOM using `shadowRoot.querySelector()` recursively. Provides `query-shadow-dom`, `get-shadow-roots`.

**Why it belongs in core:** Pure JS evaluation using standard `shadowRoot` API. Identical on all engines.

**Action:** Implement in `core-automation`. JS is reusable as-is.

### 2.3 Snapshot3DBridge — `core/apple/shared/Handlers/Snapshot3DBridge.swift`

**What it does:** Full-page 3D CSS transform for element inspection. ~700 lines of JS that:
1. Reads all DOM elements, computes depth via ancestor traversal
2. Applies `translateZ(n * 30px)` per element with `transformStyle: preserve-3d`
3. Creates an overlay for mouse/touch/wheel input
4. Handles hover highlighting, info panel, mode switching (rotate/scroll), pinch-zoom

**Why it belongs in core:** Pure JS/CSS. Zero platform-specific calls except `exitViaMessage()` which has a fallback chain:
```javascript
window.webkit.messageHandlers.kelpie3DSnapshot.postMessage(...)  // WebKit
window.KelpieBridge.on3DSnapshotEvent(...)                       // generic fallback
console.log('__kelpie_3d_exit__')                                // last-resort fallback
```

**What to move:** The entire JS (lines 4–800 of `Snapshot3DBridge.swift`) to `core-automation/include/kelpie/bridge_scripts.h`. Platform code provides the bridge function via its own mechanism. The JS itself is reusable on iOS/Android/WebKit/Chromium.

**Note:** `Snapshot3DBridge.swift` also contains `Snapshot3DHandler.swift` (the handler that calls the bridge). The handler has a feature flag check (`FeatureFlags.is3DInspectorEnabled`) and state (`context.isIn3DInspector`).

### 2.4 NetworkBridge — Injected JS in `core/apple/macos/Handlers/NetworkBridge.swift`

**What it does:** Intercepts `XMLHttpRequest.prototype.open/send/setRequestHeader` and `window.fetch` to capture network requests and post them via `window.webkit.messageHandlers.kelpieNetwork.postMessage`.

**Why it belongs in core:** The XHR/fetch interception JS is portable. Only the `postMessage` call differs.

**What to move:** The XHR/fetch interception JS to `core-automation`. The bridge call (`postMessage`) should use the generic fallback chain like Snapshot3DBridge.

### 2.5 ViewportState — `core/apple/macos/Browser/ViewportState.swift`

**What it does:** Manages viewport dimensions, orientation, and viewport presets. `allMacViewportPresets` is macOS-specific (iPhone SE, iPad Mini, etc.). `ViewportState` itself has platform-agnostic fields: `width`, `height`, `devicePixelRatio`, `orientation`, `mode`.

**Why it belongs in core:** Viewport management is a core automation concern. The preset list differs by platform but the `ViewportState` struct and orientation logic belong in `core-automation`.

**What to move:** `ViewportState` struct and orientation enum to `core-automation/include/kelpie/viewport_state.h`. Platform-specific preset lists stay in platform code.

### 2.6 FeatureFlags — `core/apple/macos/Browser/FeatureFlags.swift`

**What it does:** Static boolean dictionary for feature toggles. Currently: `is3DInspectorEnabled`.

**Why it belongs in core:** Feature flags are a core concept. The storage/retrieval mechanism is platform-specific but the concept and flag names belong in core.

**What to move:** Flag name constants (`KELPIE_FF_3D_INSPECTOR`) and the `FeatureFlags` struct to `core-protocol/include/kelpie/feature_flags.h`.

### 2.7 FaviconExtractor — `core/apple/macos/Browser/FaviconExtractor.swift`

**What it does:** Extracts favicons from web pages by:
1. Parsing `<link rel="icon">` tags
2. Fetching `/favicon.ico`
3. Generating letter avatars as fallback

**Why it belongs in core:** Favicon extraction logic is platform-agnostic. The implementation (parsing link tags, building ICO URLs) is the same on all platforms.

**What to move:** The extraction logic (parsing HTML for link tags, URL building) to `core-automation`. The actual HTTP fetch uses platform stack (URLSession/WKWebView). Letter avatar generation (using platform graphics) stays in platform code.

**Note:** SVG favicon decoding via temp file (`ad6d5d6` — "decode SVG favicons via temp file") is macOS-specific and should remain in platform code.

### 2.8 TabStore — `core/apple/macos/Browser/TabStore.swift`

**What it does:** Multi-tab management. Per-tab `WKWebViewRenderer` instances with title/URL/isLoading/favicon tracking. Tab switching, adding, closing with tab spread animation coordination.

**Why it belongs in core:** Tab management is a core browser concept. The data model (`Tab`: id, title, url, isLoading, favicon) is identical across platforms.

**What to move:**
- `Tab` data model (without renderer reference) to `core-protocol/include/kelpie/types.h`
- `TabStore` logic (add/close/switch) to `core-automation`
- Platform code (macOS/iOS/Android) provides the platform-specific renderer per tab

**Note:** `WKWebViewRenderer` is WebKit-specific. `TabStore` should hold an opaque `RendererInterface*` (already defined in C++ as `kelpie::RendererInterface`). The Swift `Tab` holds a `WKWebViewRenderer` directly — this needs a Swift-level abstraction that wraps the C++ renderer interface.

### 2.9 BrowserState — `core/apple/macos/Browser/BrowserState.swift`

**What it does:** Aggregates `tabStore`, `viewportState`, `featureFlags`, and bridge scripts (`consoleBridgeScript`, `networkBridgeScript`). Tracks `isIn3DInspector`, `consoleMessages`, `lastError`.

**Why it belongs in core:** `BrowserState` is the top-level automation state. It should be in `core-automation`. Platform code provides the renderer and network layer.

**What to move:** `BrowserState` struct and the bridge script references to `core-automation`. Platform code owns the actual injection mechanism.

### 2.10 SharedCookieJar — `core/apple/macos/Browser/SharedCookieJar.swift`

**What it does:** Migrates cookies between WebKit (`WKHTTPCookieStore`) and CEF (`CefCookieManager`). Reads/writes cookies from a persistent JSON file (`~/Library/Cookies/kelpie_shared_cookies.json`).

**Why it belongs in core:** Cookie migration between renderers is a core concern. The JSON persistence format and cookie reading/writing logic is portable.

**What to move:** The cookie migration logic (read from one store, write to another) to `core-automation`. Platform-specific cookie APIs (WKHTTPCookieStore vs CefCookieManager) stay in platform code and implement a `CookieStore` interface defined in core.

### 2.11 AIHandler — `core/apple/macos/Handlers/AIHandler.swift`

**What it does:** `ai-status`, `ai-load`, `ai-unload`, `ai-infer`, `ai-record`. Uses `InferenceEngine` (CoreML/MLX) and `AudioRecorder` (AVFoundation) for native inference. Uses Ollama HTTP for remote inference.

**What belongs in core:**
- Ollama HTTP client protocol (`postJSON`, `ollamaURL`, `isOllamaReachable`) — already in `core/native/core-ai/src/ollama_client.cpp` but the handler-level orchestration is in Swift
- `InferenceHarness` and `InferenceEngine.InferenceResult` types — portable

**What stays platform-specific:**
- `InferenceEngine` (CoreML/MLX on macOS, Apple Foundation Models on iOS)
- `AudioRecorder` (AVFoundation microphone access)
- `NSBitmapImageRep` screenshot encoding for vision context

**Action:** The `ai-infer` Ollama code path (detached from native inference) should use `core-ai`. The `ai-status` response format should be defined in `core-protocol`.

---

## 3. Platform-Specific — Do Not Move to Core

These files use AppKit, WKWebView, or other macOS-only APIs and belong in the macOS app:

| File | Reason |
|------|--------|
| `AI/AIManager.swift` | AppKit UI integration |
| `AI/AudioRecorder.swift` | AVFoundation microphone |
| `AI/InferenceEngine.swift` | CoreML/MLX |
| `AI/InferenceHarness.swift` | CoreML/MLX harness |
| `AI/PageSummary.swift` | AI logic, partially portable |
| `AI/SystemPrompt.swift` | Portable text, can extract |
| `Device/DeviceInfo.swift` | NSScreen, platform info |
| `Network/HTTPServer.swift` | `NWListener` (macOS Network.framework) |
| `Network/MDNSAdvertiser.swift` | `NWListener` bonjour service |
| `Network/Router.swift` | Swift router, but C++ has `desktop_router.cpp` |
| `Network/ServerState.swift` | macOS HTTP server state |
| `Renderer/WKWebViewRenderer.swift` | WKWebView-specific |
| `Renderer/CEFRenderer.swift` | CEF-specific |
| `Renderer/RendererEngine.swift` | Dual-engine macOS logic |
| `Renderer/RendererState.swift` | Renderer selection state |
| `Renderer/CookieMigrator.swift` | WKHTTPCookieStore + CEF |
| `Handlers/AIHandler.swift` | Mixed: Ollama portable, native inference not |
| `Handlers/RendererHandler.swift` | macOS dual-renderer switching |
| `Handlers/DeviceHandler.swift` | NSScreen viewport info |
| `Handlers/BrowserManagementHandler.swift` | macOS-specific clipboard, viewport, tabs |
| `SafariAuthHelper.swift` | Safari auth API |
| `LLM/LLMHandler.swift` | LLM-specific |
| All `Views/*.swift` | SwiftUI/AppKit UI |
| `KelpieApp.swift` | App lifecycle |

---

## 4. Implementation Priority

### Phase 1 — Bridge Scripts to Core (High Value, Low Risk)
Extract all injected JS strings to `core-automation/include/kelpie/bridge_scripts.h`:
1. `Snapshot3DBridge` (~700 lines JS)
2. `MutationHandler` JS (MutationObserver injection)
3. `NetworkBridge` JS (XHR/fetch intercept)
4. `ConsoleHandler` bridge script

These are pure string constants. Moving them to core costs nothing and makes them available to all platforms immediately.

### Phase 2 — Store Parity (Medium Value)
1. `ViewportState` struct → `core-automation`
2. `FeatureFlags` constants → `core-protocol`
3. `FaviconExtractor` logic → `core-automation`
4. `SharedCookieJar` migration logic → `core-automation` with platform `CookieStore` interface
5. `BrowserState` → `core-automation`

### Phase 3 — Handler Wire-Through (Medium Value, Larger Change)
For each handler that exists in both Swift and C++: replace Swift JS execution with C API calls. This makes the macOS app a consumer of the core rather than a parallel implementation.

Priority order:
1. `EvaluateHandler` (simple)
2. `DOMHandler` (simple)
3. `ScrollHandler` (needs `scroll2` + `scroll-to-y` ported to C++ first)
4. `InteractionHandler` (large, 7 methods)
5. `NavigationHandler` (cookie migration needs to move to core first)
6. `NetworkHandler` (`buildSummary()` logic needs to move to core first)
7. `ConsoleHandler` (JS is in core, handler logic wires to JS in core)

### Phase 4 — TabStore to Core (High Value, Significant Refactor)
Move `Tab` data model and `TabStore` logic to `core-automation`. Requires defining a `TabInterface` that platforms implement (returns opaque `RendererInterface*`). macOS `Tab` wraps C++ tab + Swift `WKWebViewRenderer`. iOS and Android implement their own tab wrappers.

### Phase 5 — AI Orchestration (Lower Priority)
Define `ai-*` response schemas in `core-protocol`. Move Ollama HTTP protocol handling to `core-ai`. Keep native inference in platform code.

---

## 5. Cross-Platform Consistency Requirements

Per AGENTS.md § Platform Parity, every feature on one platform must be on all platforms. Before any item in this document is implemented on macOS, the equivalent must be planned for iOS and Android. This applies to:

- All bridge scripts moved to core (must work identically on iOS WebKit, Android WebView, macOS WebKit, CEF)
- TabStore model moved to core (iOS and Android must use the same tab data model)
- Feature flags defined in core (must be set on all platforms, not just macOS)
- Favicon extraction logic in core (iOS and Android must implement the same algorithm)

When implementing any Phase 1–4 item, update `docs/functionality.md` and the relevant API docs in `docs/api/` to reflect the new cross-platform behavior.

---

## 6. Adversarial Review Findings (9 Simultaneous Agents)

**Total issues found: 107. Critical (confidence 88+): 21. Important (confidence 80-87): 35.**

> Cross-platform parity agent ran out of tokens before completing — additional parity gaps likely exist.

### CRITICAL Issues (must fix before any phase ships)

---

#### C1 — HTTP Server: Missing Content-Length enables request smuggling/desync

**Source:** Critical Edge Cases agent
**File:** `core/apple/macos/Network/HTTPServer.swift`, lines 89–124

`parseContentLength` returns `0` when the header is absent or malformed. A POST request with no `Content-Length` is immediately dispatched with a truncated body. Leftover bytes become the start of the next pipelined request — textbook HTTP desync. Connection has no read timeout.

```
if bodyReceived >= contentLength {   // contentLength = 0 when absent
    Task { await self.processRequest(connection: connection, data: accumulated) }
}
```

---

#### C2 — HTTP Server + NavigationHandler: No URL scheme validation — javascript: and data: URIs reach the renderer

**Source:** Critical Edge Cases agent
**Files:** `core/apple/macos/Network/HTTPServer.swift:136`, `core/apple/macos/Handlers/NavigationHandler.swift:18`

Path passed to router without scheme filtering. navigate checks URL(string:) only — javascript:alert(document.cookie) parses fine. WKWebView executes it. Any CLI user on the LAN can XSS the browser origin via the HTTP API.

---

#### C3 — HTTPServer: @unchecked Sendable on class with multiple mutable shared fields

**Source:** Critical Edge Cases + Architecture agents
**File:** `core/apple/macos/Network/HTTPServer.swift`, line 6

```swift
final class HTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private var bonjourService: NWListener.Service?
```

Marked suppressive but has multiple mutable fields accessed from NWListener internal threads and Task closures concurrently. No lock. Future concurrent access introduces races silently.

---

#### C4 — CEFRenderer has zero bridge script injection — NetworkBridge and ConsoleBridge do not work on CEF

**Source:** Bridge Scripts agent
**File:** `core/apple/macos/Renderer/CEFRenderer.swift`

WKWebViewRenderer injects both bridge scripts via addUserScript. CEFRenderer has no equivalent mechanism — does not call addUserScript. Network interception (XMLHttpRequest/fetch) is entirely absent on CEF. The document Phase 1 plan does not address that the CEF injection pipeline does not exist.

---

#### C5 — NetworkBridge has no fallback chain — hardcodes WebKit messageHandler

**Source:** Bridge Scripts agent
**File:** `core/apple/macos/Handlers/NetworkBridge.swift`, lines 9–11

```javascript
var _post = window.webkit.messageHandlers.kelpieNetwork.postMessage.bind(
    window.webkit.messageHandlers.kelpieNetwork
);
```

No if (window.webkit...) guard. On CEF or Android WebView this throws TypeError at load time before any network event is captured. The document action item says add a fallback chain — this is already broken, not a future improvement.

---

#### C6 — MutationHandler: MutationObserver buffers and observers accumulate across every page navigation — never cleaned up

**Source:** Critical Edge Cases + Bridge Scripts agents
**File:** `core/apple/macos/Handlers/MutationHandler.swift`, lines 23–67

WKWebView reuses the same JS context for same-origin navigations. window.__kelpieMutations persists across navigations. No stopWatching call on navigation — observers accumulate indefinitely. On heavy-DOM pages (live data, infinite scroll), each observer fills to 1000 entries. 10 calls without stop-watching = up to 10000 orphaned mutation entries accumulating in memory. Also: watchId uses Date.now() — two calls within the same millisecond produce duplicate IDs, orphaning the first observer.

---

#### C7 — Snapshot3DBridge: document.write/document.open called after injection silently orphans the inspector

**Source:** Critical Edge Cases agent
**File:** `core/apple/shared/Handlers/Snapshot3DBridge.swift`

document.write during parse or document.open post-load erases the DOM including __m3d_overlay, __m3d_suppress, iframe labels, and all modified element inline styles. The JS window.__m3d survives. Overlay is gone — user sees nothing and cannot interact. On re-entry after document.open, the stale cleanup at the top of enterScript runs against the new document with nil or dead-element WeakMap references.

---

#### C8 — InteractionHandler: selector parameter escapes only single-quote — full CSS selector injection possible

**Source:** Critical Edge Cases + Handler Wire-Through agents
**File:** `core/apple/macos/Handlers/InteractionHandler.swift`, lines 24, 70, 97, 128, 152

document.querySelector('selector.replacingOccurrences(of: "'", with: "\\'")') — crafted selectors like [onfocus=alert(1)//], div[class*=secret], input[type=password], or button[class*=admin] enumerate page structure and detect specific elements. Not direct XSS (native setters bypass re-parsing) but exploitable information disclosure by any CLI user.

---

#### C9 — WKWebViewRenderer: Inverted deduplication guard — non-consecutive duplicate URLs all re-logged

**Source:** Critical Edge Cases + Platform-Specific agents
**File:** `core/apple/macos/Renderer/WKWebViewRenderer.swift`, line 220

capturedDocumentResponseURL != url else { return } then set at end. Trace A -> B -> A: Call 3 checks B != A -> true -> logs A again. Guard only prevents consecutive duplicates. In CLI automation sessions revisiting pages (form -> submit -> back to form), NetworkTrafficStore silently records duplicate entries.

---

#### C10 — SharedCookieJar: SameSite attribute silently dropped on every save/load cycle

**Source:** Store Parity agent
**File:** `core/apple/macos/Browser/SharedCookieJar.swift`

StoredCookie has no sameSite field. signature() omits SameSite from hash — cookie policy changes undetectable. Additionally: HttpOnly and Secure are set as string "TRUE" instead of Bool true. Both flags silently lost on restore.

---

#### C11 — SharedCookieJar: Cookies silently dropped when switching FROM CEF

**Source:** Platform-Specific agent
**File:** `core/apple/macos/Renderer/CookieMigrator.swift`, lines 7–16

guard source.engineName != "chromium" else { return } — when switching from CEF to WebKit, migrate returns immediately. SharedCookieJar never populated with CEF cookies. httpOnly cookies also silently skipped in injectCookiesViaJS due to CEF API limitations.

---

#### C12 — Document error: wait-for-element and wait-for-navigation do not exist in C++

**Source:** Handler Wire-Through agent
**File:** `core/native/engine-chromium-desktop/src/handlers/evaluate_handler.cpp`

The document claims both are implemented. Grep across entire core/native/ tree finds zero references. Only evaluate is implemented. Phase 3 wire-through for EvaluateHandler is built on false premise.

---

#### C13 — C++ scroll-to-bottom uses document.body.scrollHeight — fails on overflow:hidden body

**Source:** Handler Wire-Through agent
**File:** `core/native/engine-chromium-desktop/src/handlers/scroll_handler.cpp`, line 13

C++ uses document.body.scrollHeight. Swift uses document.documentElement.scrollHeight. Pages with body { overflow: hidden } (common in SPAs) report body.scrollHeight === window.innerHeight — zero scrollable distance. C++ version will not scroll to bottom of these pages.

---

#### C14 — C++ type ignores delay parameter — sends all characters synchronously

**Source:** Handler Wire-Through agent
**File:** `core/native/engine-chromium-desktop/src/handlers/interaction_handler.cpp`, lines 99–103

Swift typeText loops with Task.sleep per character. C++ uses synchronous for-loop with no sleep. Sites listening for intermediate input events (Google Search, typeaheads, form validators) receive all characters simultaneously and miss intermediate state.

---

#### C15 — C++ navigate does not wait for page load — reports zero load time

**Source:** Handler Wire-Through agent
**File:** `core/native/engine-chromium-desktop/src/handlers/navigation_handler.cpp`, lines 22–33

Swift polls isLoadingPage up to 10 seconds. C++ calls LoadUrl(url), records NowMillis() immediately, returns — loadTime always negligible. C++ navigation methods also do not call cookie persistence. Sessions not migrated on navigation.

---

#### C16 — C++ fill uses element.value= — fails on React/Vue/Angular instrumented inputs

**Source:** Handler Wire-Through agent
**File:** `core/native/engine-chromium-desktop/src/handlers/interaction_handler.cpp`, line 68

Swift uses Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, value)?.set to bypass framework setters. C++ uses element.value = directly. On React/Angular/Vue apps, this sets the DOM property but may not trigger framework state update.

---

#### C17 — Document error: BrowserState does not contain isIn3DInspector or lastError

**Source:** Store Parity agent
**File:** `core/apple/macos/Browser/BrowserState.swift`

The document claims BrowserState tracks these fields. They are not in the file. consoleMessages is present but not wired to the C++ kelpie_console_store C API. Document misstates what needs to move to core.

---

#### C18 — Snapshot3DBridge exit mechanism: fallback chain broken on CEF and Android

**Source:** Bridge Scripts agent
**File:** `core/apple/shared/Handlers/Snapshot3DBridge.swift`, lines 447–456

webkit.messageHandlers fallback is WebKit-only. KelpieBridge.on3DSnapshotEvent — no platform sets this object. console.log(__kelpie_3d_exit__) depends on console bridging being wired to HandlerContext — no guarantee this forwarding is set up in all CEF and Android code paths.

---

#### C19 — Port 8420 claimed by two independent servers — no collision detection

**Source:** Architecture agent
**Files:** `core/native/engine-chromium-desktop/include/kelpie/desktop_http_server.h:14`, `core/apple/macos/Network/ServerState.swift:38`

Both DesktopHttpServer (C++) and Swift HTTPServer default to port 8420. Currently only Swift starts. Phase 3 wire-through implies routing through C++ — if both servers run simultaneously they race for the port.

---

#### C20 — Swift HandlerContext has 30+ methods the C++ context does not have

**Source:** Architecture agent
**File:** `core/apple/macos/Handlers/HandlerContext.swift` vs `core/native/core-automation/include/kelpie/handler_context.h`

Swift has: load, goBack, goForward, reloadPage, allCookies, setCookie, deleteCookie, syncSharedCookiesIntoRenderer, showTouchIndicator, showToast, waitForViewportSize, tab lifecycle, 3D inspector management. C++ context has: SetRenderer, EvaluateJs, EvaluateJsReturningJson. Wire-through without adding these to C++ will silently drop functionality.

---

#### C21 — C++ RendererInterface missing SetCookies, DeleteCookie, DeleteAllCookies, AllCookies

**Source:** Architecture agent
**File:** `core/native/core-automation/include/kelpie/renderer_interface.h`, lines 14–25

Required by HandlerContext cookie sync methods. Without these, SharedCookieJar cannot be wired through to C++. Phase 3 navigation wire-through cannot complete without cookie infrastructure in core.

---

### IMPORTANT Issues (should fix before phase ships)

#### I1 — HistoryStore.remove(id:) bypasses C API — no single-entry removal in core (C++ header has no remove_by_id function)
#### I2 — History ISO8601 formatter too strict — non-standard dates silently become Date()
#### I3 — History 500-entry cap only in C++ — Swift can accumulate unbounded entries before load_json
#### I4 — HistoryStore remove(id:) has no actor isolation — data race on concurrent access
#### I5 — FaviconExtractor uses ~= CSS operator — misses rel="shortcut icon" and compound rel values
#### I6 — FaviconExtractor: data: URI favicons fail silently with no in-memory decode path
#### I7 — FaviconExtractor: ICO multi-resolution — first image wins regardless of target display size
#### I8 — C++ and Swift query-selector return incompatible response schemas (found/element vs found/count/elements array)
#### I9 — C++ query-selector always fetches all attributes — Swift never uses them, significant waste per call
#### I10 — Swift/C++ text extraction uses textContent vs innerText — different results for hidden elements
#### I11 — Swift typeText breaks on input containing single-quote or backslash
#### I12 — Swift fill value escaping misses backslash; select-option misses newline in value too
#### I13 — wait-for-element selector injection only escapes single-quote, not backslash — same class of bug as I11
#### I14 — wait-for-element wait-time measured from before first poll, not from element appearance
#### I15 — MutationHandler 1000-entry buffer cap undocumented — returns hasMore: false when silently dropping
#### I16 — NetworkBridge has no cap on in-flight fetch/XHR closures — aborted requests leak closures indefinitely
#### I17 — InferenceHarness JSON parsing uses brace-counting — breaks on literal braces in string values (e.g. {"answer": "f(x) = {x+1}"})
#### I18 — Swift AIHandler bypasses C API entirely for Ollama — URLSession vs httplib are completely separate HTTP paths
#### I19 — InferenceHarness not portable — uses NSBitmapImageRep and HandlerContext; document label of portable is wrong
#### I20 — No context-window check — PageSummary + preloadedContext can exceed 8192 tokens silently
#### I21 — Hardcoded 4-char/token budget heuristic wrong for URLs (7:1 ratio) and JSON — systematic under-truncation
#### I22 — Missing tab escape in escapeForJavaScript — JS injection broken on tab characters in tool arguments
#### I23 — C API silently swallows all Ollama exceptions — Swift gets empty dict with no error signal, indistinguishable from empty response
#### I24 — Model vision capability lists diverge: gemma missing from Swift, multimodal models missing from both lists
#### I25 — Snapshot3DBridge CSS blur only uses -webkit-backdrop-filter on toast/info panel — absent on Chromium (needs unprefixed form)
#### I26 — WKWebViewRenderer.hardReload() does not call reloadFromOrigin() — silently serves cached content on WebKit
#### I27 — iOS HTTPServer missing onStateChange — isServerRunning always reports true after start() regardless of bind success
#### I28 — iOS MDNSAdvertiser is byte-for-byte identical to macOS — misclassified as macOS-only in document
#### I29 — Android mDNS TXT record missing engine field — inconsistent with macOS/iOS
#### I30 — Android has 3 more snapshot-3d-* methods (set-mode, zoom, reset-view) than iOS and macOS — parity violation
#### I31 — SharedCookieJar entirely absent on iOS and Android — cookie sync is macOS-only
#### I32 — CEF injectCookiesViaJS domain normalization misses www.example.com vs example.com subdomain mismatch
#### I33 — Swift stores + C++ core-state are two independent copies with no sync contract
#### I34 — startSharedCookieSync() Timer on MainActor without deinit — undefined behavior if context replaced without stopSharedCookieSync()
#### I35 — Snapshot3DHandler FeatureFlags.is3DInspectorEnabled missing on iOS/Android — feature parity violation

---

### Issues Found by Category

| Category | Critical | Important | Total |
|----------|----------|-----------|-------|
| HTTP Server / Network | C1, C2, C3 | I27 | 4 |
| Bridge Scripts (JS) | C4, C5, C6, C7, C8, C18 | I15, I16, I25 | 11 |
| Handler Logic (Swift vs C++) | C12, C13, C14, C15, C16, C8 | I8, I9, I10, I11, I12, I13, I14 | 14 |
| Stores / State | C9, C10, C11, C17 | I1, I2, I3, I4, I5, I6, I7, I33 | 13 |
| AI | — | I17, I18, I19, I20, I21, I22, I23, I24 | 8 |
| Platform-Specific / Parity | C19, C20, C21 | I26, I27, I28, I29, I30, I31, I32, I34, I35 | 14 |
| **Total** | **21** | **35** | **56** |

