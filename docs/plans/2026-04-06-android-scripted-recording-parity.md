# Android Scripted Recording Parity

## Goal

Bring Android to functional parity with the existing iOS scripted-recording surface introduced today:

- `swipe`
- `show-commentary` / `hide-commentary`
- `highlight` / `hide-highlight`
- `play-script` / `abort-script` / `get-script-status`
- recording-mode UI with a stop button and hidden browser chrome

Parity here also requires aligning the Android interaction semantics that script playback depends on:

- `tap` must accept viewport coordinates, not a selector
- `fill` must support `mode: "instant" | "typing"`
- `type` and `swipe` must stop promptly when script abort is requested
- click/fill/type/select/check/uncheck overlays must honor script-provided colors

## Existing Android Shape

Android is simpler than iOS:

- one `HandlerContext`
- one `Router`
- one `BrowserScreen`
- no recording gate
- no playback state
- no overlay handlers

That means the smallest clean port is:

1. add a Kotlin `ScriptPlaybackState`
2. thread that state through `HandlerContext`, `Router`, and `MainActivity`
3. add the missing handlers
4. gate the router during playback
5. hide Android chrome in `BrowserScreen` while playback is active

## Design

### 1. Shared Android playback state

Add `ScriptPlaybackState.kt` in `handlers/` with:

- in-memory session state
- `MutableStateFlow<Boolean>` for `isRecording`
- `start`, `requestAbort`, `isAbortRequested`
- `recordSuccess`, `recordFailure`, `addScreenshot`
- `statusResponse`, `finishSuccess`, `finishFatalFailure`, `finishAborted`
- `recordingError(method)` gate identical to iOS

Keep it lock-based and non-Compose-specific so handlers and UI can both use it.

### 2. Router gate

Update Android `Router` to match iOS behavior:

- store `scriptPlaybackState`
- reject all requests with HTTP 409 + `RECORDING_IN_PROGRESS` while a script is active
- allow only `abort-script` and `get-script-status`
- keep an escape hatch `bypassRecordingGate` for internally forwarded script actions
- return HTTP 200 for partial-failure or aborted script summaries, matching iOS

### 3. Android JS escape utility

Add `JSEscape.kt` so new handlers do not repeat ad hoc quoting.

Use it in all new scripted-recording handlers and in the Android interaction code paths touched by this parity work.

### 4. Overlay handlers

Add Android ports of the iOS handlers:

- `CommentaryHandler.kt`
- `HighlightHandler.kt`
- `SwipeHandler.kt`

These should inject ephemeral DOM overlays just like iOS:

- commentary: fixed pill, configurable position, optional persistence
- highlight: absolute overlay around `getBoundingClientRect` + `scrollX/Y`
- swipe: visible trail plus synthetic pointer events

### 5. Interaction parity fixes needed for script playback

Update Android `InteractionHandler.kt` to match iOS where script playback depends on it:

- `tap` consumes `x` and `y`
- `fill` supports `mode: "typing"` and delegates to `type`
- `type` checks script abort between characters
- interaction overlays accept optional `color`

This is not optional polish; without it Android script playback would accept the same script JSON as iOS and behave differently.

### 6. Script handler

Add Android `ScriptHandler.kt` closely following iOS:

- validate `actions`
- start playback session
- exit 3D mode before starting
- set recording mode on/off through a callback
- sequentially execute actions
- support `wait`, `wait-for-element`, `wait-for-navigation`
- forward all other actions through `router.handle(..., bypassRecordingGate = true)`
- normalize script-facing aliases:
  - `commentary` -> `show-commentary`
  - `evaluate.script` -> `evaluate.expression`
  - `handle-dialog.text` -> `handle-dialog.promptText`
- collect screenshots to temp files

### 7. Browser UI recording mode

Update Android `BrowserScreen.kt` to mirror iOS behavior:

- observe `scriptPlaybackState.isRecording`
- hide progress bar, URL bar, floating menu, and 3D controls while recording
- keep only the WebView plus a floating stop button visible
- disable pointer interaction on non-recording chrome because it is hidden rather than merely dimmed

Add `RecordingStopButton.kt` as a small Compose component.

### 8. Wiring

Update `MainActivity.kt` and `Router.kt`:

- instantiate one shared `ScriptPlaybackState`
- assign it to `handlerContext` and `router`
- register the new handlers
- pass the state into `BrowserScreen`

## Files

New:

- `core/android/src/main/java/com/kelpie/browser/handlers/JSEscape.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/CommentaryHandler.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/HighlightHandler.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/SwipeHandler.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/ScriptPlaybackState.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/ScriptHandler.kt`
- `core/android/src/main/java/com/kelpie/browser/ui/RecordingStopButton.kt`

Changed:

- `core/android/src/main/java/com/kelpie/browser/MainActivity.kt`
- `core/android/src/main/java/com/kelpie/browser/network/Router.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/HandlerContext.kt`
- `core/android/src/main/java/com/kelpie/browser/handlers/InteractionHandler.kt`
- `core/android/src/main/java/com/kelpie/browser/ui/BrowserScreen.kt`
- `docs/functionality.md`

## Risks

- Android `WebView.evaluateJavascript` returns JSON-encoded strings; the new handlers must stay consistent with existing decoding.
- The Compose UI must not create a second source of truth for recording state; `ScriptPlaybackState` owns it.
- Synthetic swipe events will only be reliable for JS-driven listeners, same limitation as iOS.
- Keeping the port minimal matters more than perfectly sharing code with iOS.

## Verification

- `./gradlew build`
- targeted manual inspection of Android route registration and recording UI state transitions

## Cross-Provider Review

Attempted twice via `max`, including one bounded run with `timeout 60`, but the tool produced no review output and exited on timeout in this environment.

Blocked external review concerns to keep in mind during implementation:

- Android `WebView.evaluateJavascript` returns doubly encoded strings; new handlers must stay consistent with existing decoding.
- Script playback must not rely on Compose-local state; one shared playback state object must own routing and UI visibility.
- Android interaction semantics must be aligned before script playback is considered parity, especially `tap` coordinates and `fill` typing mode.
