# Adversarial Review: Scripted Video Recording

**Document:** `docs/plans/2026-04-06-scripted-video-recording.md`
**Reviewer:** Adversarial (same-provider)
**Severity scale:** HIGH = blocks merge, MEDIUM = must address before ship, LOW = should fix

---

## FINDING 1 — Stop button design contradicts overlay spec [HIGH]

**Location:** Recording Mode §3 vs §6

The recording mode spec says:

> All overlays are CSS elements injected into the WebView's DOM ... with `pointer-events: none`.

But the stop button (Step 3) must be tappable by the user. A CSS element with `pointer-events: none` is not interactive.

The implementation section says macOS uses an `NSButton` subclass via `NSViewRepresentable` — which correctly solves the hit-testing problem — but this is a native AppKit view, not a CSS overlay. So the stop button is not actually "part of the WebView's rendered content" (Step 6 says it is) and it doesn't actually follow the `pointer-events: none` pattern.

Two concrete contradictions:
1. CSS overlay with `pointer-events: none` cannot be a stop button.
2. Native AppKit view is not "in the WebView's rendered content" and won't appear in a viewport-only screen recording.

**Fix required:** Either (a) the stop button is a native overlay that does NOT appear in the viewport recording (acceptable — it's outside the frame), or (b) the stop button is a CSS element inside the WebView with `pointer-events: auto` (possible, but then it blocks clicks on underlying content). Pick one and update both the Recording Mode section and the Implementation Scope.

---

## FINDING 2 — Error codes in the doc are not in the error table [HIGH]

**Location:** Throughout doc, e.g. scroll-to-y response: `MISSING_PARAM`, swipe implementation: `EVAL_ERROR`, Recording Mode §4: `RECORDING_IN_PROGRESS`

`MISSING_PARAM` and `EVAL_ERROR` do not appear in the [README.md error codes table](docs/api/README.md). `RECORDING_IN_PROGRESS` is defined nowhere in the existing codebase.

Per the platform support matrix and README, error codes are a fixed contract. Adding undocumented codes breaks the error table contract. Every code the doc introduces must be added to the table before implementation.

List of undocumented codes:
- `RECORDING_IN_PROGRESS` — used in blocking response during recording mode
- `MISSING_PARAM` — referenced in scroll-to-y response, but not in the error table
- `EVAL_ERROR` — referenced in swipe implementation, but not in the error table (existing docs use `WEBVIEW_ERROR` for JS evaluation failures)

---

## FINDING 3 — `defaultWaitBetweenActions` double-waits on successful sync actions [MEDIUM]

**Location:** Top-Level Options §, Timing section

The rule states:

> Implicit pause ... inserted between actions, unless the next action is `wait`, `wait-for-element`, or `wait-for-navigation`.

This means:
1. `wait-for-element` succeeds in 500ms.
2. `defaultWaitBetweenActions: 500` then fires — viewer watches 500ms of nothing before next action.

The intent of the rule is unclear. If the rule means "don't insert extra wait after a sync primitive already paused", then `wait-for-element` that resolves in 500ms followed by a 500ms implicit wait = 1s total pause, not 500ms. The doc does not acknowledge this. An LLM building a script has no way to predict the combined behavior.

**Either:** remove the exclusion rule entirely (the script author controls all pacing explicitly), or redefine `defaultWaitBetweenActions` as "pause inserted only between non-timing, non-sync actions" (which means the exclusion is implicit by nature, not by rule).

---

## FINDING 4 — `highlight` with `draw` animation has no scroll-off-screen strategy [MEDIUM]

**Location:** Element Highlight §, Animation modes

The `draw` animation traces the element's bounding box over 600ms. If the element is near the bottom of the viewport and the highlight is `durationMs: 0` (persistent), what happens when the script scrolls and the element moves off-screen?

No behavior is specified. Options:
- The highlight stays fixed at its last known position (visually wrong — hovers over wrong content).
- The highlight is removed when the element leaves the viewport (breaks the `durationMs: 0` promise).
- The highlight moves with the element (requires continuous tracking via scroll events and `getBoundingClientRect` polling — adds implementation complexity the doc doesn't mention).

None of these are addressed. For `durationMs: 0` highlights, this is a real scenario: any long-page walkthrough that scrolls will eventually trigger it.

---

## FINDING 5 — `fill` mode `"typing"` / `type` action key event fidelity on iOS WebKit is unspecified [MEDIUM]

**Location:** Fill Modes §, Interaction table

The doc says `mode: "typing"` fires `keydown`, `keypress`, `input`, and `keyup` events for each character — matching the existing `type` endpoint. But the existing `type` endpoint on iOS is already implemented, and the platform support matrix says keyboard simulation is Native on iOS.

The iOS platform support matrix says: `Keyboard simulation — Native`. Native keyboard input on iOS WKWebView uses `UIKeyCommand` or JavaScript injection. The `keypress` event was removed from the DOM events spec years ago (deprecated in DOM4, removed from UAs). If the highlight fires `keypress`, modern WebKit won't process it.

This is a spec error: `keypress` should not be listed as an event fired by `fill` mode `"typing"` on iOS. It's also inconsistent with the existing `type` endpoint's documented behavior (which the doc says it matches — but the existing `type` doc in core.md does not list individual key events).

---

## FINDING 6 — `highlight` `getBoundingClientRect` coordinate system mismatch [MEDIUM]

**Location:** Element Highlight §, Implementation

The spec says the overlay is "absolutely-positioned `<div>` ... positioned to match the element's `getBoundingClientRect()` plus padding."

`getBoundingClientRect()` returns coordinates relative to the **viewport** (top-left of visible viewport). CSS `position: absolute` is relative to the nearest **positioned ancestor** (not the viewport). If the WebView's body/html has `position: relative`, this works. If it doesn't (or has a non-zero offset), the highlight will be mispositioned.

No instruction is given to ensure the injection target has `position: relative` on its container. On some pages, the overlay will appear offset from the element.

---

## FINDING 7 — `fill` `timeout` parameter absent from standalone endpoint [MEDIUM]

**Location:** Interaction table

The script action catalogue lists `fill` with `timeout?` as an optional parameter. The standalone `fill` endpoint in core.md also has `timeout` (optional, default 5000ms).

But the new `swipe` endpoint does NOT have a `timeout` parameter, while `click`, `tap`, and `fill` all do. There's no stated reason for this divergence. If a swipe fails because the WebView is not in a gesture-ready state, there is no timeout mechanism to fail fast rather than hang.

Either `swipe` should get a `timeout` parameter, or the doc should explain why swipe is exempt from the timeout pattern.

---

## FINDING 8 — macOS keyboard shortcuts not blocked during recording [MEDIUM]

**Location:** Recording Mode §2

"All controls disabled. No clicking URL bar, no swiping between tabs, no opening settings, no keyboard shortcuts."

What keyboard shortcuts are blocked on macOS? `⌘N` (new tab), `⌘W` (close tab), `⌘,` (settings), `⌘L` (focus URL bar), `⌃⌘F` (fullscreen toggle) — all of these can interfere with a scripted walkthrough. The spec does not say how keyboard shortcuts are suppressed.

On iOS there is no keyboard, so this is a macOS-only problem. The spec says "All controls disabled" without defining what that means on each platform. The implementation scope mentions native AppKit stop button on macOS but does not mention keyboard intercept.

---

## FINDING 9 — Recording mode on iOS during app backgrounding not specified [MEDIUM]

**Location:** Recording Mode §5

"Recording mode ends when: (a) the script finishes all actions, (b) the user taps the stop button, or (c) `abort-script` is called via API."

What happens when iOS sends the app to background (phone call, user switches app, low memory)? The script is mid-execution. The spec does not address:
- Does the script pause and resume when the app returns to foreground?
- Does the script abort?
- If the script continues in background, does the HTTP server still accept `abort-script`?

iOS is aggressive about suspending background apps. The HTTP server may go down, breaking the `abort-script` path.

---

## FINDING 10 — `screenshot` action documentation inconsistency [LOW]

**Location:** Complete Action Catalogue, Screenshots & Evaluation table

The table lists `screenshot` with `fullPage?`, `format?`, `quality?` parameters. The standalone `screenshot` endpoint in core.md documents exactly these parameters.

However, the examples in the doc (lines 571-572, 696-697, etc.) use `screenshot` without any parameters, relying on defaults. This is fine, but the doc never explicitly states what the defaults are for `format` and `quality` in the action catalogue, even though the standalone endpoint defines them (`format: "png"`, `quality: 80` for jpeg only). These should be consistent.

---

## FINDING 11 — `direction` field in swipe response is inconsistent with existing scroll response conventions [LOW]

**Location:** Swipe Gesture §, Response

The `scroll` endpoint returns `scrollX` and `scrollY`. The `scroll2` endpoint returns `scrollsPerformed`, `element`, `viewport`. None of the scroll actions return a `direction` string.

The `swipe` endpoint response adds a `direction` field (`"up"`, `"down"`, `"left"`, `"right"`, `"diagonal"`). This is a new response field pattern for a movement action. If this is intentional (informational, not blocking), it should be noted that it diverges from scroll response conventions.

---

## FINDING 12 — `highlight` draw animation start point is ambiguous in SVG coordinates [LOW]

**Location:** Element Highlight §, Animation modes

"The line starts at the top of the element and traces the full perimeter."

SVG coordinate system: y increases downward. "Top of the element" in SVG means y = `rect.top`. The path trace direction (clockwise vs counterclockwise) is not specified. For a rectangular element this doesn't matter much, but it matters for the `stroke-dashoffset` animation direction (forward vs backward reveal).

The spec should define `pathDirection: "clockwise"` and confirm the `stroke-dashoffset` animation goes from `pathLength` → `0` (full draw visible at end) or `0` → `pathLength` (fades in then draws).

---

## FINDING 13 — `set-viewport-preset` on iOS requires iPad, not iPhone [LOW]

**Location:** Viewport & Display table, and platform support matrix in README.md

The platform support matrix says `set-viewport-preset` is `Native (iPad only)`. Phones return no preset support.

The doc's Viewport & Display table includes `set-viewport-preset` without noting this limitation. An LLM building a script that runs on iPhone could include a `set-viewport-preset` action and get `PLATFORM_NOT_SUPPORTED` with no indication in the doc that this is expected on phones.

---

## FINDING 14 — `evaluate` result not surfaced in script response [LOW]

**Location:** Screenshots & Evaluation table

The `evaluate` action executes JS and captures the return value. The script playback response schema only includes `actionsExecuted`, `totalDurationMs`, `errors`, and `screenshots`. The `evaluate` return value is dropped.

If the LLM uses `evaluate` to extract state mid-script (e.g., checking a variable value, reading form data), it has no way to retrieve it. This was presumably intentional (keep the response simple), but it's a limitation the doc should note.

---

## Summary

| # | Finding | Severity |
|---|---|---|
| 1 | Stop button contradicts `pointer-events: none` rule | HIGH |
| 2 | Undocumented error codes (`RECORDING_IN_PROGRESS`, `MISSING_PARAM`, `EVAL_ERROR`) | HIGH |
| 3 | `defaultWaitBetweenActions` double-waits after successful sync actions | MEDIUM |
| 4 | `highlight` draw animation has no scroll-off-screen strategy | MEDIUM |
| 5 | `keypress` event in `fill` mode `"typing"` is deprecated and wrong for iOS WebKit | MEDIUM |
| 6 | `getBoundingClientRect` vs CSS positioning coordinate mismatch | MEDIUM |
| 7 | `swipe` missing `timeout` parameter unlike `click`/`tap`/`fill` | MEDIUM |
| 8 | macOS keyboard shortcuts during recording not specified | MEDIUM |
| 9 | iOS app backgrounding during script not specified | MEDIUM |
| 10 | `screenshot` action defaults not explicitly stated | LOW |
| 11 | `swipe` response `direction` field inconsistent with scroll convention | LOW |
| 12 | `draw` animation SVG path direction not specified | LOW |
| 13 | `set-viewport-preset` not flagged as iPad-only on iOS | LOW |
| 14 | `evaluate` result not surfaced in script response | LOW |

**Verdict:** The doc cannot be implemented as-is. Findings 1 and 2 are blockers — the stop button contradiction and undocumented error codes would introduce bugs or broken contracts. Findings 3–9 need resolution before implementation. Findings 10–14 are cleanup items for the doc.