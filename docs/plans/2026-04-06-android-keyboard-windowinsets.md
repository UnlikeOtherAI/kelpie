# Android Keyboard State via WindowInsets

**Goal:** Replace the Android keyboard-state stub with real IME visibility and height reporting derived from `WindowInsets`.

**Scope:** Android only. This change updates the HTTP/MCP-facing keyboard state payload and the documented browser-management behavior.

## Design

### Observer ownership

- Add `KeyboardObserver` under `core/android/src/main/java/com/kelpie/browser/browser/`.
- The observer owns two values only:
  - `isVisible: Boolean`
  - `height: Int` in raw pixels
- The observer is constructed once from the activity root view and stored on `HandlerContext`.

### Insets source

- Use `ViewCompat.setOnApplyWindowInsetsListener(rootView)` to observe insets updates.
- Read:
  - `WindowInsetsCompat.Type.ime()`
  - `WindowInsetsCompat.Type.navigationBars()`
- Compute keyboard height as:
  - `max(ime.bottom - navigationBars.bottom, 0)`
- Treat the keyboard as visible only when that computed height is greater than zero.

### Handler changes

- `BrowserManagementHandler.getKeyboardState()` will stop returning hardcoded values.
- Response values:
  - `visible`: `ctx.keyboardObserver.isVisible`
  - `height`: keyboard height converted from px to dp using display density
  - `type`: keep `"default"`
  - `visibleViewport`: current screen size in dp with keyboard height subtracted from the height
- `showKeyboard()` and `hideKeyboard()` should return the observer-backed state instead of hardcoded booleans if they currently imply a fabricated size or visibility.

### Wiring

- `HandlerContext` gets a nullable `keyboardObserver` property.
- `MainActivity` remains the composition owner.
- The Compose UI is responsible for creating the observer once the root Android view is available, then storing it on `handlerContext`.

### Docs

- Update `docs/functionality.md` to state that Android reports real soft-keyboard visibility and viewport impact.
- Update `docs/api/browser.md` so the keyboard endpoints reflect observed state rather than implied state.

## Constraints

- Keep the implementation minimal.
- No polling, no global layout listeners, no duplicated keyboard math in multiple places.
- Do not change the public response shape beyond filling in the already documented fields with real values.

## Cross-Provider Review

- Reviewer: `max -p --bare` adversarial review
- Valid findings adopted:
  - Seed state from the current insets immediately instead of waiting for the first inset change.
  - Replace the stored observer whenever the Compose root view changes so `HandlerContext` does not keep stale view state.
- Weak findings rejected:
  - Rejecting `ime.bottom - navigationBars.bottom` is out of scope because this task explicitly requires that formula.
  - Rejecting `type = "default"` is out of scope because this task explicitly keeps that field fixed.
  - Listener clobbering is a low-risk note for future work; no other Android code currently installs an insets listener on the same root view.
