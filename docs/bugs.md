# Kelpie Bug Tracker

Active bugs to fix. Move to done/ once resolved and reference the commit.

---

## BUG-001 — AI Models tab: section label and HF Token button (macOS)

**Status:** Fixed — see commit after this entry is filed.

**Location:** `apps/macos/Kelpie/Views/AIChatPanel.swift`

### Issue 1: Section labelled "NATIVE" instead of "HUGGING FACE"

The native on-device models section header reads `NATIVE`. The user sees this as the Hugging Face section (models sourced from HF, token needed for gated downloads). Label should read `HUGGING FACE`.

### Issue 2: "Set HF Token" button not clickable

The "Set HF Token" button inside the NATIVE/HUGGING FACE section header was a SwiftUI `Button` with `.buttonStyle(.plain)`. In any window that hosts a `WKWebView`, SwiftUI buttons lose the hit-test race to the WebView's first-responder claim — they silently stop receiving clicks.

**Fix applied:** Replaced the SwiftUI `Button` wrapper with the visual `HStack` plus an `AppKitInvisibleButton` overlay (the same `NSButton`-backed pattern used for tab switches and the chat send button throughout the panel). The popover anchor was moved onto the `HStack` and continues to work correctly.
