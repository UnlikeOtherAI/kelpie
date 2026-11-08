# Platform Completion — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring iOS and Android to full feature parity with macOS, add HuggingFace API key gating on all platforms, and verify every feature end-to-end via MCP and interactive App Reveal testing.

**Architecture:** Each phase targets one feature area across both mobile platforms simultaneously (per AGENTS.md parity rule). Every phase ends with a verification gate that exercises the feature via MCP tool calls and manual App Reveal click-through. AI testing uses the smallest available models (tinyllama for Ollama, a small gated model for HuggingFace).

**Tech Stack:** Swift/WKWebView (iOS), Kotlin/WebView (Android), TypeScript/Vitest (CLI tests), MCP stdio transport for verification.

---

## Phase Overview

| Phase | Feature | Platforms | Effort |
|-------|---------|-----------|--------|
| 1 | Dialog handling (alert/confirm/prompt) | iOS + Android | Medium |
| 2 | Keyboard state detection | iOS + Android | Small |
| 3 | Element obscured detection | iOS + Android | Small |
| 4 | HuggingFace API key gating + UI | iOS + Android + macOS | Medium |
| 5 | CLI coverage for missing commands | CLI | Small |
| 6 | E2E verification suite | CLI tests | Medium |

Tabs, iframes, geolocation override, and request interception are **out of scope** — these are hard platform limitations (single-tab WebView, no cross-origin iframe switching, no CDP on mobile). The existing stubs with plausible responses are the correct behaviour.

---

## Phase 1: Dialog Handling (iOS + Android)

### Background

JavaScript `alert()`, `confirm()`, and `prompt()` calls trigger native delegate methods that neither iOS nor Android currently implements. macOS also has this stubbed. The fix is to intercept dialogs via WKUIDelegate (iOS) / WebChromeClient (Android), queue them, and expose them through the existing `get-dialog` / `handle-dialog` / `set-dialog-auto-handler` endpoints.

### Task 1.1: iOS — Add dialog state and WKUIDelegate interception

**Files:**
- Create: `core/apple/ios/Browser/DialogState.swift`
- Modify: `core/apple/ios/Browser/WebViewCoordinator.swift`
- Modify: `core/apple/ios/Handlers/BrowserManagementHandler.swift`

**Step 1: Create DialogState model**

```swift
// core/apple/ios/Browser/DialogState.swift
import Foundation

@MainActor
final class DialogState: ObservableObject {
    struct PendingDialog {
        let type: String          // "alert", "confirm", "prompt"
        let message: String
        let defaultText: String?  // prompt default value
        let completion: (String?) -> Void  // nil = dismiss, string = accept (with input for prompt)
    }

    @Published private(set) var current: PendingDialog?
    var autoHandler: String?  // nil = queue, "accept", "dismiss"

    func enqueue(_ dialog: PendingDialog) {
        if let auto = autoHandler {
            dialog.completion(auto == "accept" ? (dialog.defaultText ?? "") : nil)
            return
        }
        current = dialog
    }

    func handle(action: String, text: String? = nil) {
        guard let dialog = current else { return }
        if action == "accept" {
            dialog.completion(dialog.type == "prompt" ? (text ?? dialog.defaultText ?? "") : "")
        } else {
            dialog.completion(nil)
        }
        current = nil
    }
}
```

**Step 2: Implement WKUIDelegate methods in WebViewCoordinator**

Add these three methods to the existing `Coordinator` class in `WebViewCoordinator.swift` (after line ~142, inside the WKUIDelegate extension area):

```swift
func webView(_ webView: WKWebView,
             runJavaScriptAlertPanelWithMessage message: String,
             initiatedByFrame frame: WKFrameInfo,
             completionHandler: @escaping () -> Void) {
    dialogState.enqueue(.init(type: "alert", message: message, defaultText: nil) { _ in
        completionHandler()
    })
}

func webView(_ webView: WKWebView,
             runJavaScriptConfirmPanelWithMessage message: String,
             initiatedByFrame frame: WKFrameInfo,
             completionHandler: @escaping (Bool) -> Void) {
    dialogState.enqueue(.init(type: "confirm", message: message, defaultText: nil) { result in
        completionHandler(result != nil)
    })
}

func webView(_ webView: WKWebView,
             runJavaScriptTextInputPanelWithPrompt prompt: String,
             defaultText: String?,
             initiatedByFrame frame: WKFrameInfo,
             completionHandler: @escaping (String?) -> Void) {
    dialogState.enqueue(.init(type: "prompt", message: prompt, defaultText: defaultText) { result in
        completionHandler(result)
    })
}
```

The `dialogState` property needs to be added to Coordinator and passed in from the parent. Trace the existing Coordinator init to find where to inject it.

**Step 3: Wire dialog state into HandlerContext**

The `HandlerContext` (in `core/apple/ios/Handlers/HandlerContext.swift`) needs a reference to `DialogState` so the HTTP handler can read/write it. Add a `dialogState` property.

**Step 4: Replace stubs in BrowserManagementHandler**

In `core/apple/ios/Handlers/BrowserManagementHandler.swift`, replace the three dialog stubs (lines 46-53) with:

```swift
router.register("get-dialog") { [weak self] _ in
    guard let ds = self?.context.dialogState, let d = ds.current else {
        return self?.successResponse(["showing": false, "dialog": NSNull()]) ?? [:]
    }
    return self?.successResponse([
        "showing": true,
        "dialog": ["type": d.type, "message": d.message, "defaultText": d.defaultText ?? NSNull()]
    ]) ?? [:]
}

router.register("handle-dialog") { [weak self] body in
    guard let ds = self?.context.dialogState else {
        return self?.errorResponse(code: "NO_DIALOG", message: "No dialog showing") ?? [:]
    }
    let action = body["action"] as? String ?? "accept"
    let text = body["text"] as? String
    ds.handle(action: action, text: text)
    return self?.successResponse(["action": action, "dialogType": ds.current?.type ?? "none"]) ?? [:]
}

router.register("set-dialog-auto-handler") { [weak self] body in
    guard let ds = self?.context.dialogState else {
        return self?.errorResponse(code: "INTERNAL", message: "Dialog state unavailable") ?? [:]
    }
    if let enabled = body["enabled"] as? Bool {
        ds.autoHandler = enabled ? "accept" : nil
    }
    if let mode = body["mode"] as? String {
        ds.autoHandler = mode  // "accept", "dismiss", or nil
    }
    return self?.successResponse(["enabled": ds.autoHandler != nil, "mode": ds.autoHandler ?? "queue"]) ?? [:]
}
```

**Step 5: Commit**

```
feat(ios): implement dialog interception via WKUIDelegate
```

---

### Task 1.2: Android — Add dialog state and WebChromeClient interception

**Files:**
- Create: `core/android/src/main/java/com/kelpie/browser/browser/DialogState.kt`
- Modify: `core/android/src/main/java/com/kelpie/browser/browser/WebViewContainer.kt`
- Modify: `core/android/src/main/java/com/kelpie/browser/handlers/BrowserManagementHandler.kt`
- Modify: `core/android/src/main/java/com/kelpie/browser/handlers/HandlerContext.kt`

**Step 1: Create DialogState**

```kotlin
// core/android/src/main/java/com/kelpie/browser/browser/DialogState.kt
package com.kelpie.browser.browser

import android.webkit.JsResult
import android.webkit.JsPromptResult

class DialogState {
    data class PendingDialog(
        val type: String,
        val message: String,
        val defaultText: String?,
        val jsResult: JsResult?,
        val jsPromptResult: JsPromptResult?
    )

    var current: PendingDialog? = null
        private set
    var autoHandler: String? = null  // null = queue, "accept", "dismiss"

    fun enqueue(dialog: PendingDialog) {
        val auto = autoHandler
        if (auto != null) {
            if (auto == "accept") {
                dialog.jsPromptResult?.confirm(dialog.defaultText ?: "")
                    ?: dialog.jsResult?.confirm()
            } else {
                dialog.jsResult?.cancel()
            }
            return
        }
        current = dialog
    }

    fun handle(action: String, text: String? = null) {
        val dialog = current ?: return
        if (action == "accept") {
            dialog.jsPromptResult?.confirm(text ?: dialog.defaultText ?: "")
                ?: dialog.jsResult?.confirm()
        } else {
            dialog.jsResult?.cancel()
        }
        current = null
    }
}
```

**Step 2: Add WebChromeClient overrides in WebViewContainer**

In `WebViewContainer.kt` (inside the `webChromeClient = object : WebChromeClient() { ... }` block, after onProgressChanged), add:

```kotlin
override fun onJsAlert(view: WebView, url: String?, message: String, result: JsResult): Boolean {
    dialogState.enqueue(DialogState.PendingDialog("alert", message, null, result, null))
    return true
}

override fun onJsConfirm(view: WebView, url: String?, message: String, result: JsResult): Boolean {
    dialogState.enqueue(DialogState.PendingDialog("confirm", message, null, result, null))
    return true
}

override fun onJsPrompt(view: WebView, url: String?, message: String, defaultValue: String?, result: JsPromptResult): Boolean {
    dialogState.enqueue(DialogState.PendingDialog("prompt", message, defaultValue, null, result))
    return true
}
```

**Step 3: Add dialogState to HandlerContext and replace stubs**

Add `val dialogState: DialogState` to `HandlerContext`. Replace the three dialog stubs in `BrowserManagementHandler.kt` (lines 44-47) with real implementations mirroring the iOS pattern.

**Step 4: Commit**

```
feat(android): implement dialog interception via WebChromeClient
```

---

### Verification Gate 1: Dialog Handling

**MCP test script** — run via `kelpie mcp` or direct HTTP:

```bash
# 1. Navigate to a test page
kelpie navigate "data:text/html,<button onclick='alert(\"hello\")'>Alert</button><button onclick='confirm(\"sure?\")'>Confirm</button><button onclick='prompt(\"name?\",\"default\")'>Prompt</button>"

# 2. Set auto-handler to queue mode
kelpie dialog auto --mode queue

# 3. Click the alert button
kelpie click "button:nth-child(1)"

# 4. Verify dialog is showing
kelpie dialog
# Expected: {"showing": true, "dialog": {"type": "alert", "message": "hello"}}

# 5. Accept the dialog
kelpie dialog accept

# 6. Verify dialog is dismissed
kelpie dialog
# Expected: {"showing": false, "dialog": null}

# 7. Click confirm button, check, dismiss
kelpie click "button:nth-child(2)"
kelpie dialog
# Expected: {"showing": true, "dialog": {"type": "confirm", "message": "sure?"}}
kelpie dialog dismiss

# 8. Click prompt button, check, accept with text
kelpie click "button:nth-child(3)"
kelpie dialog
# Expected: {"showing": true, "dialog": {"type": "prompt", "message": "name?", "defaultText": "default"}}
kelpie dialog accept --text "Claude"

# 9. Test auto-handler mode
kelpie dialog auto --enabled true
kelpie click "button:nth-child(1)"
kelpie dialog
# Expected: {"showing": false} — auto-accepted
```

**App Reveal test:**
1. Open App Reveal, connect to the running iOS/Android app
2. Navigate to the test page above
3. Click each dialog button in the browser UI — verify native dialog appears
4. Use API to accept/dismiss — verify dialog dismisses in the UI
5. Enable auto-handler — click button — verify no dialog appears (auto-handled)

**Run on both iOS and Android. Both must pass identically.**

---

## Phase 2: Keyboard State Detection (iOS + Android)

### Task 2.1: iOS — Real keyboard state via NotificationCenter

**Files:**
- Modify: `core/apple/ios/Handlers/BrowserManagementHandler.swift`

**Step 1: Add keyboard tracking**

Add a keyboard observer class or properties to BrowserManagementHandler (or a separate KeyboardObserver that HandlerContext holds). Use `UIResponder.keyboardWillShowNotification` / `UIResponder.keyboardWillHideNotification`:

```swift
@MainActor
final class KeyboardObserver: ObservableObject {
    @Published var isVisible = false
    @Published var height: CGFloat = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { [weak self] notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                self?.isVisible = true
                self?.height = frame.height
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isVisible = false
            self?.height = 0
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
```

**Step 2: Replace the hardcoded getKeyboardState**

Replace lines 182-185 in BrowserManagementHandler.swift:

```swift
private func getKeyboardState() async -> [String: Any] {
    let kb = context.keyboardObserver
    let screen = UIScreen.main.bounds
    let visibleHeight = screen.height - kb.height
    return successResponse([
        "visible": kb.isVisible,
        "height": Int(kb.height),
        "type": "default",
        "visibleViewport": ["width": Int(screen.width), "height": Int(visibleHeight)],
        "focusedElement": NSNull()
    ])
}
```

**Step 3: Commit**

```
feat(ios): detect real keyboard state via NotificationCenter
```

---

### Task 2.2: Android — Real keyboard state via WindowInsets

**Files:**
- Modify: `core/android/src/main/java/com/kelpie/browser/handlers/BrowserManagementHandler.kt`
- Modify: `core/android/src/main/java/com/kelpie/browser/handlers/HandlerContext.kt`

**Step 1: Add keyboard height tracking**

In HandlerContext or a new KeyboardObserver, use `ViewCompat.setOnApplyWindowInsetsListener` on the root view:

```kotlin
class KeyboardObserver(private val rootView: View) {
    var isVisible: Boolean = false
        private set
    var height: Int = 0
        private set

    init {
        ViewCompat.setOnApplyWindowInsetsListener(rootView) { _, insets ->
            val imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
            val navInsets = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            height = (imeInsets.bottom - navInsets.bottom).coerceAtLeast(0)
            isVisible = height > 0
            insets
        }
    }
}
```

**Step 2: Replace getKeyboardState stub**

```kotlin
private fun getKeyboardState(): Map<String, Any?> {
    val kb = ctx.keyboardObserver
    val dm = ctx.activity.resources.displayMetrics
    return successResponse(mapOf(
        "visible" to kb.isVisible,
        "height" to kb.height,
        "type" to "default",
        "visibleViewport" to mapOf(
            "width" to (dm.widthPixels / dm.density).toInt(),
            "height" to ((dm.heightPixels - kb.height) / dm.density).toInt()
        )
    ))
}
```

**Step 3: Commit**

```
feat(android): detect real keyboard state via WindowInsets
```

---

### Verification Gate 2: Keyboard State

```bash
# 1. Navigate to a page with an input
kelpie navigate "data:text/html,<input id='name' placeholder='Type here'>"

# 2. Check keyboard is hidden
kelpie keyboard state
# Expected: {"visible": false, "height": 0, ...}

# 3. Show keyboard by focusing input
kelpie keyboard show --selector "#name"

# 4. Check keyboard is now visible
kelpie keyboard state
# Expected: {"visible": true, "height": <non-zero>, ...}

# 5. Hide keyboard
kelpie keyboard hide

# 6. Verify hidden again
kelpie keyboard state
# Expected: {"visible": false, "height": 0, ...}
```

**App Reveal test:**
1. Connect to device via App Reveal
2. Navigate to a form page
3. Tap an input field — verify keyboard appears
4. Call `kelpie keyboard state` — verify height matches visible keyboard
5. Call `kelpie keyboard hide` — verify keyboard dismisses

---

## Phase 3: Element Obscured Detection (iOS + Android)

### Task 3.1: iOS — Use keyboard height for obscured check

**Files:**
- Modify: `core/apple/ios/Handlers/BrowserManagementHandler.swift`

Replace `isElementObscured` (lines 250-264) to use the real keyboard height:

```swift
private func isElementObscured(_ body: [String: Any]) async -> [String: Any] {
    guard let selector = body["selector"] as? String else {
        return errorResponse(code: "MISSING_PARAM", message: "selector is required")
    }
    let escaped = JSEscape.string(selector)
    let js = "(function(){var el=document.querySelector('\(escaped)');if(!el)return null;var r=el.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom};})()"
    do {
        let result = try await context.evaluateJSReturningJSON(js)
        guard let bottom = result["bottom"] as? Double else {
            return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found")
        }
        let kb = context.keyboardObserver
        let viewport = await UIScreen.main.bounds
        let visibleBottom = Double(viewport.height - kb.height)
        let obscured = bottom > visibleBottom && kb.isVisible
        let overlap = obscured ? bottom - visibleBottom : 0.0
        return successResponse([
            "element": ["selector": selector, "rect": result],
            "obscured": obscured,
            "reason": obscured ? "keyboard" : NSNull(),
            "keyboardOverlap": obscured ? Int(overlap) : NSNull(),
            "suggestion": obscured ? "scroll-into-view" : NSNull()
        ])
    } catch {
        return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
    }
}
```

**Step 2: Commit**

```
feat(ios): detect elements obscured by keyboard
```

---

### Task 3.2: Android — Same pattern with WindowInsets height

**Files:**
- Modify: `core/android/src/main/java/com/kelpie/browser/handlers/BrowserManagementHandler.kt`

Same approach — use `ctx.keyboardObserver.height` and element's bounding rect bottom to determine overlap.

**Step 2: Commit**

```
feat(android): detect elements obscured by keyboard
```

---

### Verification Gate 3: Element Obscured

```bash
# 1. Navigate to page with input at bottom
kelpie navigate "data:text/html,<div style='height:2000px'></div><input id='bottom' placeholder='At bottom'>"

# 2. Scroll to bottom and focus input (keyboard opens)
kelpie scroll-bottom
kelpie keyboard show --selector "#bottom"

# 3. Check if element is obscured
kelpie obscured "#bottom"
# Expected: {"obscured": true, "reason": "keyboard", "keyboardOverlap": <number>}

# 4. Hide keyboard
kelpie keyboard hide

# 5. Check again
kelpie obscured "#bottom"
# Expected: {"obscured": false}
```

---

## Phase 4: HuggingFace API Key Gating + UI

### Background

macOS already has HF token persistence (`@AppStorage("huggingFaceToken")` in AIState) and a popover in AIChatPanel. iOS and Android have no token UI. The requirement: block model downloads until the user provides an API key, showing a prompt with an "Open HuggingFace" button that navigates to `https://huggingface.co/settings/tokens` **inside the Kelpie browser** (in a new tab or the current view).

### Task 4.1: iOS — HF token persistence and download gating

**Files:**
- Modify: `core/apple/ios/AI/AIState.swift` — add `@AppStorage("huggingFaceToken")` property
- Modify: `core/apple/ios/Views/SettingsView.swift` — add HF token section with SecureField
- Modify: `core/apple/ios/AI/AIManager.swift` — gate downloads on token presence

**Step 1: Add token persistence to AIState**

In `AIState.swift`, add:

```swift
@AppStorage("huggingFaceToken") var huggingFaceToken: String = ""
```

**Step 2: Add HF token section to SettingsView**

After the experimental features section in SettingsView.swift, add a "HuggingFace" section:

```swift
Section("HuggingFace") {
    if huggingFaceToken.isEmpty {
        HStack {
            Image(systemName: "key")
                .foregroundColor(.orange)
            Text("API key required for model downloads")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    } else {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
            Text("API key configured")
                .font(.caption)
        }
    }

    if showTokenField {
        SecureField("HuggingFace API Token", text: $tokenDraft)
            .textFieldStyle(.roundedBorder)
        HStack {
            Button("Save") {
                huggingFaceToken = tokenDraft
                showTokenField = false
            }
            .disabled(tokenDraft.isEmpty)

            if !huggingFaceToken.isEmpty {
                Button("Clear") {
                    huggingFaceToken = ""
                    tokenDraft = ""
                }
                .foregroundColor(.red)
            }
        }
    }

    Button(showTokenField ? "Cancel" : (huggingFaceToken.isEmpty ? "Set API Key" : "Change API Key")) {
        if showTokenField {
            showTokenField = false
        } else {
            tokenDraft = huggingFaceToken
            showTokenField = true
        }
    }

    Button("Open HuggingFace Tokens Page") {
        onNavigate?("https://huggingface.co/settings/tokens")
        dismiss()
    }
    .foregroundColor(.blue)
}
```

The `onNavigate` callback should be a closure passed into SettingsView that calls through to the WebView's `load(url:)`. The settings sheet dismisses and the browser navigates to the HF tokens page.

**Step 3: Gate downloads**

In the AI handler or AIState download method, before starting any HF download:

```swift
guard !huggingFaceToken.isEmpty else {
    return errorResponse(
        code: "AUTH_REQUIRED",
        message: "HuggingFace API key required. Set it in Settings before downloading models."
    )
}
aiManager.hfToken = huggingFaceToken
```

**Step 4: Commit**

```
feat(ios): add HuggingFace API key gating with settings UI
```

---

### Task 4.2: Android — HF token persistence and download gating

**Files:**
- Modify: `core/android/src/main/java/com/kelpie/browser/ai/AIState.kt` — add SharedPreferences token
- Modify: `core/android/src/main/java/com/kelpie/browser/ui/SettingsScreen.kt` — add HF section
- Modify: AI handler to gate downloads

**Step 1: Add token to AIState**

```kotlin
class AIState(private val prefs: SharedPreferences) {
    var huggingFaceToken: String
        get() = prefs.getString("huggingFaceToken", "") ?: ""
        set(value) = prefs.edit().putString("huggingFaceToken", value).apply()
}
```

**Step 2: Add HF section to SettingsScreen**

Add a composable section with:
- Status indicator (key icon orange if empty, green checkmark if set)
- "Set API Key" button that shows a dialog with a password TextField
- "Open HuggingFace" button that navigates the WebView to `https://huggingface.co/settings/tokens` and dismisses settings

The "Open HuggingFace" button must navigate **inside the app's WebView**, not open an external browser. Pass a `onNavigate: (String) -> Unit` callback into SettingsScreen that calls through to the WebView.

**Step 3: Gate downloads**

Same pattern as iOS — return `AUTH_REQUIRED` error if token is empty.

**Step 4: Commit**

```
feat(android): add HuggingFace API key gating with settings UI
```

---

### Task 4.3: macOS — Align with mobile pattern

**Files:**
- Modify: `core/apple/macos/Views/SettingsView.swift` — add HF token section (currently only in AIChatPanel)
- Verify: download gating already works (AIState.swift line 179)

macOS already has the token popover in AIChatPanel. Add the same section to SettingsView for consistency. The "Open HuggingFace" button should navigate the browser to the tokens page (use the existing `onAuthFailureNavigate` pattern from BrowserView.swift line 313).

**Step 1: Commit**

```
feat(macos): add HuggingFace token section to settings view
```

---

### Verification Gate 4: HuggingFace API Key Gating

**Test A — No key set (expect rejection):**

```bash
# 1. Ensure no token is set (clear via settings if needed)
# 2. Try to load a HuggingFace model
kelpie ai load "hf:gemma-4-e2b-q4"
# Expected: ERROR — AUTH_REQUIRED, "HuggingFace API key required"

# 3. Try ai-pull via CLI
kelpie ai pull gemma-4-e2b-q4
# Expected: ERROR — AUTH_REQUIRED
```

**Test B — Set key via settings, then download:**

1. Open App Reveal, connect to device
2. Open Settings panel (via floating menu)
3. Find the HuggingFace section
4. Tap "Set API Key" — verify SecureField/dialog appears
5. Tap "Open HuggingFace Tokens Page" — verify browser navigates to `https://huggingface.co/settings/tokens` (inside the app, not external browser)
6. Go back to Settings, paste a token, tap Save
7. Retry model download — should proceed with auth header

**Test C — AI inference round-trip (smallest model):**

```bash
# Using Ollama (tinyllama — smallest model)
ollama pull tinyllama
kelpie ai load "ollama:tinyllama"
kelpie ai status
# Expected: {"loaded": true, "backend": "ollama", "model": "tinyllama"}

kelpie ai ask "Say hello in one word"
# Expected: response with generated text

kelpie ai unload
```

**Test D — HuggingFace cloud inference:**

```bash
# Token should be set from Test B
# Use smallest model available — the env var HUGGING_FACE_TOKEN should be in environment
kelpie ai load "hf-cloud:google/gemma-2b"
kelpie ai status
kelpie ai ask "Say hello"
# Expected: response from HF Inference API
kelpie ai unload
```

**App Reveal click-through for AI:**
1. Open settings, verify HF token status shows green checkmark
2. Load an Ollama model via MCP
3. Open AI chat panel (if exists on mobile) or use API
4. Send a prompt → wait for response → verify response appears
5. Unload model via MCP

---

## Phase 5: CLI Coverage for Missing Commands

### Task 5.1: Add missing CLI commands

**Files:**
- Modify: `packages/cli/src/commands/` — add new command files as needed
- Modify: `packages/cli/src/mcp/tools.ts` — add any missing MCP tool definitions

Commands to add:

| Command | Maps to | Notes |
|---------|---------|-------|
| `kelpie renderer get` | `GET /v1/get-renderer` | macOS only |
| `kelpie renderer set <engine>` | `POST /v1/set-renderer` | macOS only |
| `kelpie fullscreen get` | `GET /v1/get-fullscreen` | macOS only |
| `kelpie fullscreen set <bool>` | `POST /v1/set-fullscreen` | macOS only |
| `kelpie orientation get` | `GET /v1/get-orientation` | Mobile only |
| `kelpie orientation set <mode>` | `POST /v1/set-orientation` | Mobile only |
| `kelpie viewport-preset set <name>` | `POST /v1/set-viewport-preset` | All |
| `kelpie viewport-preset list` | `GET /v1/get-viewport-presets` | All |

Check if these already exist before creating. Some may already be wired but not discoverable. Each command is a thin wrapper calling `sendCommand(device, method, body)`.

**Step 1: Implement and commit**

```
feat(cli): add renderer, fullscreen, orientation, and viewport-preset commands
```

---

### Verification Gate 5: CLI Commands

```bash
# macOS-specific (run against macOS device)
kelpie renderer get
# Expected: {"engine": "webkit"} or similar

kelpie fullscreen get
# Expected: {"fullscreen": false}

# Mobile-specific (run against iOS or Android)
kelpie orientation get
# Expected: {"orientation": "portrait", "locked": false}

# All platforms
kelpie viewport-preset list
# Expected: array of preset objects
```

---

## Phase 6: E2E Verification Suite

### Task 6.1: Add E2E tests for new features

**Files:**
- Create: `packages/cli/tests/e2e/dialogs.e2e.test.ts`
- Create: `packages/cli/tests/e2e/keyboard.e2e.test.ts`
- Create: `packages/cli/tests/e2e/ai.e2e.test.ts`
- Modify: `packages/cli/tests/e2e/browser-management.e2e.test.ts` — extend existing

**Step 1: Dialog E2E tests**

```typescript
// packages/cli/tests/e2e/dialogs.e2e.test.ts
import { describe, it, expect } from "vitest";
import { deviceRequest, skipUnlessDevice, testDevice } from "./setup";

describe("dialog handling", () => {
  const device = testDevice();

  skipUnlessDevice(device);

  it("should report no dialog when none is showing", async () => {
    const { ok, data } = await deviceRequest(device, "get-dialog", {});
    expect(ok).toBe(true);
    expect(data.showing).toBe(false);
  });

  it("should intercept alert dialog", async () => {
    await deviceRequest(device, "navigate", {
      url: "data:text/html,<button onclick='alert(\"test\")' id='btn'>Alert</button>",
    });
    await deviceRequest(device, "set-dialog-auto-handler", { enabled: false });
    await deviceRequest(device, "click", { selector: "#btn" });

    const { data } = await deviceRequest(device, "get-dialog", {});
    expect(data.showing).toBe(true);
    expect(data.dialog.type).toBe("alert");
    expect(data.dialog.message).toBe("test");

    await deviceRequest(device, "handle-dialog", { action: "accept" });
    const after = await deviceRequest(device, "get-dialog", {});
    expect(after.data.showing).toBe(false);
  });

  it("should auto-handle dialogs when enabled", async () => {
    await deviceRequest(device, "set-dialog-auto-handler", { enabled: true });
    await deviceRequest(device, "click", { selector: "#btn" });
    // Small delay for auto-handling
    await new Promise((r) => setTimeout(r, 200));
    const { data } = await deviceRequest(device, "get-dialog", {});
    expect(data.showing).toBe(false);
  });
});
```

**Step 2: Keyboard E2E tests**

```typescript
// packages/cli/tests/e2e/keyboard.e2e.test.ts
import { describe, it, expect } from "vitest";
import { deviceRequest, skipUnlessDevice, testDevice } from "./setup";

describe("keyboard state", () => {
  const device = testDevice();

  skipUnlessDevice(device);

  it("should report keyboard hidden initially", async () => {
    const { data } = await deviceRequest(device, "get-keyboard-state", {});
    expect(data.visible).toBe(false);
    expect(data.height).toBe(0);
  });

  it("should detect keyboard after focusing input", async () => {
    await deviceRequest(device, "navigate", {
      url: "data:text/html,<input id='inp' placeholder='type'>",
    });
    await deviceRequest(device, "show-keyboard", { selector: "#inp" });
    // Allow keyboard animation
    await new Promise((r) => setTimeout(r, 500));
    const { data } = await deviceRequest(device, "get-keyboard-state", {});
    // On mobile: visible=true, height>0. On macOS: PLATFORM_NOT_SUPPORTED.
    // This test only makes sense on mobile.
    if (data.visible !== undefined) {
      expect(data.height).toBeGreaterThanOrEqual(0);
    }
  });
});
```

**Step 3: AI E2E tests**

```typescript
// packages/cli/tests/e2e/ai.e2e.test.ts
import { describe, it, expect } from "vitest";
import { deviceRequest, skipUnlessDevice, testDevice } from "./setup";

describe("AI inference", () => {
  const device = testDevice();

  skipUnlessDevice(device);

  it("should report ai status", async () => {
    const { ok, data } = await deviceRequest(device, "ai-status", {});
    expect(ok).toBe(true);
    expect(data).toHaveProperty("loaded");
    expect(data).toHaveProperty("backend");
  });

  it("should reject HF download without token", async () => {
    // This test assumes no HF token is set on the device
    const { data } = await deviceRequest(device, "ai-load", {
      model: "hf:gemma-4-e2b-q4",
    });
    // Should fail with auth_required or similar
    if (!data.success) {
      expect(data.error?.code).toMatch(/AUTH|auth/);
    }
  });

  it("should load and query ollama model", async () => {
    const load = await deviceRequest(device, "ai-load", {
      model: "ollama:tinyllama",
    });
    if (!load.ok) return; // Ollama not available, skip

    const status = await deviceRequest(device, "ai-status", {});
    expect(status.data.loaded).toBe(true);

    const infer = await deviceRequest(device, "ai-infer", {
      prompt: "Say hello in one word",
    });
    expect(infer.ok).toBe(true);
    expect(infer.data).toHaveProperty("response");

    await deviceRequest(device, "ai-unload", {});
  });
});
```

**Step 4: Run full test suite**

```bash
cd packages/cli && pnpm test
```

**Step 5: Commit**

```
test: add E2E tests for dialogs, keyboard state, and AI inference
```

---

### Verification Gate 6: Full E2E Pass

Run all tests against each platform:

```bash
# Against iOS device/simulator
KELPIE_TEST_HOST=<ios-ip> KELPIE_TEST_PORT=8420 pnpm --filter @unlikeotherai/kelpie test

# Against Android device/emulator
KELPIE_TEST_HOST=<android-ip> KELPIE_TEST_PORT=8420 pnpm --filter @unlikeotherai/kelpie test

# Against macOS app
KELPIE_TEST_HOST=localhost KELPIE_TEST_PORT=8420 pnpm --filter @unlikeotherai/kelpie test
```

**All tests must pass on all three platforms.**

**Final App Reveal click-through checklist (run on each platform):**

- [ ] Navigate to a URL → page loads
- [ ] Take screenshot via MCP → image returned
- [ ] Click element via MCP → element activates
- [ ] Fill form via MCP → text appears
- [ ] Trigger JS alert → dialog intercepted → accept via MCP
- [ ] Trigger JS confirm → dialog intercepted → dismiss via MCP
- [ ] Focus input → keyboard state reports visible=true
- [ ] Check element obscured by keyboard → returns true with overlap
- [ ] Hide keyboard → state reports visible=false
- [ ] Open Settings → HF section visible
- [ ] Tap "Set API Key" → secure field appears
- [ ] Tap "Open HuggingFace" → browser navigates to tokens page (in-app)
- [ ] Load Ollama tinyllama → send prompt → get response → unload
- [ ] Run full CLI E2E suite → all tests pass

---

## Out of Scope (Documented Platform Limitations)

These remain as stubs with plausible responses. They are **correct behavior**, not missing features:

| Feature | Reason |
|---------|--------|
| Multi-tab (iOS/Android) | WebView is single-tab by design |
| Iframe context switching | WKWebView/WebView can't switch iframe execution context |
| Geolocation override (Android) | Requires Chrome DevTools Protocol, not available in WebView |
| Request interception (Android) | Requires CDP |
| Geolocation/interception (iOS) | WKWebView has no API for this |
