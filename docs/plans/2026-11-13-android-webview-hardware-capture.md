# Android WebView screenshot: hardware-composited capture proposal

Related upstream reports: [#213](https://github.com/UnlikeOtherAI/kelpie/issues/213) and [#207](https://github.com/UnlikeOtherAI/kelpie/issues/207).

## Problem

The Android `HandlerContext.captureScreenshotPayload()` path used `WebView.draw(Canvas(bitmap))`. This is WebView's software-draw route; it can miss hardware-composited pixels. On a Samsung Galaxy S24 Ultra a remote agent observed blank or stale captures despite successful semantic DOM actions, especially when the Android app was in the background. `active=true` does not mean the WebView has a visible surface.

## Proposed behavior

- Copy the foreground, attached, entirely visible WebView rectangle from the Activity's hardware-composited window with `PixelCopy.request`.
- Defer copying until `postVisualStateCallback` and a subsequent animation frame.
- Return the existing screenshot failure contract when a renderer has no usable surface, rather than a successful white bitmap.
- Preserve screenshot PNG/JPEG encoding, viewport/native scaling, metadata, and tab/authorization logic.
- Do not modify application task-removal policy, background activity rules, pairing, or tunnel-client configuration in this patch.

## Known limitations to validate on Android hardware

- `PixelCopy` is not a headless/background renderer; hidden or detached tabs will fail closed.
- Window-inset coordinates must be confirmed by an on-device screenshot with a distinct color pattern next to system bars and Kelpie controls.
- `Choreographer` ticks do not by themselves guarantee the latest WebView buffer has been committed; compare a time-stamped animated canvas to the visual result. If stale, wait for a real view draw / hardware commit signal before copying.
- Test intermediate cancellation / timeout before accepting the implementation as production-ready.
- Current `ScreenshotHandler.captureFullPagePayload()` uses the old `WebView.draw` tiling algorithm and is **not** repaired by this viewport-only change. It should be a separate follow-up with bounded, validated hardware captures.
- The source patch requires Gradle build, Kotlin ktlint and physical-device instrumentation before a PR may claim readiness. No Android SDK/device is available in the current coding sandbox.

## Suggested acceptance checks

1. Static HTML test page with a 384×720 viewport, colored quadrants, CSS gradients, text, and a canvas/WebGL element; compare expected RGB locations (allow compression tolerance for JPEG).
2. In foreground, compare screenshots before/after actual scroll and tab switch; verify nonzero `scrollY` where appropriate.
3. In background/zero-size/detached states, refuse with an error (never `success:true` for an invalid buffer).
4. Force repeated capture cancellations, rotation, and tab closure; confirm no bitmap leaks, no deadlock, and a succeeding next `tabs.list`.
5. Confirm iOS existing screenshot behavior is unchanged (no public API addition); coordinate metadata contract remains stable.
