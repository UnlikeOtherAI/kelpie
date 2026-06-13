# Issue 67 Coordinate Diagnostics

## Problem

Kelpie already exposes the individual MCP primitives needed for most coordinate debugging: device discovery, navigation, screenshot, evaluation, tap, swipe, scroll, viewport metadata, and tab selection. The remaining gap is a single deterministic diagnostic primitive that lets an agent run a coordinate oracle workflow and receive one structured result with:

- viewport and page metadata
- requested input coordinates
- `document.elementFromPoint()` / `elementsFromPoint()` samples
- delivered pointer/mouse event targets and coordinates
- optional page-side setup/export expressions
- screenshot metadata and image payload when requested
- pass/fail classification fields for regression tests

Issue #67 asks for native/input-subsystem actions. The current iOS WKWebView public API cannot inject trusted OS touch events into web content, and Kelpie's existing cross-platform tap/swipe path dispatches browser-visible coordinate events from the page bridge. Android can dispatch `MotionEvent`s to `WebView`, and macOS can synthesize AppKit events in some renderer modes, but those paths are not equivalent across iOS, macOS, and Android. This change should therefore expose the input source explicitly instead of pretending all platforms can produce trusted native events today.

## Goals

- Add one additive HTTP endpoint, `POST /v1/coordinate-diagnostics`.
- Add one MCP tool, `kelpie_coordinate_diagnostics`.
- Keep the request/response shape mirrored across iOS, macOS, and Android.
- Compose existing primitives in-page where possible instead of creating a parallel automation stack.
- Return honest input provenance with `inputSource: "page-synthesized"` for the initial implementation.
- Return input capability metadata so clients do not assume trusted native input is available.
- Support macOS `tabId`.
- Include screenshot payload and mapping metadata when `captureScreenshot` is true.
- Update API docs, MCP tool lists, shared TypeScript types, and tests.

## Non-Goals

- Do not replace existing `tap`, `swipe`, `scroll`, `evaluate`, or `screenshot` endpoints.
- Do not claim trusted OS-level input on platforms where it is not implemented.
- Do not add video or trace capture in this issue.
- Do not add cross-origin iframe inspection beyond what `evaluate` can already reach.
- Do not make the coordinate overlay style configurable here; that is tracked separately in issue #69.

## Endpoint

### Request

```json
{
  "points": [
    { "label": "button-center", "x": 120, "y": 240 }
  ],
  "actions": [
    { "type": "tap", "label": "tap-button", "x": 120, "y": 240, "expectedSelector": "#pay" },
    {
      "type": "swipe",
      "label": "scroll-card",
      "from": { "x": 220, "y": 620 },
      "to": { "x": 220, "y": 260 },
      "durationMs": 350,
      "steps": 12
    },
    { "type": "scroll", "label": "window-scroll", "deltaX": 0, "deltaY": 300 }
  ],
  "setupExpression": "window.__hitTargetOracle?.reset?.()",
  "exportExpression": "window.__hitTargetOracle?.exportLog?.()",
  "captureScreenshot": true,
  "screenshotFormat": "png",
  "screenshotResolution": "viewport",
  "tabId": "optional-macos-tab-id"
}
```

Fields:

- `points`: optional static sample points in viewport CSS pixels.
- `actions`: optional ordered coordinate actions. Supported types are `tap`, `swipe`, and `scroll`.
- `expectedSelector`: optional CSS selector on points and actions. When supplied, diagnostics classify whether the sampled or delivered target matches the selector or is contained by it.
- `setupExpression`: optional JavaScript evaluated before diagnostics start.
- `exportExpression`: optional JavaScript evaluated after actions complete.
- `captureScreenshot`: optional boolean, default false.
- `screenshotFormat`: optional `png` or `jpeg`, default `png`.
- `screenshotResolution`: optional `viewport` or `native`, default `viewport`.
- `tabId`: optional macOS tab selection.

### Response

```json
{
  "success": true,
  "coordinateSpace": "viewport-css-pixels",
  "inputSource": "page-synthesized",
  "inputCapabilities": {
    "trustedNativeInput": false,
    "availableInputSources": ["page-synthesized"]
  },
  "viewport": {
    "width": 390,
    "height": 844,
    "scrollX": 0,
    "scrollY": 128,
    "devicePixelRatio": 3,
    "visualViewport": {
      "offsetLeft": 0,
      "offsetTop": 0,
      "pageLeft": 0,
      "pageTop": 128,
      "width": 390,
      "height": 744,
      "scale": 1
    }
  },
  "setupResult": null,
  "points": [
    {
      "label": "button-center",
      "x": 120,
      "y": 240,
      "pageX": 120,
      "pageY": 368,
      "elementFromPoint": {
        "tag": "button",
        "id": "pay",
        "classes": ["primary"],
        "text": "Pay",
        "rect": { "x": 80, "y": 220, "width": 120, "height": 44 }
      },
      "elementsFromPoint": [],
      "expectedSelector": "#pay",
      "matchesExpected": true
    }
  ],
  "actions": [
    {
      "type": "tap",
      "label": "tap-button",
      "accepted": true,
      "input": { "x": 120, "y": 240, "pageX": 120, "pageY": 368 },
      "before": {},
      "after": {},
      "events": [
        {
          "type": "click",
          "target": { "tag": "button", "id": "pay", "text": "Pay" },
          "clientX": 120,
          "clientY": 240,
          "pageX": 120,
          "pageY": 368,
          "timeStamp": 12345
        }
      ]
    }
  ],
  "eventLog": [],
  "exportResult": {},
  "screenshot": {
    "image": "...base64...",
    "width": 390,
    "height": 844,
    "format": "png",
    "resolution": "viewport",
    "coordinateSpace": "viewport-css-pixels",
    "viewportWidth": 390,
    "viewportHeight": 844,
    "devicePixelRatio": 3,
    "imageScaleX": 1,
    "imageScaleY": 1
  },
  "classification": {
    "status": "needs-review",
    "reason": "No expected selector was supplied"
  }
}
```

## Classification

The endpoint should not infer application-specific correctness without an oracle. It will return:

- `pass` when every action has `expectedSelector` and the observed final click/pointer target matches.
- `fail` when at least one expected selector is provided and does not match the observed event or hit-test target.
- `needs-review` when no expected selector is supplied or the page does not expose enough event information.

`expectedSelector` is optional on point and action records. Matching is performed in page JS against the sampled or delivered event target. A match succeeds when:

- the target itself matches `expectedSelector`
- the target is contained by an element matching `expectedSelector`
- an element matching `expectedSelector` contains the target

If `expectedSelector` is invalid, the endpoint returns `INVALID_PARAMS`.

## Implementation Plan

### Shared and CLI

- Add shared request/response interfaces in `packages/shared/src/coordinate-diagnostics-types.ts`.
  - `CoordinateDiagnosticsRequest`
  - `CoordinateDiagnosticsResponse`
  - `CoordinateDiagnosticsPoint`
  - `CoordinateDiagnosticsAction`
  - `CoordinateDiagnosticsPointSample`
  - `CoordinateDiagnosticsEvent`
  - `CoordinateDiagnosticsViewport`
- Add `coordinate-diagnostics` to `BrowserMcpToolNames`, `HttpMethodToMcpTool`, and tests.
- Add MCP schema in `packages/cli/src/mcp/tools.ts`.
- Keep forwarding generic through the existing MCP server.

### Native Apps

- Add `CoordinateDiagnosticsHandler` on iOS, macOS, and Android.
- Register the handler next to existing interaction/screenshot handlers.
- Use a shared page-side script shape per platform:
  - install temporary capture listeners
  - sample viewport metrics
  - sample `elementFromPoint()` / `elementsFromPoint()`
  - dispatch tap/swipe/scroll action sequences
  - collect event records
  - evaluate optional setup/export expressions
- Reuse each platform's existing screenshot payload helper when `captureScreenshot` is true.
- Return `INVALID_PARAMS` for malformed points, actions, selectors, formats, or resolutions.
- Return tab-specific errors on macOS through the existing tab error helpers.
- Return `EVAL_ERROR` for setup/export or diagnostic script failures.
- Return `SCREENSHOT_FAILED` when screenshot capture is requested and fails.

### Docs

- Document `POST /v1/coordinate-diagnostics` in `docs/api/core.md`.
- Add the HTTP/MCP mapping to `docs/api/README.md`.
- Update `docs/functionality.md` to describe the coordinate oracle workflow.

## Risks

- Duplicated diagnostic JS across Swift and Kotlin can drift. Keep it compact and response-shape focused.
- Screenshot capture inside the handler must use the same metadata helpers as `screenshot` to avoid another coordinate-space variant.
- Consumers may assume `inputSource` is native. The docs and MCP description must explicitly say the current input source is page-synthesized.

## Verification

- `pnpm lint`
- `pnpm build`
- `pnpm test`
- `make lint-swift`
- `cd apps/android && ./gradlew build`

## Cross-Provider Review

Review attempts:

- `claude -p` started but produced no output after multiple polls. The stuck timeout process was terminated.
- `gemini -p` failed with quota exhaustion.
- `opencode run` completed a review using `deepseek-ai/DeepSeek-V3.2`.

Findings and adjudication:

1. `drag` would drift from the existing `swipe` endpoint shape.
   - Accepted. The endpoint will use action type `swipe` with `from`, `to`, `durationMs`, and `steps`.
2. The plan did not define `expectedSelector` in the request schema.
   - Accepted. `expectedSelector` is now explicit on points and actions, with matching rules.
3. `inputSource: "page-synthesized"` alone could hide platform differences.
   - Accepted. The response will also include `inputCapabilities`, starting with `trustedNativeInput: false` and `availableInputSources: ["page-synthesized"]`.
4. `visualViewport` and event log shapes were not typed.
   - Accepted. Shared interfaces will define viewport, point sample, action result, and event records.
5. The response duplicates viewport data inside screenshot metadata.
   - Partially accepted. Screenshot metadata intentionally keeps the existing `screenshot` response shape. The top-level viewport describes the page state; screenshot metadata describes the returned image mapping.
6. Error cases were underspecified.
   - Accepted. The plan now names `INVALID_PARAMS`, tab errors, `EVAL_ERROR`, and `SCREENSHOT_FAILED`.
7. Performance risk for dense swipe sampling.
   - Accepted in implementation: only sample `before` and `after` for each action, while event listeners capture delivered pointer/mouse events. The endpoint will not sample every swipe interpolation step.
