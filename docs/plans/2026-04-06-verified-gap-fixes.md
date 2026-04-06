# Verified Gap Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all verified-real issues from the 9-agent adversarial review of the core parity gap analysis.

**Architecture:** Fixes organized by independent work streams that can be parallelized. Each stream touches different files.

**Tech Stack:** Swift (macOS/iOS), Kotlin (Android), C++ (native engine)

---

## Triage Summary

### FIX (verified real)
C1, C3, C8, C10, C11, C12, C13, C14, C15, C16, C19, C21,
I1, I3, I4, I8, I10, I11, I16, I17, I29, I30

### FIX (defense-in-depth, low-cost)
C2 (URL scheme allowlist), C6 (MutationHandler ID collisions + hint about cleanup)

### SKIP (exaggerated/wrong/architectural)
C4, C5, C7, C9, C17, C18, C20, I2, I5, I22, I26, I28

---

## Stream A: Swift JS Escaping (C8, I11)

**Files:**
- Create: `apps/macos/Kelpie/Handlers/JSEscape.swift`
- Modify: `apps/macos/Kelpie/Handlers/InteractionHandler.swift`
- Modify: `apps/macos/Kelpie/Handlers/EvaluateHandler.swift`
- Modify: `apps/macos/Kelpie/Handlers/HandlerContext.swift`
- Modify: `apps/macos/Kelpie/Handlers/MutationHandler.swift`
- Mirror: `apps/ios/Kelpie/Handlers/JSEscape.swift` (same file)
- Mirror: same fixes in iOS InteractionHandler, EvaluateHandler, MutationHandler

**New utility:**
```swift
// JSEscape.swift
enum JSEscape {
    static func string(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count + 8)
        for char in value {
            switch char {
            case "\\": result += "\\\\"
            case "'":  result += "\\'"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{2028}": result += "\\u2028"
            case "\u{2029}": result += "\\u2029"
            default: result.append(char)
            }
        }
        return result
    }
}
```

**Replace every** `selector.replacingOccurrences(of: "'", with: "\\'")` with `JSEscape.string(selector)`.

**Replace every** unescaped `\(char)` interpolation in typeText JS with `JSEscape.string(String(char))`.

---

## Stream B: HTTPServer (C1, C3)

**File:** `apps/macos/Kelpie/Network/HTTPServer.swift`

**C1 fix:** In `receiveData`, when Content-Length is absent on a POST, reject with 411 Length Required instead of assuming 0.

**C3 fix:** Add `NSLock` to protect mutable state. Wrap `listener`, `bonjourService`, `onBonjourStateChange`, `onStateChange` access in lock/unlock pairs. Alternative: use `os_unfair_lock` or convert callbacks to `let` set at init.

---

## Stream C: SharedCookieJar SameSite (C10)

**File:** `apps/macos/Kelpie/Browser/SharedCookieJar.swift`

Add `sameSite: String?` field to `StoredCookie`. Populate from `HTTPCookiePropertyKey("SameSite")`. Include in `signature()`. Set during `makeCookie()`.

---

## Stream D: CookieMigrator (C11)

**File:** `apps/macos/Kelpie/Renderer/CookieMigrator.swift`

When source is chromium, try to use SharedCookieJar as the cookie source instead of silently returning empty. The shared jar already has cookies persisted from the last sync.

```swift
guard source.engineName != "chromium" else {
    let snapshot = SharedCookieJar.load()
    guard !snapshot.cookies.isEmpty else { return }
    await target.setCookies(snapshot.cookies)
    return
}
```

---

## Stream E: HistoryStore (I4)

**File:** `apps/macos/Kelpie/Browser/HistoryStore.swift`

Add `@MainActor` to the class declaration. All mutations of `@Published var entries` already happen from SwiftUI contexts; this makes the requirement explicit and catches off-main-thread callers at compile time.

---

## Stream F: InferenceHarness JSON Parser (I17)

**File:** `apps/macos/Kelpie/AI/InferenceHarness.swift`

Replace brace-counting `parseJSONObject` with a string-aware version that tracks whether we're inside a JSON string literal (between unescaped `"`):

```swift
private func parseJSONObject(from text: String) -> [String: Any]? {
    guard let startIdx = text.firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var prevWasBackslash = false
    for i in text.indices[startIdx...] {
        let ch = text[i]
        if inString {
            if ch == "\\" && !prevWasBackslash { prevWasBackslash = true; continue }
            if ch == "\"" && !prevWasBackslash { inString = false }
            prevWasBackslash = false
            continue
        }
        switch ch {
        case "\"": inString = true
        case "{": depth += 1
        case "}":
            depth -= 1
            if depth == 0 {
                let json = String(text[startIdx...i])
                guard let data = json.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        default: break
        }
    }
    return nil
}
```

---

## Stream G: NavigationHandler Scheme Allowlist (C2)

**File:** `apps/macos/Kelpie/Handlers/NavigationHandler.swift`
**Mirror:** `apps/ios/Kelpie/Handlers/NavigationHandler.swift`

Add scheme check after URL parsing:
```swift
guard let url = URL(string: urlString),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      context.renderer != nil else {
    return errorResponse(code: "INVALID_URL", message: "Missing or invalid URL")
}
```

---

## Stream H: MutationHandler ID Collisions (C6)

**File:** `apps/macos/Kelpie/Handlers/MutationHandler.swift`
**Mirror:** `apps/ios/Kelpie/Handlers/MutationHandler.swift`

Replace `Date.now()` with `crypto.randomUUID()` (or fallback):
```javascript
var id = 'mut_' + (crypto.randomUUID ? crypto.randomUUID() : Date.now() + '_' + Math.random().toString(36).slice(2));
```

---

## Stream I: C++ Handler Fixes (C12, C13, C14, C15, C16, I8, I10)

### C12 — Add wait-for-element and wait-for-navigation

**File:** `native/engine-chromium-desktop/src/handlers/evaluate_handler.cpp` + header

Add two new methods. Register them in `Register()`:
```cpp
router.Register("wait-for-element", [this](const json& p) { return WaitForElement(p); });
router.Register("wait-for-navigation", [this](const json& p) { return WaitForNavigation(p); });
```

`WaitForElement`: Poll with `EvaluateJsReturningJson` checking for element existence + visibility, sleep 100ms between polls, timeout default 5000ms.

`WaitForNavigation`: Poll `IsLoading()` with 100ms sleep, timeout default 10000ms.

### C13 — Fix scroll-to-bottom

**File:** `native/engine-chromium-desktop/src/handlers/scroll_handler.cpp`

Change line 13 from `document.body.scrollHeight` to `document.documentElement.scrollHeight`.

### C14 — Fix type to dispatch per-character events

**File:** `native/engine-chromium-desktop/src/handlers/interaction_handler.cpp`

Replace the simple `element.value = next` loop with per-character event dispatching (keydown, input, keyup) matching Swift's pattern.

### C15 — Fix navigate to wait for page load

**File:** `native/engine-chromium-desktop/src/handlers/navigation_handler.cpp`

After `LoadUrl`, add a polling loop on `IsLoading()` with `std::this_thread::sleep_for(100ms)`, timeout 10s.

### C16 — Fix fill to use property descriptor trick

**File:** `native/engine-chromium-desktop/src/handlers/interaction_handler.cpp`

Replace `element.value = VALUE;` with:
```js
var nativeSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set ||
                   Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
if (nativeSetter) nativeSetter.call(element, VALUE);
else element.value = VALUE;
```

### I8 — Align query-selector response schema

**File:** `native/engine-chromium-desktop/src/handlers/dom_handler.cpp`

Match Swift response: `{found, element: {tag, id, text, classes, rect, visible}}`. Remove `attributes` from default response.

### I10 — Align text extraction

**Files:** `native/engine-chromium-desktop/src/handlers/dom_handler.cpp`

Use `(element.textContent || '')` consistently to match Swift. The `innerText` behavior difference is a semantic change that could break consumers.

---

## Stream J: RendererInterface Cookie Methods (C21)

**Files:**
- `native/core-automation/include/kelpie/renderer_interface.h`
- `native/engine-chromium-desktop/include/kelpie/cef_renderer.h`
- `native/engine-chromium-desktop/src/cef_renderer.cpp`

Add virtual stubs to RendererInterface:
```cpp
virtual std::string GetCookies() { return "[]"; }
virtual void SetCookie(const std::string& cookie_string) {}
virtual void DeleteAllCookies() {}
```

---

## Stream K: Android mDNS (I29)

**File:** `apps/android/app/src/main/java/com/kelpie/browser/network/MDNSAdvertiser.kt`

Add `setAttribute("engine", "webview")` after the existing TXT attributes.

---

## Stream L: iOS Parity (I29, I30)

**Files:**
- `apps/ios/Kelpie/Device/DeviceInfo.swift` — add `"engine": "webkit"` to txtRecord
- `apps/ios/Kelpie/Handlers/Snapshot3DHandler.swift` — add `set-mode`, `zoom`, `reset-view`
- `apps/ios/Kelpie/Network/Router.swift` — add stubs for the three new routes

---

## Stream M: Port Collision Guard (C19)

**File:** `native/engine-chromium-desktop/include/kelpie/desktop_http_server.h`

Add a comment documenting that Swift ServerState has port fallback logic and that if both servers ever run simultaneously, the C++ side should also attempt fallback. No code change needed now since only one server runs at a time.

---

## Stream N: NetworkBridge Closure Cap (I16)

**File:** `apps/macos/Kelpie/Handlers/NetworkBridge.swift`
**Mirror:** `apps/ios/Kelpie/Handlers/NetworkBridge.swift`

Add an `AbortSignal` check on the fetch interception to avoid leaking closures for aborted requests. Add a max-pending counter.
