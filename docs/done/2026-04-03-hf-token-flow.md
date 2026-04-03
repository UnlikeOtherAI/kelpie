# Hugging Face Token Flow — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When a native model download fails due to missing Hugging Face auth, navigate the browser to the HF tokens page and surface a "Set Hugging Face Token" button in the AI panel that opens a popover with a text field.

**Architecture:** Store the HF token in UserDefaults (no Keychain per project rules). Pass it as an `Authorization: Bearer` header on download requests. On auth failure, navigate the browser to the HF token settings page. The token button lives in the NATIVE section header of the Models tab in AIChatPanel.

**Tech Stack:** SwiftUI, URLSession, UserDefaults

---

### Task 1: Store and expose the HF token on AIState

**Files:**
- Modify: `apps/macos/Mollotov/AI/AIState.swift`

**Step 1: Add the token property**

Add a published `@AppStorage` property for the token and a setter method. Place these right after the existing published properties (after `lastError` on line 74):

```swift
@AppStorage("huggingFaceToken") var huggingFaceToken: String = ""
```

**Step 2: Add a callback for auth-failure navigation**

AIState needs a way to tell the browser to navigate. Add a closure property after `lastError`:

```swift
var onAuthFailureNavigate: ((URL) -> Void)?
```

**Step 3: Commit**

```
git add apps/macos/Mollotov/AI/AIState.swift
git commit -m "feat(macos): add HF token storage and auth-failure navigation hook"
```

---

### Task 2: Send the token on download requests and detect auth failure

**Files:**
- Modify: `apps/macos/Mollotov/AI/AIState.swift` — `downloadNativeModel` method (lines 165-214)

**Step 1: Replace the bare download call with an authenticated URLRequest**

In `downloadNativeModel`, replace:

```swift
let (downloadedURL, _) = try await URLSession.shared.download(from: model.downloadURL)
```

with:

```swift
var request = URLRequest(url: model.downloadURL)
if !self.huggingFaceToken.isEmpty {
    request.setValue("Bearer \(self.huggingFaceToken)", forHTTPHeaderField: "Authorization")
}
let (downloadedURL, response) = try await URLSession.shared.download(for: request)

// Detect auth failure — HF returns 401 or a small error body
if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
    try? FileManager.default.removeItem(at: downloadedURL)
    await MainActor.run {
        self.lastError = self.huggingFaceToken.isEmpty
            ? "This model requires a Hugging Face token. Tap \"Set HF Token\" in the Models tab."
            : "Hugging Face rejected your token. Check it on the settings page."
        self.onAuthFailureNavigate?(
            URL(string: "https://huggingface.co/settings/tokens")!
        )
    }
    return
}
```

**Step 2: Also validate the downloaded file isn't a tiny error response**

After the move-to-final step (`try self.fileManager.moveItem(at: tempURL, to: finalURL)`), add a size check:

```swift
let attrs = try self.fileManager.attributesOfItem(atPath: finalURL.path)
let fileSize = (attrs[.size] as? Int64) ?? 0
if fileSize < 1_000_000 {
    // Likely an HTML error page, not a real GGUF
    let snippet = (try? String(contentsOf: finalURL, encoding: .utf8))?.prefix(200) ?? ""
    if snippet.contains("Invalid") || snippet.contains("Access") || snippet.contains("login") {
        try self.fileManager.removeItem(at: finalURL)
        await MainActor.run {
            self.lastError = "Download failed — Hugging Face returned an auth error. Set your token and try again."
            self.onAuthFailureNavigate?(
                URL(string: "https://huggingface.co/settings/tokens")!
            )
        }
        return
    }
}
```

**Step 3: Commit**

```
git add apps/macos/Mollotov/AI/AIState.swift
git commit -m "feat(macos): authenticate HF downloads and detect auth failures"
```

---

### Task 3: Wire the navigation callback in BrowserView

**Files:**
- Modify: `apps/macos/Mollotov/Views/BrowserView.swift`

**Step 1: Set the callback in onAppear**

In the `.onAppear` block (around line 213), after `aiState.configure(...)`, add:

```swift
aiState.onAuthFailureNavigate = { [weak serverState] url in
    serverState?.handlerContext.load(url: url)
}
```

**Step 2: Commit**

```
git add apps/macos/Mollotov/Views/BrowserView.swift
git commit -m "feat(macos): navigate browser to HF tokens page on auth failure"
```

---

### Task 4: Add the "Set HF Token" button and popover to the Models tab

**Files:**
- Modify: `apps/macos/Mollotov/Views/AIChatPanel.swift`

**Step 1: Add a `@State` for the popover**

In `AIChatPanel`, add a state variable:

```swift
@State private var showHFTokenPopover = false
```

**Step 2: Add the token button in the NATIVE section header**

In `modelsTab`, change the NATIVE header from:

```swift
Text("NATIVE")
    .font(.system(size: 11, weight: .bold))
    .foregroundStyle(.secondary)
```

to:

```swift
HStack(spacing: 6) {
    Text("NATIVE")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    Spacer()
    Button {
        showHFTokenPopover = true
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "key.fill")
                .font(.system(size: 9))
            Text("Set HF Token")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(aiState.huggingFaceToken.isEmpty ? .orange : .secondary)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("browser.ai.hf-token")
    .popover(isPresented: $showHFTokenPopover, arrowEdge: .bottom) {
        HFTokenPopover(token: $aiState.huggingFaceToken)
    }
}
```

**Step 3: Create the HFTokenPopover view**

Add this private struct at the bottom of AIChatPanel.swift (before the closing brace of the file, after `AIOllamaModelCardView`):

```swift
private struct HFTokenPopover: View {
    @Binding var token: String
    @State private var draft: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hugging Face Token")
                .font(.system(size: 12, weight: .semibold))

            Text("Some models require authentication. Generate a token at huggingface.co/settings/tokens and paste it here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("hf_...", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .accessibilityIdentifier("browser.ai.hf-token.input")

            HStack {
                if !token.isEmpty {
                    Button("Clear") {
                        token = ""
                        draft = ""
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                Button("Save") {
                    token = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("browser.ai.hf-token.save")
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear {
            draft = token
        }
    }
}
```

**Step 4: Commit**

```
git add apps/macos/Mollotov/Views/AIChatPanel.swift
git commit -m "feat(macos): add Set HF Token button and popover in AI panel"
```

---

### Task 5: Clean up the corrupt model file and verify end-to-end

**Step 1: Remove the existing corrupt model**

```bash
rm -rf ~/.mollotov/models/gemma-4-e2b-q4
```

**Step 2: Build and launch**

```bash
pkill -f Mollotov; sleep 1
cd apps/macos && xcodebuild -project Mollotov.xcodeproj -scheme Mollotov -configuration Debug build
open /tmp/gpteen-xcode2/Prod/Debug/Mollotov.app
```

**Step 3: Verify the flow**

1. Open AI panel (brain button in floating menu)
2. The "Set HF Token" button should appear orange (no token set) in the NATIVE header
3. Tap "Download" on Gemma 4 E2B Q4 — should fail and show error about needing a token
4. Browser should navigate to `https://huggingface.co/settings/tokens`
5. Tap "Set HF Token" — popover appears with SecureField
6. Paste a valid HF token and save
7. Tap "Download" again — download should proceed with auth header

**Step 4: Final commit and push**

```bash
git push
```

---

### Summary of changes

| File | Change |
|------|--------|
| `AIState.swift` | `huggingFaceToken` AppStorage property, `onAuthFailureNavigate` closure, authenticated download request, auth failure detection |
| `BrowserView.swift` | Wire `onAuthFailureNavigate` to navigate browser |
| `AIChatPanel.swift` | "Set HF Token" button in NATIVE header, `HFTokenPopover` with SecureField |
