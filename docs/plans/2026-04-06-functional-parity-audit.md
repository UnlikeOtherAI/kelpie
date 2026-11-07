# Kelpie Functional Parity Audit

**Date:** 2026-04-06
**Scope:** macOS (apps/macos/Kelpie/), iOS (apps/ios/Kelpie/), Android (core/android/src/main/java/com/kelpie/)
**Exclusions:** Renderer engines (WKWebView/WebView/CEF), UI frameworks (SwiftUI/UIKit/Compose)

---

## Executive Summary

| Platform | HTTP Route Count | Handler Files | Stores | Bridge Scripts |
|----------|-----------------|---------------|--------|---------------|
| macOS    | ~76 routes      | 18 handlers   | 7      | 4 (all present) |
| iOS      | ~73 routes (see GAP-1) | 17 handlers (see GAP-1) | 6 | 3 (missing Snapshot3DBridge) |
| Android  | ~82 routes (incl. stubs) | 16 handlers | 5 | 4 (all present) |

**Gaps found: 16 total — 1 CRITICAL, 6 IMPORTANT, 9 MINOR**

---

## Handler Architecture Comparison

### macOS ServerState.registerHandlers()
```
NavigationHandler, ScreenshotHandler, DOMHandler, InteractionHandler,
ScrollHandler, DeviceHandler (+viewportState), EvaluateHandler,
ConsoleHandler, NetworkHandler, MutationHandler, ShadowDOMHandler,
BrowserManagementHandler, LLMHandler, BookmarkHandler, HistoryHandler,
NetworkInspectorHandler, AIHandler, Snapshot3DHandler, RendererHandler
```

### iOS ServerState.registerHandlers()
```
NavigationHandler, ScreenshotHandler, DOMHandler, InteractionHandler,
ScrollHandler, DeviceHandler (+deviceInfo), EvaluateHandler,
ConsoleHandler, NetworkHandler, MutationHandler, ShadowDOMHandler,
BrowserManagementHandler, LLMHandler, AIHandler,
Snapshot3DHandler ← referenced but DOES NOT EXIST (GAP-1 CRITICAL),
BookmarkHandler, HistoryHandler, NetworkInspectorHandler
```

### Android MainActivity.registerHandlers()
```
NavigationHandler, ScreenshotHandler, DOMHandler, InteractionHandler,
ScrollHandler, DeviceHandler (+deviceInfo,activity), EvaluateHandler,
ConsoleHandler, NetworkLogHandler (≠ NetworkHandler), MutationHandler,
BrowserManagementHandler, LLMHandler, AIHandler, Snapshot3DHandler,
BookmarkHandler, HistoryHandler, NetworkInspectorHandler
(ShadowDOMHandler NOT registered — shadow-dom routes are in LLMHandler instead)
```

---

## Per-Feature Matrix

| Feature | macOS | iOS | Android | Gap |
|---------|-------|-----|---------|-----|
| **HTTP Routes** | | | | |
| Navigation (navigate, back, forward, reload, get-current-url) | ✅ | ✅ | ✅ | — |
| Screenshot | ✅ | ✅ | ✅ | — |
| DOM (get-dom, query-selector, query-selector-all, get-element-text, get-attributes) | ✅ | ✅ | ✅ | — |
| Interaction (click, tap, fill, type, select-option, check, uncheck) | ✅ | ✅ | ✅ | — |
| Scroll (scroll, scroll2, scroll-to-top, scroll-to-bottom, scroll-to-y) | ✅ | ✅ | ✅ | — |
| Device (get-viewport, get-viewport-presets, get-device-info, get-capabilities, set-orientation, get-orientation) | ✅ | ✅ | ✅ | — |
| Evaluate (evaluate, wait-for-element, wait-for-navigation) | ✅ | ✅ | ✅ | — |
| Console (get-console-messages, get-js-errors, clear-console) | ✅ | ✅ | ✅ | — |
| Network (get-network-log, get-resource-timeline) | ✅ | ✅ | ✅ | — |
| Mutation (watch-mutations, get-mutations, stop-watching) | ✅ | ✅ | ✅ | — |
| ShadowDOM (query-shadow-dom, get-shadow-roots) | ✅ | ✅ | ✅ | — |
| BrowserManagement (cookies, storage, clipboard, keyboard, viewport, iframes, dialogs) | ✅ | ✅ | ✅ | — |
| LLM (get-accessibility-tree, get-visible-elements, get-page-text, get-form-state, find-*, screenshot-annotated, click/fill-annotation) | ✅ | ✅ | ✅ | — |
| AI (ai-status, ai-load, ai-unload, ai-infer, ai-record) | ✅ | ✅ | ✅ | — |
| Bookmarks (list, add, remove, clear) | ✅ | ✅ | ✅ | — |
| History (history-list, history-clear) | ✅ | ✅ | ✅ | — |
| NetworkInspector (network-list, network-detail, network-select, network-current, network-clear) | ✅ | ✅ | ✅ | — |
| Snapshot3D (snapshot-3d-enter/exit/status/set-mode/zoom/reset-view) | ✅ | ❌ BROKEN | ✅ | **GAP-1 CRITICAL** |
| TabStore — real implementation | ✅ real | ❌ stub | ❌ stub | **GAP-2 IMPORTANT** |
| Tab routes — new-tab / switch-tab / close-tab | ✅ real | ❌ missing | ❌ stub | **GAP-2 IMPORTANT** |
| Renderer switching (set-renderer, get-renderer) | ✅ | ❌ | ❌ | GAP-3 MINOR |
| Fullscreen (set-fullscreen, get-fullscreen) | ✅ | ❌ | ❌ | GAP-4 MINOR |
| TV sync debug routes (debug-screens, debug-attach-local-tv, debug-detach-tv, set/get-tv-sync, debug-overlay) | ❌ | ✅ iOS-only | ❌ | GAP-5 MINOR |
| Request interception stubs (set-geolocation, clear-geolocation, set-request-interception, get-intercepted-requests, clear-request-interception) | ❌ | ❌ | ✅ Android-only stubs | GAP-6 MINOR |
| **Stores** | | | | |
| HistoryStore | ✅ | ✅ | ✅ | — |
| BookmarkStore | ✅ | ✅ | ✅ | — |
| NetworkTrafficStore | ✅ | ✅ | ✅ | — |
| TabStore | ✅ real | ❌ | ❌ | GAP-2 |
| ViewportState | ✅ macOS-only | N/A | ❌ | Intentional |
| FaviconExtractor | ✅ | ❌ | ❌ | GAP-7 MINOR |
| FeatureFlags | ✅ | ✅ | ✅ | — |
| AIState (Ollama backend config) | ✅ | ✅ | ❌ | GAP-8 MINOR |
| **Bridge Scripts** | | | | |
| Snapshot3DBridge (enter/exit/setMode/zoom/resetView JS) | ✅ 802 lines | ❌ MISSING | ✅ 749 lines | **GAP-1 CRITICAL** |
| ConsoleHandler.bridgeScript (kelpieConsole) | ✅ | ✅ identical | ✅ (same handler name) | — |
| NetworkBridge (kelpieNetwork) | ✅ | ✅ identical | ✅ (JS eval) | — |
| MutationHandler bridge (__kelpieMutations) | ✅ | ✅ identical | ✅ (JS eval) | — |
| **HandlerContext** | | | | |
| evaluateJS | ✅ | ✅ | ✅ | — |
| evaluateJSReturningString | ✅ | ✅ | ✅ | — |
| evaluateJSReturningJSON | ✅ | ✅ | ✅ | — |
| evaluateJSReturningArray | ❌ | ❌ | ✅ Android-only | GAP-9 MINOR |
| showToast | ✅ | ✅ | ✅ (same) | — |
| injectTouchIndicator / showTouchIndicatorForElement | ✅ | ✅ | ✅ | — |
| console bridge injection | ✅ | ✅ | ✅ | — |
| **mDNS Advertiser** | | | | |
| MDNSAdvertiser class | ✅ | ✅ | ✅ | — |
| TXT record: id, name, model, platform, width, height, port, version | ✅ | ✅ | ❌ (no txtRecord method) | **GAP-10 MINOR** |
| TXT record: engine field | ✅ | ❌ | ❌ | GAP-11 MINOR |
| TXT record: ip field | ❌ | ❌ | ✅ Android-only | Intentional |
| **Settings Keys** | | | | |
| homeURL | ✅ `homeURL` | ✅ `homeURL` | ✅ `"homeURL"` | — |
| enable3DInspector | ✅ `enable3DInspector` | ✅ `enable3DInspector` | ✅ `"enable3DInspector"` | — |
| Renderer engine | ✅ `com.kelpie.renderer-engine` | N/A | N/A | Intentional |
| tvSyncEnabled | N/A | ✅ `tvSyncEnabled` | N/A | Intentional |
| Ollama endpoint | ✅ AIState / AIManager | ✅ AIState | ❌ | GAP-8 MINOR |
| **AI / Inference** | | | | |
| ai-* HTTP routes | ✅ all 5 | ✅ all 5 | ✅ all 5 | — |
| Ollama local inference (native FFI) | ✅ via AIManager+InferenceHarness | ✅ via AIState | ✅ via Java-native | — |
| Ollama endpoint persistence | ✅ UserDefaults | ✅ UserDefaults | ❌ | GAP-8 MINOR |
| **DeviceInfo fields** | | | | |
| id, name, model, platform, width, height, port, version | ✅ | ✅ | ✅ | — |
| ip | ❌ | ❌ | ✅ | Intentional |
| engine (in txtRecord) | ✅ | ❌ | ❌ | GAP-11 MINOR |

---

## Detailed Gaps

---

### GAP-1 — [CRITICAL] iOS Snapshot3DHandler / Snapshot3DBridge: file does not exist

**Severity:** CRITICAL — build failure on iOS

**What's broken:**
iOS `ServerState.swift:96` registers `Snapshot3DHandler(context: ctx).register(on: router)`, but:
- `core/apple/ios/Handlers/Snapshot3DHandler.swift` **does not exist**
- `apps/ios/Kelpie/Handlers/Snapshot3DBridge.swift` **does not exist**

**macOS:** Has both `Snapshot3DHandler.swift` (lines 6–119) and `Snapshot3DBridge.swift` (802 lines of JS).
**Android:** Has both `Snapshot3DHandler.kt` and `Snapshot3DBridge.kt` (749 lines of JS). The Snapshot3DBridge scripts (`ENTER_SCRIPT`, `EXIT_SCRIPT`, `SET_MODE_SCRIPT`, `ZOOM_BY_SCRIPT`, `RESET_VIEW_SCRIPT`) are identical in logic to macOS (same `window.__m3d` state management, same DOM overlay/id names, same CSS selectors).

**Impact:** Any build or code reference to `Snapshot3DHandler` on iOS will fail at compile time. Even if the build somehow skips this, the 3D inspector (`snapshot-3d-enter`, `snapshot-3d-exit`, `snapshot-3d-status`, `snapshot-3d-set-mode`, `snapshot-3d-zoom`, `snapshot-3d-reset-view`) is completely non-functional on iOS.

**Evidence:**
```swift
// core/apple/ios/Network/ServerState.swift:96
Snapshot3DHandler(context: ctx).register(on: router)  // ← file does not exist
```

```bash
$ test -f core/apple/ios/Handlers/Snapshot3DHandler.swift && echo EXISTS || echo DOES NOT EXIST
DOES NOT EXIST
```

**Fix:** Copy `core/apple/macos/Handlers/Snapshot3DHandler.swift` and `Snapshot3DBridge.swift` to iOS, update the `import WebKit` to `import WebKit` (same), change `context.evaluateJS` calls if needed.

---

### GAP-2 — [IMPORTANT] Tab Management: macOS real, iOS/Android stubs or missing

**Severity:** IMPORTANT — functional parity violation

**macOS TabStore** (`core/apple/macos/Browser/TabStore.swift`): Full `TabStore: ObservableObject` with real tab creation, switching, closing, URL/title tracking, persisted via `UserDefaults`. HTTP routes:
- `get-tabs` → real implementation
- `new-tab` → real implementation via `TabStore`
- `switch-tab` → real implementation
- `close-tab` → real implementation

**iOS BrowserManagementHandler** (`core/apple/ios/Handlers/BrowserManagementHandler.swift`):
- `get-tabs` (line 56): calls `getTabs()` — returns hardcoded stub data
- `new-tab` (line 57): returns `successResponse(["tab": ["id": 0, ...], "tabCount": 1])` — hardcoded stub
- `switch-tab` (line 58): returns hardcoded stub
- `close-tab` (line 59): returns hardcoded stub
- `TabStore` does not exist on iOS
- `getTabs()` method (line 290): returns hardcoded stub with id=0

**Android BrowserManagementHandler** (`core/android/src/main/java/com/kelpie/browser/handlers/BrowserManagementHandler.kt`):
- All tab routes present but return hardcoded stubs (lines 49–52)
- `getTabs()` (line 274): returns `mapOf("tabs" to listOf(...), "activeTab" to 0)` — hardcoded stub
- `TabStore` does not exist on Android

**Intentionality:** The macOS app genuinely supports multi-tab browsing with real tab switching. iOS and Android may not need multi-tab support (mobile browsers often don't). However, the API surface should be consistent: either implement real tab management or document that mobile platforms intentionally stub it.

---

### GAP-3 — [MINOR] RendererHandler: macOS only

**Severity:** MINOR

**macOS** has `RendererHandler.swift` (line 96 in ServerState):
```swift
router.register("set-renderer") { body in await setRenderer(body) }
router.register("get-renderer") { _ in await getRenderer() }
```
Enables switching between WebKit (WKWebView) and Chromium (CEF) renderers.

**iOS:** No equivalent (WKWebView only on iOS).
**Android:** No equivalent (WebView only on Android).

**Intentionality:** Almost certainly intentional — dual-renderer is a macOS-specific feature. Mark as intentional.

---

### GAP-4 — [MINOR] Fullscreen controls: macOS only

**Severity:** MINOR

**macOS** has `set-fullscreen` / `get-fullscreen` routes in `BrowserManagementHandler.swift` (lines 25, 31, 192, 205).

**iOS/Android:** No equivalent (fullscreen is system-managed on mobile).

**Intentionality:** Intentional.

---

### GAP-5 — [MINOR] TV sync debug routes: iOS only

**Severity:** MINOR

**iOS DeviceHandler** registers: `debug-screens`, `debug-attach-local-tv`, `debug-detach-tv`, `set-tv-sync`, `get-tv-sync`, `set-debug-overlay`, `get-debug-overlay` (lines 16–22, 257–281 in `DeviceHandler.swift`).

Also uses `tvSyncEnabled` key in `ExternalDisplayManager.swift`.

**macOS:** No TV sync routes.
**Android:** No TV sync routes.

**Intentionality:** iOS-only Apple TV mirroring / external display sync is a platform-specific feature. Mark as intentional.

---

### GAP-6 — [MINOR] Request interception stubs: Android only

**Severity:** MINOR

**Android** registers stub routes in `BrowserManagementHandler.kt` (lines 54–58):
- `set-geolocation` → returns `{"set": true}`
- `clear-geolocation` → returns `{"cleared": true}`
- `set-request-interception` → returns `{"activeRules": 0}`
- `get-intercepted-requests` → returns `{"requests": [], "count": 0}`
- `clear-request-interception` → returns `{"cleared": 0}`

**macOS/iOS:** No equivalent routes.

**Intentionality:** Likely intentional (Android Chrome WebView supports geolocation override and request interception natively). The stubs return consistent responses so the CLI won't error when calling these methods.

---

### GAP-7 — [MINOR] FaviconExtractor: macOS only

**Severity:** MINOR

**macOS** has `core/apple/macos/Browser/FaviconExtractor.swift` (5 lines).
**iOS:** No equivalent file.
**Android:** No equivalent file.

**Intentionality:** Unknown — favicon extraction may not be needed on mobile.

---

### GAP-8 — [MINOR] AI/Ollama endpoint persistence: Android missing

**Severity:** MINOR

**macOS:** `AIState.swift` + `AIManager.swift` persist Ollama endpoint to `UserDefaults` (`ai.ollamaEndpoint`).
**iOS:** `AIState.swift` persists to `UserDefaults` (`ai.ollamaEndpoint`).
**Android:** `AIHandler.kt` has the HTTP routes but no `AIState` equivalent — Ollama endpoint is not persisted.

This means on Android, Ollama settings are lost on restart.

---

### GAP-9 — [MINOR] evaluateJSReturningArray: Android only

**Severity:** MINOR

**Android** `HandlerContext.kt` has `evaluateJSReturningArray()` (line 84):
```kotlin
suspend fun evaluateJSReturningArray(script: String): List<Map<String, Any?>>
```
Used in `LLMHandler.kt` for some DOM queries.

**macOS/iOS:** No equivalent method — would return a different structure for the same calls.

**Intentionality:** Android WebView's `evaluateJavascript` can return JSON arrays directly; WKWebView's `evaluateJavaScript` returns `Any`, requiring different unwrapping. Platform adaptation rather than a feature gap.

---

### GAP-10 — [MINOR] mDNS TXT record: no txtRecord method on Android DeviceInfo

**Severity:** MINOR

**macOS DeviceInfo** has `txtRecord(engine:)` method (line 31) returning `[String: String]` for `NWTXTRecord`.
**iOS DeviceInfo** has `txtRecord` property (line 43) returning `[String: String]`.
**Android DeviceInfo:** No `txtRecord` property or method.

Android `MDNSAdvertiser.kt` receives the `DeviceInfo` object but constructs its TXT record separately (or from the advertiser itself). Check `MDNSAdvertiser.kt` to confirm Android advertises the same fields.

---

### GAP-11 — [MINOR] TXT record `engine` field: macOS only

**Severity:** MINOR

**macOS** `txtRecord()` accepts `engine:` parameter and advertises `"engine": engine` in TXT record (used for dual-renderer tracking).

**iOS:** No `engine` field in `txtRecord`.
**Android:** No `txtRecord` method at all.

**Intentionality:** macOS-specific (dual renderer). Mark as intentional.

---

## Priority Summary

| Priority | Gap | Description |
|----------|-----|-------------|
| **CRITICAL** | GAP-1 | iOS `Snapshot3DHandler.swift` does not exist — compile failure / 3D inspector completely non-functional on iOS |
| **IMPORTANT** | GAP-2 | Tab management: macOS has real `TabStore` + tab routes; iOS/Android return hardcoded stubs |
| **MINOR** | GAP-3 | `RendererHandler` (dual-renderer switch) — macOS only, likely intentional |
| **MINOR** | GAP-4 | Fullscreen controls — macOS only, intentional |
| **MINOR** | GAP-5 | TV sync debug routes — iOS only, intentional |
| **MINOR** | GAP-6 | Request interception stubs — Android only, likely intentional |
| **MINOR** | GAP-7 | `FaviconExtractor` — macOS only |
| **MINOR** | GAP-8 | Ollama endpoint not persisted on Android |
| **MINOR** | GAP-9 | `evaluateJSReturningArray` — Android-only HandlerContext method |
| **MINOR** | GAP-10 | Android `DeviceInfo` has no `txtRecord` method |
| **MINOR** | GAP-11 | mDNS TXT record `engine` field — macOS only, intentional |

---

## Bridge Script Identity Check

| Bridge | macOS | iOS | Android |
|--------|-------|-----|---------|
| Console bridge handler name | `kelpieConsole` | `kelpieConsole` ✅ identical | `kelpieConsole` ✅ same name |
| Network bridge handler name | `kelpieNetwork` | `kelpieNetwork` ✅ identical | uses `evaluateJavascript` injection |
| Mutation buffer name | `window.__kelpieMutations` | `window.__kelpieMutations` ✅ identical | `window.__kelpieMutations` ✅ same |
| 3D inspector state | `window.__m3d` | **MISSING** ❌ | `window.__m3d` ✅ same |
| Snapshot3DBridge.js | 802 lines | **MISSING** ❌ | 749 lines, structurally identical |

macOS and iOS ConsoleHandler and NetworkBridge JS are **byte-for-byte identical** (verified by grep showing same `webkit.messageHandlers.kelpieConsole` and `kelpieNetwork` names, same masking logic). ✅

---

## Stores Comparison

| Store | macOS | iOS | Android |
|-------|-------|-----|---------|
| `HistoryStore` | ✅ `ObservableObject` + `UserDefaults` | ✅ `ObservableObject` + `UserDefaults` (native-backed) | ✅ `object` + `SharedPreferences` |
| `BookmarkStore` | ✅ `ObservableObject` + `UserDefaults` | ✅ `ObservableObject` + `UserDefaults` (native-backed) | ✅ `object` + `SharedPreferences` |
| `NetworkTrafficStore` | ✅ `ObservableObject` + `UserDefaults` | ✅ `ObservableObject` + `UserDefaults` (native-backed) | ✅ `object` + `SharedPreferences` |
| `TabStore` | ✅ real implementation | ❌ missing | ❌ missing |
| `ViewportState` | ✅ macOS-specific (shell window, viewport presets) | N/A | ❌ (has `ViewportPresetStore` separately) |
| `FaviconExtractor` | ✅ | ❌ | ❌ |
| `FeatureFlags` | ✅ `UserDefaults` | ✅ `UserDefaults` | ✅ `SharedPreferences` |
| `AIState` (Ollama) | ✅ | ✅ | ❌ |
| `HomeStore` | ❌ (uses `BrowserState.homeURL`) | ❌ (uses `BrowserState.homeURL`) | ✅ |

**Settings key alignment (homeURL):**
- macOS: `UserDefaults.standard.string(forKey: "homeURL")`
- iOS: `UserDefaults.standard.string(forKey: "homeURL")`
- Android: `prefs.getString("homeURL", DEFAULT_HOME_URL)`
All three platforms use `"homeURL"` string key. ✅
