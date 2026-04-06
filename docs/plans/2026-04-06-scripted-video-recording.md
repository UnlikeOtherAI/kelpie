# Scripted Video Recording via MCP

**Date:** 2026-04-06
**Status:** Draft

---

## Problem

Kelpie needs a way for an LLM (or any MCP client) to script a walkthrough of a website as a sequence of timed actions — click here, wait, scroll there, type this — with visual feedback overlays (touch indicators, commentary text, swipe trails, element highlights) so the result can be screen-recorded into a polished demo video. Today, an LLM can already do this by calling individual MCP tools one at a time, but that approach has no timing control between actions, no way to show commentary, and no swipe gesture support.

## What Already Exists

| Capability | Status | Notes |
|---|---|---|
| Click overlay (blue dot + ripple) | Ready | `showTouchIndicator(x:y:)` — 36px dot, 600ms ripple, auto-cleanup |
| Toast overlay (commentary) | Internal only | `showToast(_ message:)` — bottom-center, 3s, backdrop blur. Not exposed as API |
| `click` / `tap` | Ready | Selector-based and coordinate-based. Both trigger the touch overlay |
| `fill` / `type` | Ready | `type` supports per-character delay |
| `scroll` / `scroll2` / `scrollToY` | Ready | Fixed, resolution-aware, and absolute variants |
| `navigate` / `back` / `forward` | Ready | Standard navigation |
| `wait-for-element` / `wait-for-navigation` | Ready | Synchronization primitives |
| `screenshot` / `screenshot-annotated` | Ready | Viewport and full-page capture |
| `evaluate` | Ready | Arbitrary JS execution — escape hatch for anything missing |
| Viewport presets / orientation / resize | Ready | `set-viewport-preset`, `resize-viewport`, `set-orientation` |
| Fullscreen | Ready | `set-fullscreen` |
| Swipe gesture | Missing | No endpoint, no visual overlay |
| Element highlight | Missing | No way to draw attention circles around elements |
| Batch action playback | Missing | Each command is a separate HTTP request |
| Recording mode (UI lockdown) | Missing | No way to hide chrome and lock controls |

---

## Design

### What Gets Recorded

The recording frame is **the web content viewport only**. Nothing else. The only things visible in the frame are:

1. **The web page** — whatever is rendered in the WebView at the current viewport size
2. **Touch indicators** — the blue dot + ripple (or custom color) injected via CSS into the WebView
3. **Commentary overlays** — text pills injected via CSS into the WebView
4. **Swipe trails** — animated dot trails injected via CSS into the WebView
5. **Element highlights** — colored circles/rings injected via CSS into the WebView
6. **The stop button** — small floating button, top-right corner

All overlays are CSS elements injected into the WebView's DOM at z-index `2147483647` with `pointer-events: none`. They are part of the WebView's rendered content, so they appear in any screen recording of the viewport. No native UI layers (URL bar, toolbar, tab strip, status bar, window chrome) are visible.

The stop button is the one exception — it is a native UI element (NSButton on macOS, UIButton on iOS) floating above the WebView. It will appear in full-screen recordings but not in WebView-only window captures. It is intentionally small and semi-transparent (0.3 opacity, 1.0 on hover/touch) so it is unobtrusive in recordings.

### Recording Mode

When a script starts playing, the app enters **recording mode**.

**What recording mode does:**

1. **Viewport-only display.** On macOS, the URL bar, toolbar, tab strip, and window chrome are hidden. On iOS, the status bar area and any Kelpie UI overlays (URL bar, bottom toolbar) are hidden. What remains is a clean rectangle of web content at the current viewport size. If the user has selected a viewport preset (e.g. "iPhone 15 Pro — 393x852"), the recording frame is exactly that size — not the full window.

2. **All controls disabled.** No clicking URL bar, no swiping between tabs, no opening settings, no keyboard shortcuts. The user cannot interfere with the scripted playback. The only interactive element is the stop button.

3. **Stop button.** A single floating stop button appears in the top-right corner of the recording frame. Minimal — a small red circle or square (the universal "stop recording" icon). Tapping it aborts the script, exits recording mode, and restores all UI. On macOS, this is an AppKit `NSButton` (per the WebView hit-testing rule in AGENTS.md).

4. **API requests blocked.** While recording, the HTTP server rejects all requests except `POST /v1/abort-script` and `POST /v1/get-script-status`. Response: `{ "success": false, "error": { "code": "RECORDING_IN_PROGRESS", "message": "Script is playing. Call abort-script to stop." } }`.

5. **Auto-rotation locked.** On iOS, auto-rotation is disabled during recording to prevent the OS from rotating the viewport mid-script. Orientation changes are only possible via the `set-orientation` script action.

6. **Exit.** Recording mode ends when: (a) the script finishes all actions, (b) the user taps the stop button, or (c) `abort-script` is called via API. On exit, all UI is restored to its pre-recording state and auto-rotation is re-enabled.

**Before recording:** The user should enable Do Not Disturb / Focus mode to prevent notifications, phone calls, and system banners from overlaying the recording. Kelpie cannot suppress system-level interruptions. On macOS, the app enters fullscreen automatically when recording starts (hides the menu bar and Dock). On iOS, the Home indicator and Dynamic Island cannot be hidden — they are system elements.

### New MCP Tool: `kelpie_play_script`

A single MCP tool that accepts an ordered array of actions with timing. The device enters recording mode, executes actions sequentially with overlays, and returns a summary when done.

**Why a single tool instead of calling existing tools in sequence?**
- Timing precision: the LLM round-trip between tool calls adds 1-5s of uncontrolled latency. A script runs locally on the device with exact delays.
- Atomicity: the entire walkthrough is one operation. If the LLM disconnects mid-sequence, the script still finishes.
- Commentary: individual tools have no way to show explanatory text.
- Recording mode: UI lockdown only makes sense as a bracketed operation (enter on start, exit on finish).

### HTTP Endpoint

```
POST /v1/play-script
```

### Request Schema

```json
{
  "actions": [
    { "action": "navigate", "url": "https://example.com" },
    { "action": "wait", "ms": 2000 },
    { "action": "commentary", "text": "This is the homepage", "position": "bottom", "durationMs": 0 },
    { "action": "wait", "ms": 3000 },
    { "action": "hide-commentary" },
    { "action": "highlight", "selector": "#login-btn", "color": "#ff0000", "thickness": 3, "animation": "draw", "durationMs": 2000 },
    { "action": "wait", "ms": 1500 },
    { "action": "click", "selector": "#login-btn" },
    { "action": "wait", "ms": 1000 },
    { "action": "fill", "selector": "#email", "value": "demo@example.com", "mode": "instant" },
    { "action": "fill", "selector": "#password", "value": "hunter2", "mode": "typing", "delay": 80 },
    { "action": "tap", "x": 195, "y": 420 },
    { "action": "swipe", "from": { "x": 200, "y": 600 }, "to": { "x": 200, "y": 200 }, "durationMs": 400 },
    { "action": "screenshot" },
    { "action": "commentary", "text": "Done!", "durationMs": 5000 }
  ],
  "overlayColor": "#3B82F6",
  "defaultWaitBetweenActions": 500,
  "continueOnError": false
}
```

### Top-Level Options

| Field | Type | Default | Description |
|---|---|---|---|
| `actions` | array | required | Ordered list of actions to execute |
| `overlayColor` | string | `"#3B82F6"` | Default color for touch indicators and swipe trails (CSS color value). Can be overridden per-action |
| `defaultWaitBetweenActions` | number | `0` | Implicit pause (ms) inserted *after* each action completes and *before* the next action starts, unless the next action is `wait`, `wait-for-element`, or `wait-for-navigation`. For blocking actions (`fill` with `mode: "typing"`, `swipe`), the pause starts after the action finishes |
| `continueOnError` | boolean | `false` | If `true`, skip failed actions and continue. If `false`, stop on first error |

### Overlay Color

The `overlayColor` at the top level sets the default color for all touch indicators (dot + ripple) and swipe trails. The existing hardcoded blue (`rgba(59,130,246,0.7)` / `#3B82F6`) becomes the default.

Individual actions can override the color:

```json
{ "action": "click", "selector": "#danger-btn", "color": "#EF4444" }
{ "action": "tap", "x": 200, "y": 400, "color": "#10B981" }
{ "action": "swipe", "from": {"x":200,"y":600}, "to": {"x":200,"y":200}, "color": "#F59E0B" }
```

The `color` parameter on an action takes precedence over `overlayColor`, which takes precedence over the default blue.

---

## Complete Action Catalogue

Every action the script supports. Parameters marked with `?` are optional.

### Navigation

| Action | Parameters | Description |
|---|---|---|
| `navigate` | `url` | Navigate to a URL. Waits for page load before proceeding |
| `back` | — | Go back in browser history |
| `forward` | — | Go forward in browser history |
| `reload` | — | Reload the current page |

**Overlay:** None for navigation actions.

### Interaction

| Action | Parameters | Description |
|---|---|---|
| `click` | `selector`, `timeout?`, `color?` | Click an element by CSS selector |
| `tap` | `x`, `y`, `color?` | Tap at specific viewport coordinates |
| `fill` | `selector`, `value`, `timeout?`, `mode?`, `delay?`, `color?` | Fill a form field (see modes below) |
| `type` | `selector?`, `text`, `delay?`, `color?` | Type text character by character |
| `select-option` | `selector`, `value`, `color?` | Select a `<select>` dropdown option |
| `check` | `selector`, `color?` | Check a checkbox or radio button |
| `uncheck` | `selector`, `color?` | Uncheck a checkbox |
| `swipe` | `from: {x,y}`, `to: {x,y}`, `durationMs?`, `steps?`, `color?` | Swipe gesture between two points |

**Overlay:** Touch indicator (dot + ripple in the active color) shown at the interaction point for `click`, `tap`, `fill`, `type`, `select-option`, `check`, `uncheck`. Swipe trail (dot + comet tail in the active color) shown for `swipe`.

#### Fill Modes

The `fill` action supports two modes via the `mode` parameter:

| Mode | Behavior | Use case |
|---|---|---|
| `"instant"` (default) | Clears the field and sets the value immediately. Same as existing `fill` endpoint behavior | Background form population, not visually interesting |
| `"typing"` | Clears the field, then types the value character by character with a delay between keystrokes | Demo videos where you want to show the text appearing naturally |

When `mode` is `"typing"`:
- `delay` (ms, default `50`) controls the speed between characters
- Fires `keydown`, `keypress`, `input`, and `keyup` events for each character — same as the existing `type` endpoint
- The touch indicator appears on the field when typing starts
- The script **blocks until typing finishes** before moving to the next action — so `delay` directly affects the pacing of the recording

Speed guidelines for `delay`:
- `30` — fast typist, good for long text you want to breeze through
- `50` — natural human speed (default)
- `80-100` — deliberate, easy to follow in a video
- `150+` — dramatic, one character at a time

### Scrolling

| Action | Parameters | Description |
|---|---|---|
| `scroll` | `deltaX?`, `deltaY` | Scroll by a fixed pixel amount |
| `scroll2` | `selector`, `position?`, `maxScrolls?` | Resolution-aware scroll to make an element visible |
| `scroll-to-top` | — | Scroll to the top of the page |
| `scroll-to-bottom` | — | Scroll to the bottom of the page |
| `scroll-to-y` | `y`, `x?` | Scroll to an absolute pixel offset |

**Overlay:** None. The content movement is the visual feedback.

### Viewport & Display

These actions let a script change the device frame mid-recording. Useful for showing the same page at different screen sizes.

| Action | Parameters | Description |
|---|---|---|
| `set-viewport-preset` | `presetId`, `orientation?` | Switch to a named viewport preset (e.g. `"compact-base"`, `"standard-pro"`) |
| `resize-viewport` | `width`, `height` | Set an arbitrary viewport size in CSS pixels |
| `set-orientation` | `orientation` | Set `"portrait"` or `"landscape"` |
| `set-fullscreen` | `enabled` | Enter or exit fullscreen mode |
| `reset-viewport` | — | Reset viewport to the device's native size |

**Overlay:** None. The viewport change is instantly visible.

**Recording frame resizes with viewport.** If a script action changes the viewport (e.g. from 393x852 to 428x926), the recording frame resizes accordingly. The clean viewport-only rectangle grows or shrinks — the viewer sees the page reflow at the new size. On macOS, the window auto-resizes to fit the new viewport (since the app is in fullscreen during recording, the viewport is centered in the screen with a black or blurred surround if smaller than the display).

### Wait / Sync

| Action | Parameters | Description |
|---|---|---|
| `wait` | `ms` | Pause for a fixed duration. The viewport stays visible — use this to let the viewer read commentary or observe a state |
| `wait-for-element` | `selector`, `timeout?`, `state?` | Wait for a DOM element to reach a state (`"attached"`, `"visible"`, `"hidden"`) |
| `wait-for-navigation` | `timeout?` | Wait for a page navigation/load to complete |

**Overlay:** None.

**Important: `commentary` does not block.** The `commentary` action injects the overlay and immediately proceeds to the next action. To keep the commentary visible for a specific time before the next action, follow it with a `wait`:

```json
{ "action": "commentary", "text": "Watch what happens next", "durationMs": 0 },
{ "action": "wait", "ms": 3000 },
{ "action": "click", "selector": "#btn" }
```

Here the commentary appears, the script pauses 3 seconds (viewer reads the text), then the click happens. The commentary stays on screen (because `durationMs: 0` = persistent) until a `hide-commentary` or next `commentary` replaces it.

To show a self-dismissing message without blocking:

```json
{ "action": "commentary", "text": "Loading...", "durationMs": 2000 },
{ "action": "wait-for-element", "selector": ".loaded", "timeout": 5000 }
```

The commentary auto-fades after 2 seconds while the script independently waits for the element.

### Commentary

| Action | Parameters | Description |
|---|---|---|
| `commentary` | `text`, `durationMs?`, `position?` | Show a text overlay on the viewport |
| `hide-commentary` | — | Immediately dismiss the active commentary overlay |

**Parameters for `commentary`:**
- `text` (required): the message to display
- `durationMs` (optional, default `3000`): how long the text stays on screen. `0` = persistent until `hide-commentary` or the next `commentary` replaces it
- `position` (optional, default `"bottom"`): `"top"` | `"bottom"` | `"center"`

**`durationMs` vs `wait`:** These are independent. `durationMs` controls when the overlay auto-fades. `wait` controls when the next action starts. Use `durationMs: 0` + `wait` for "show text, pause for viewer, then continue". Use a specific `durationMs` without `wait` for fire-and-forget messages that fade on their own while other actions proceed.

**Visual design:** Dark backdrop-blurred pill, white text, max-width 390px, 16px border radius. Positioned per the `position` parameter. Fades in immediately, fades out over 300ms when dismissed or when `durationMs` expires. Each new `commentary` action replaces the previous one (no stacking).

### Element Highlight

Draw a colored circle or ring around a DOM element to call attention to it.

| Action | Parameters | Description |
|---|---|---|
| `highlight` | `selector`, `color?`, `thickness?`, `padding?`, `animation?`, `durationMs?` | Draw a highlight ring around an element |
| `hide-highlight` | — | Immediately dismiss the active highlight |

**Parameters for `highlight`:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `selector` | string | required | CSS selector for the element to highlight |
| `color` | string | `"#EF4444"` (red) | CSS color for the ring. Any valid CSS color: hex, rgb(), hsl(), named colors |
| `thickness` | number | `2` | Border width in CSS pixels |
| `padding` | number | `4` | Space between the element's bounding box and the ring, in CSS pixels |
| `animation` | string | `"appear"` | `"appear"` = instant, `"draw"` = animated stroke drawing effect |
| `durationMs` | number | `2000` | How long the highlight stays visible. `0` = persistent until `hide-highlight` |

**Animation modes:**

- **`"appear"`** — the ring appears instantly (opacity 0 to 1 over 150ms). Simple and clean.
- **`"draw"`** — the ring draws itself stroke-by-stroke using a CSS `stroke-dashoffset` animation. The line starts at the top of the element and traces the full perimeter. Drawing duration is 600ms. The ring then stays visible for the remaining `durationMs`.

**Stacking:** Each new `highlight` action replaces the previous one (same as commentary — no stacking). Use `hide-highlight` for explicit dismissal.

**Implementation:** The highlight is a `<div>` (for `"appear"`) or `<svg>` (for `"draw"`) injected into the WebView DOM. It is positioned using `position: absolute` relative to the document (calculated from `getBoundingClientRect()` + `window.scrollX/scrollY`), so it scrolls with the page content. Uses `border-radius: 8px` for a rounded rectangle shape (not a circle — elements are rectangular). Same z-index and `pointer-events: none` pattern as other overlays.

**Limitation:** Highlights on `position: fixed` or `position: sticky` elements will drift when the page scrolls, because the highlight is document-anchored while the element is viewport-anchored. For fixed elements, use `tap` coordinates with a manual `evaluate` to draw a custom overlay, or avoid scrolling while the highlight is active.

**Example:**

```json
{ "action": "highlight", "selector": "#submit-btn", "color": "#EF4444", "thickness": 3, "animation": "draw", "durationMs": 3000 },
{ "action": "wait", "ms": 1500 },
{ "action": "commentary", "text": "Click the submit button", "durationMs": 0 },
{ "action": "wait", "ms": 1500 },
{ "action": "click", "selector": "#submit-btn" }
```

The highlight draws around the button (600ms draw animation), pauses 1.5s, commentary appears, pauses another 1.5s, then the click fires. The highlight auto-fades at 3s total.

### Screenshots & Evaluation

| Action | Parameters | Description |
|---|---|---|
| `screenshot` | `fullPage?`, `format?`, `quality?` | Capture a screenshot during playback. Saved to a temp file; file path returned in the response `screenshots` array |
| `evaluate` | `script` | Execute arbitrary JavaScript. Return value is captured but not displayed |

**Overlay:** None.

### Dialogs

If a page triggers `alert()`, `confirm()`, or `prompt()` during playback, it blocks execution. Include dialog handling actions in scripts that might hit dialogs.

| Action | Parameters | Description |
|---|---|---|
| `handle-dialog` | `action` (`"accept"` or `"dismiss"`), `text?` | Handle the current dialog |
| `set-dialog-auto-handler` | `action` (`"accept"`, `"dismiss"`, or `"none"`) | Auto-handle all dialogs during playback. Set before navigating to pages that show dialogs |

**Overlay:** None.

**Recommendation:** Use `set-dialog-auto-handler` with `"accept"` or `"dismiss"` at the start of scripts that may encounter dialogs. This prevents execution from blocking.

### Tabs

| Action | Parameters | Description |
|---|---|---|
| `new-tab` | `url?` | Open a new tab, optionally navigating to a URL |
| `switch-tab` | `index` | Switch to a tab by index |
| `close-tab` | `index?` | Close a tab (defaults to current) |

**Overlay:** None. Tab switching is visible as a content change.

---

## Swipe Gesture (New Endpoint)

Available both as a script action and as a standalone endpoint.

**Endpoint:** `POST /v1/swipe`
**MCP tool:** `kelpie_swipe`

```json
{
  "from": { "x": 200, "y": 600 },
  "to": { "x": 200, "y": 200 },
  "durationMs": 400,
  "steps": 20,
  "color": "#3B82F6"
}
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `from` | `{x, y}` | required | Start point in viewport coordinates |
| `to` | `{x, y}` | required | End point in viewport coordinates |
| `durationMs` | number | `400` | Duration of the swipe animation |
| `steps` | number | `20` | Number of intermediate `pointermove` events. More = smoother |
| `color` | string | `"#3B82F6"` | Color for the finger dot and trail |

**Implementation:**

Dispatches a sequence of pointer events from `from` to `to` over `durationMs`:
1. `pointerdown` at `from`
2. `pointermove` at interpolated positions (`steps` count, evenly spaced over `durationMs`)
3. `pointerup` at `to`

**Limitation:** Synthetic pointer events dispatched via JavaScript may not trigger browser-native gesture handlers (e.g., pull-to-refresh, native carousel swipe, iOS rubber-band scroll). The swipe action is reliable for: (a) showing a visual swipe trail overlay, (b) triggering JS-based touch/pointer event listeners on the page, (c) interacting with JS-driven carousels and sliders. It may not trigger native browser scroll momentum or OS-level gestures. For native scrolling, use the `scroll` or `scroll2` actions instead.

**Swipe trail overlay:**

- A **finger dot** (36px circle in the active color) appears at `from` and translates along the path to `to` over `durationMs`
- A **fading trail** of 6-8 smaller dots (12px, opacity decreasing from 0.6 to 0.1) follows behind the finger dot, each slightly delayed — creates a comet-tail effect
- Everything auto-cleans after `durationMs + 400ms`
- Same z-index (`2147483647`) and `pointer-events: none` pattern as the existing touch indicator

**Response:**

```json
{
  "success": true,
  "from": { "x": 200, "y": 600 },
  "to": { "x": 200, "y": 200 },
  "durationMs": 400,
  "direction": "up"
}
```

The `direction` field is informational — classified from the delta:

| Delta | Direction |
|---|---|
| `dy <= -100, abs(dx) < 50` | `"up"` |
| `dy >= 100, abs(dx) < 50` | `"down"` |
| `dx <= -100, abs(dy) < 50` | `"left"` |
| `dx >= 100, abs(dy) < 50` | `"right"` |
| else | `"diagonal"` |

---

## Element Highlight (New Endpoint)

Available both as a script action and as a standalone endpoint.

**Endpoint:** `POST /v1/highlight`
**MCP tool:** `kelpie_highlight`

```json
{
  "selector": "#submit-btn",
  "color": "#EF4444",
  "thickness": 3,
  "padding": 4,
  "animation": "draw",
  "durationMs": 2000
}
```

**Endpoint:** `POST /v1/hide-highlight`
**MCP tool:** `kelpie_hide_highlight`

---

## Commentary Overlay (New Endpoint)

Available both as a script action and as a standalone endpoint.

**Endpoint:** `POST /v1/show-commentary`
**MCP tool:** `kelpie_show_commentary`

```json
{
  "text": "Now we'll fill in the login form",
  "durationMs": 3000,
  "position": "bottom"
}
```

**Endpoint:** `POST /v1/hide-commentary`
**MCP tool:** `kelpie_hide_commentary`

---

## Script Playback Response

All indices are **0-based** (matching the actions array).

Screenshots are saved to temporary files (not returned as inline base64), matching the existing CLI screenshot convention. The response contains file paths.

### Success

```json
{
  "success": true,
  "actionsExecuted": 12,
  "totalDurationMs": 14320,
  "errors": [],
  "screenshots": [
    { "index": 8, "file": "/tmp/kelpie-script-8.png", "width": 390, "height": 844 }
  ]
}
```

### Failure (continueOnError: false)

Execution stops at the failing action. The top-level `error` field contains the fatal error (matching the standard API error shape). The `errors` array provides the same data with index context.

```json
{
  "success": false,
  "actionsExecuted": 5,
  "totalDurationMs": 6200,
  "error": { "code": "ELEMENT_NOT_FOUND", "message": "No element matching '#nonexistent'" },
  "errors": [
    {
      "index": 5,
      "action": "click",
      "error": { "code": "ELEMENT_NOT_FOUND", "message": "No element matching '#nonexistent'" }
    }
  ],
  "screenshots": []
}
```

### Failure (continueOnError: true)

Skips failed actions, continues to the end:

```json
{
  "success": false,
  "actionsExecuted": 12,
  "actionsSucceeded": 11,
  "totalDurationMs": 14320,
  "error": { "code": "SCRIPT_PARTIAL_FAILURE", "message": "1 of 12 actions failed" },
  "errors": [
    {
      "index": 5,
      "action": "click",
      "error": { "code": "ELEMENT_NOT_FOUND", "message": "No element matching '#nonexistent'" },
      "skipped": true
    }
  ],
  "screenshots": [
    { "index": 8, "file": "/tmp/kelpie-script-8.png", "width": 390, "height": 844 }
  ]
}
```

### Abort (user tapped stop or API abort)

```json
{
  "success": false,
  "aborted": true,
  "actionsExecuted": 7,
  "totalDurationMs": 8100,
  "errors": [],
  "screenshots": []
}
```

---

## Abort / Status Endpoints

**Endpoint:** `POST /v1/abort-script`
**MCP tool:** `kelpie_abort_script`

Stops the currently running script. Exits recording mode. Returns the partial result.

**Endpoint:** `POST /v1/get-script-status`
**MCP tool:** `kelpie_get_script_status`

Returns the current playback state without interrupting:

```json
{
  "playing": true,
  "currentAction": 7,
  "totalActions": 15,
  "elapsedMs": 8100
}
```

Or when idle:

```json
{
  "playing": false
}
```

---

## Script Examples

### Complete Product Demo

Demonstrates: navigation, commentary, highlights, form filling (instant + typing), clicking, scrolling, swiping, custom colors, and screenshots.

```json
{
  "overlayColor": "#3B82F6",
  "defaultWaitBetweenActions": 800,
  "actions": [
    { "action": "commentary", "text": "Let's walk through MyApp", "position": "center", "durationMs": 0 },
    { "action": "wait", "ms": 2500 },
    { "action": "hide-commentary" },
    { "action": "navigate", "url": "https://myapp.com" },
    { "action": "wait-for-element", "selector": ".hero", "timeout": 5000 },
    { "action": "commentary", "text": "This is the homepage", "durationMs": 0 },
    { "action": "wait", "ms": 2000 },
    { "action": "hide-commentary" },

    { "action": "highlight", "selector": ".signup-btn", "animation": "draw", "durationMs": 3000 },
    { "action": "commentary", "text": "Let's create an account", "durationMs": 0 },
    { "action": "wait", "ms": 2000 },
    { "action": "click", "selector": ".signup-btn" },
    { "action": "wait-for-navigation" },
    { "action": "hide-commentary" },

    { "action": "commentary", "text": "Fill in the registration form", "durationMs": 0 },
    { "action": "fill", "selector": "#name", "value": "Jane Smith", "mode": "typing", "delay": 60 },
    { "action": "fill", "selector": "#email", "value": "jane@example.com", "mode": "typing", "delay": 50 },
    { "action": "fill", "selector": "#password", "value": "securepass123", "mode": "typing", "delay": 80 },
    { "action": "check", "selector": "#agree-terms" },

    { "action": "commentary", "text": "All fields filled, submitting..." },
    { "action": "highlight", "selector": "#submit", "color": "#10B981", "thickness": 3, "animation": "draw", "durationMs": 2000 },
    { "action": "wait", "ms": 1000 },
    { "action": "click", "selector": "#submit" },
    { "action": "wait-for-navigation" },

    { "action": "commentary", "text": "Account created! Let's scroll down", "durationMs": 0 },
    { "action": "wait", "ms": 1500 },
    { "action": "swipe", "from": { "x": 200, "y": 700 }, "to": { "x": 200, "y": 200 }, "durationMs": 500 },
    { "action": "wait", "ms": 1000 },
    { "action": "screenshot" },

    { "action": "commentary", "text": "That's it! Thanks for watching", "position": "center", "durationMs": 0 },
    { "action": "wait", "ms": 3000 }
  ]
}
```

### Multi-Page Form with Typing Speed Variation

Shows how `delay` controls pacing per field, and how `mode: "instant"` vs `mode: "typing"` changes the visual.

```json
{
  "defaultWaitBetweenActions": 600,
  "actions": [
    { "action": "navigate", "url": "https://app.example.com/apply" },
    { "action": "wait-for-element", "selector": "form" },

    { "action": "commentary", "text": "Quick fields -- filled instantly", "durationMs": 0 },
    { "action": "fill", "selector": "#first-name", "value": "Alice", "mode": "instant" },
    { "action": "fill", "selector": "#last-name", "value": "Johnson", "mode": "instant" },
    { "action": "wait", "ms": 1000 },

    { "action": "commentary", "text": "Email -- typed at natural speed", "durationMs": 0 },
    { "action": "fill", "selector": "#email", "value": "alice.johnson@company.com", "mode": "typing", "delay": 50 },

    { "action": "commentary", "text": "Bio -- slow and deliberate", "durationMs": 0 },
    { "action": "fill", "selector": "#bio", "value": "Senior engineer with 10 years of experience building distributed systems.", "mode": "typing", "delay": 100 },

    { "action": "commentary", "text": "Credit card -- fast, nothing to see here", "durationMs": 0 },
    { "action": "fill", "selector": "#card-number", "value": "4242 4242 4242 4242", "mode": "typing", "delay": 30 },

    { "action": "hide-commentary" },
    { "action": "select-option", "selector": "#country", "value": "us" },
    { "action": "highlight", "selector": "#submit", "animation": "draw", "durationMs": 2000 },
    { "action": "wait", "ms": 1000 },
    { "action": "click", "selector": "#submit" },
    { "action": "wait-for-navigation" },
    { "action": "screenshot" }
  ]
}
```

### Highlight + Commentary Walkthrough

Shows the draw animation and appear animation, with different colors and thicknesses.

```json
{
  "defaultWaitBetweenActions": 500,
  "actions": [
    { "action": "navigate", "url": "https://dashboard.example.com" },
    { "action": "wait-for-element", "selector": ".dashboard" },

    { "action": "commentary", "text": "Let's explore the dashboard", "position": "top", "durationMs": 0 },
    { "action": "wait", "ms": 2000 },

    { "action": "highlight", "selector": ".revenue-card", "color": "#10B981", "thickness": 3, "animation": "draw", "durationMs": 0 },
    { "action": "commentary", "text": "Revenue is up 23% this quarter", "durationMs": 0 },
    { "action": "wait", "ms": 3000 },
    { "action": "hide-highlight" },

    { "action": "highlight", "selector": ".alert-banner", "color": "#EF4444", "thickness": 4, "animation": "appear", "durationMs": 0 },
    { "action": "commentary", "text": "But we have 3 critical alerts to address", "durationMs": 0 },
    { "action": "wait", "ms": 3000 },
    { "action": "hide-highlight" },

    { "action": "highlight", "selector": ".alerts-link", "color": "#F59E0B", "thickness": 2, "animation": "draw", "durationMs": 3000 },
    { "action": "commentary", "text": "Let's click into the alerts page", "durationMs": 0 },
    { "action": "wait", "ms": 1500 },
    { "action": "click", "selector": ".alerts-link" },
    { "action": "wait-for-navigation" },
    { "action": "hide-commentary" }
  ]
}
```

### Mobile Gesture Demo

```json
{
  "overlayColor": "#8B5CF6",
  "defaultWaitBetweenActions": 600,
  "actions": [
    { "action": "navigate", "url": "https://photos.example.com/gallery" },
    { "action": "wait-for-element", "selector": ".gallery-grid" },
    { "action": "commentary", "text": "Swipe through the photo gallery", "position": "top", "durationMs": 0 },
    { "action": "wait", "ms": 1500 },
    { "action": "swipe", "from": { "x": 350, "y": 400 }, "to": { "x": 50, "y": 400 }, "durationMs": 350 },
    { "action": "swipe", "from": { "x": 350, "y": 400 }, "to": { "x": 50, "y": 400 }, "durationMs": 350 },
    { "action": "commentary", "text": "Pull down to refresh", "durationMs": 0 },
    { "action": "wait", "ms": 1000 },
    { "action": "swipe", "from": { "x": 200, "y": 100 }, "to": { "x": 200, "y": 500 }, "durationMs": 600 },
    { "action": "wait-for-element", "selector": ".refresh-complete", "timeout": 5000 },
    { "action": "commentary", "text": "Content refreshed!", "durationMs": 2000 },
    { "action": "wait", "ms": 2500 }
  ]
}
```

### Responsive Demo (Viewport Changes)

Shows the same page at different screen sizes within one recording.

```json
{
  "defaultWaitBetweenActions": 1000,
  "actions": [
    { "action": "navigate", "url": "https://myapp.com" },
    { "action": "wait-for-element", "selector": ".hero" },

    { "action": "commentary", "text": "iPhone 15 Pro view", "position": "top", "durationMs": 0 },
    { "action": "set-viewport-preset", "presetId": "compact-base" },
    { "action": "wait", "ms": 2000 },
    { "action": "screenshot" },

    { "action": "commentary", "text": "iPad Pro view", "position": "top", "durationMs": 0 },
    { "action": "set-viewport-preset", "presetId": "ipad-pro-13" },
    { "action": "wait", "ms": 2000 },
    { "action": "screenshot" },

    { "action": "commentary", "text": "Custom 1440px desktop", "position": "top", "durationMs": 0 },
    { "action": "resize-viewport", "width": 1440, "height": 900 },
    { "action": "wait", "ms": 2000 },
    { "action": "screenshot" },

    { "action": "commentary", "text": "Landscape mode", "position": "top", "durationMs": 0 },
    { "action": "set-orientation", "orientation": "landscape" },
    { "action": "wait", "ms": 2000 },
    { "action": "screenshot" },

    { "action": "hide-commentary" },
    { "action": "wait", "ms": 500 }
  ]
}
```

### Multi-Device Recording (via CLI group)

```
kelpie group script demo.json
```

All devices execute the same script simultaneously. Since each device runs the timing locally, they stay in sync regardless of network jitter. Useful for recording comparison videos (same walkthrough on iPhone, iPad, and Android side by side).

---

## LLM Integration

An LLM building a script does not need special knowledge. The action types and parameters match the existing MCP tools — just wrapped in an array. Typical flow:

1. LLM calls `kelpie_screenshot_annotated` to see the current page
2. LLM builds a script based on what it sees
3. LLM calls `kelpie_play_script` with the action array
4. Device enters recording mode, executes all actions, exits recording mode
5. LLM gets back the result with any screenshots captured during playback
6. If the script failed, the LLM reads the error, adjusts, and retries

The LLM can also build scripts incrementally — run a short script, check the result screenshots, then build the next segment.

---

## Implementation Scope

### Native (iOS + macOS — platform parity)

1. **`RecordingModeManager`** — manages the recording mode lifecycle. On enter: hides all chrome (URL bar, toolbar, tab strip, status bar), constrains the window/view to the viewport rect, shows the stop button, sets a flag that the HTTP server checks to reject non-script requests. On exit: restores everything.

2. **Stop button (macOS):** `NSButton` subclass via `NSViewRepresentable` (per the WebView hit-testing rule). Red circle/square icon, positioned top-right of the viewport rect, semi-transparent until hovered. On click: calls `ScriptHandler.abort()`.

3. **Stop button (iOS):** Small floating `UIButton` pinned to the top-right safe area. Same red icon. On tap: calls `ScriptHandler.abort()`.

4. **`ScriptHandler`** — accepts the `play-script` request, spawns playback as a detached `Task`, and immediately returns a continuation that the Router can suspend on. The playback Task iterates the action array, delegates to existing handlers, and manages timing via `Task.sleep`. The Router must allow `abort-script` and `get-script-status` to resolve on separate request handlers while the play-script continuation is suspended — this requires the Router to dispatch these two endpoints before checking the recording-mode gate. The `play-script` HTTP response is sent only when the playback Task completes (or is aborted). Tracks execution state for abort/status queries. Exits recording mode on completion.

5. **`SwipeHandler`** — new handler file. Dispatches pointer event sequences via `evaluateJavaScript`. Shows swipe trail overlay with configurable color. Exposes `POST /v1/swipe`.

6. **`HighlightHandler`** — new handler file. Injects positioned `<div>` or `<svg>` overlay matching an element's bounding rect. Supports appear and draw animations. Exposes `POST /v1/highlight` and `POST /v1/hide-highlight`.

7. **`CommentaryHandler`** — new handler file. Wraps existing `showToast` with position/duration parameters. Exposes `POST /v1/show-commentary` and `POST /v1/hide-commentary`.

8. **`fill` mode extension** — modify existing `InteractionHandler.fill()` to accept `mode` and `delay` parameters. When `mode: "typing"`, delegate to the existing `type` implementation internally.

9. **Overlay color support** — modify `showTouchIndicator` in `HandlerContext.swift` to accept a color parameter instead of hardcoded blue. Default remains `#3B82F6`.

10. **Toast CSS updates** — minor edits in `HandlerContext.swift` to support position parameter and persistent commentary mode.

### CLI

11. **`packages/cli/src/commands/script.ts`** — new CLI command: `kelpie script <file.json> [--device]`. Reads a JSON file and posts to `/v1/play-script`. Also `kelpie swipe`, `kelpie highlight`, and `kelpie commentary` for standalone use.

12. **MCP server registration** — add `kelpie_play_script`, `kelpie_swipe`, `kelpie_highlight`, `kelpie_hide_highlight`, `kelpie_show_commentary`, `kelpie_hide_commentary`, `kelpie_abort_script`, `kelpie_get_script_status` to the MCP tool list.

### Docs

13. Update `docs/api/core.md` — add swipe, highlight, commentary, script, recording mode sections.
14. Update `docs/api/README.md` — add new MCP tool names to the table. Add `RECORDING_IN_PROGRESS` to the error codes table.
15. Update `docs/functionality.md` — describe the scripted recording feature.
16. Update `docs/cli.md` — document the `script`, `swipe`, `highlight`, `commentary` commands.

---

## Out of Scope (for now)

- **Pinch/zoom gestures** — would need multi-touch event dispatch. Low priority.
- **Built-in screen capture** — the actual video recording is done by the OS (iOS screen recording, macOS screenshot toolbar, OBS). Kelpie provides the choreography, not the capture. The viewport-only recording mode gives you a clean frame to record.
- **Audio narration sync** — the `ai-record` endpoint exists but wiring it to script timing adds complexity. Commentary text overlays are sufficient.
- **Conditional logic / loops** — this is a playback format, not a programming language. The LLM handles conditionals between script calls.
- **Android** — will need the same handlers. Deferred because Android's handler infrastructure (HandlerContext, Router, overlay injection pattern) doesn't exist yet — it needs to be built first as a separate effort. This is a documented exception to the platform parity rule. Tracked for follow-up once iOS + macOS ship.

---

## Cross-Provider Review

Reviewed by Claude (superpowers:code-reviewer), Codex (gpt-5.4), and Gemini (via max). All three reviews completed.

**Findings addressed:**

| Source | Severity | Finding | Resolution |
|---|---|---|---|
| Claude #3 | Critical | Highlight breaks on scroll — `getBoundingClientRect()` is viewport-relative | Changed to document-relative positioning (`+ scrollX/scrollY`). Documented limitation for fixed/sticky elements |
| Claude #7 | Critical | HTTP server blocks during 60s script — Router is single-threaded | ScriptHandler spawns a detached Task and suspends on a continuation. Router dispatches `abort-script` and `get-script-status` before the recording-mode gate |
| Claude #4 | Important | `typingDelay` vs `delay` naming inconsistency | Renamed to `delay` everywhere for consistency with existing `type` endpoint |
| Claude #5 | Important | `defaultWaitBetweenActions` underspecified for blocking actions | Clarified: pause is inserted *after* action completes, *before* next starts. Does not apply when next action is wait/sync |
| Claude #8 | Important | System overlays, auto-rotation, macOS menu bar not addressed | Added: auto-rotation locked during recording, Do Not Disturb recommendation, macOS enters fullscreen automatically |
| Claude #9 | Important | Highlight stacking behavior undefined | Defined: new highlight replaces old (same as commentary) |
| Claude #10 | Important | Stop button in/out of recording unclear | Clarified: native element, semi-transparent (0.3 opacity), appears in full-screen recordings but not WebView-only captures |
| Claude #11 | Low | `RECORDING_IN_PROGRESS` error code missing from README update list | Added to doc update item 14 |
| Claude #12 | Low | Swipe direction thresholds use strict inequality (dead zone) | Fixed to `<=` / `>=` |
| Claude #15 | Low | Viewport resize beyond window bounds | Added: macOS window auto-resizes, viewport centered in fullscreen |
| Codex #4 | High | `play-script` error response uses `errors` array, breaks `{ error: {} }` convention | Added top-level `error` field alongside `errors` array. Fatal errors use standard shape; `SCRIPT_PARTIAL_FAILURE` for continueOnError mode |
| Codex #5 | High | Swipe synthetic JS events may not trigger native gesture handlers | Added explicit limitation note: swipe is for JS listeners and visual overlay, not native scroll. Use `scroll`/`scroll2` for native scrolling |
| Codex #7 | Medium | Dialog handling missing — JS dialogs would block execution | Added `handle-dialog` and `set-dialog-auto-handler` to action catalogue |
| Codex #8 | Medium | Screenshots return inline base64, inconsistent with CLI convention | Changed to save to temp files and return file paths |
| Codex #10 | Low | Index fields ambiguous (0-based vs 1-based) | Specified: all indices are 0-based |
| Gemini #1 | High | Stop button is native but doc says "viewport-only, no native UI" | Already addressed by Claude #10 — clarified the stop button is an intentional exception |
| Gemini #2 | High | Error codes not in README table | Already addressed — `RECORDING_IN_PROGRESS` and `SCRIPT_PARTIAL_FAILURE` added to doc update list |

**Findings dismissed:**

| Source | Finding | Reason |
|---|---|---|
| Claude #1 | Android parity violation | Android handler infrastructure doesn't exist yet. Added documented exception with follow-up note |
| Claude #6 | API lockdown too aggressive | Intentional. Recording is a dedicated mode with precise timing |
| Claude #13 | Screenshot params incomplete in table | Already listed — consistent with other tables |
| Claude #14 | Tab switch no visual indicator | By design. Commentary handles context |
| Codex #1 | Android parity | Same as Claude #1 — documented exception |
| Codex #2 | Stop button contradicts viewport-only rule | Same as Claude #10 / Gemini #1 — addressed |
| Codex #3 | Timing model imprecise | Already addressed by Claude #5 clarification |
| Codex #6 | UI lockdown doesn't cover OS interruptions | Already addressed by Claude #8 — Do Not Disturb recommendation |
| Codex #9 | Viewport actions not supported on all devices | These actions already return `PLATFORM_NOT_SUPPORTED` on unsupported devices. Scripts using them on phones will get errors (handled by continueOnError or documented as desktop-only scripts) |
