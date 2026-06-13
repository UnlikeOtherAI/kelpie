# macOS Handler Tab Targeting Pass-Through

## Scope

Update the specified macOS handler files plus `apps/macos/Kelpie/LLM/LLMHandler.swift` so requests can target a specific tab via `tabId`, using the tab-aware APIs already added to `HandlerContext`.

## Rules

- Do not modify `HandlerContext.swift`.
- Do not modify iOS or Android code.
- Only change the requested macOS handlers and `LLMHandler`.
- Keep behavior unchanged aside from resolving the correct tab and surfacing tab selection errors.

## Implementation Plan

1. In each targeted handler method that receives a request body and touches WebView state, add `let tabId = HandlerContext.tabId(from: body)` at the top of the closure or method body.
2. Pass `tabId: tabId` to all tab-aware `HandlerContext` calls:
   - `evaluateJS`
   - `evaluateJSReturningString`
   - `evaluateJSReturningJSON`
   - `evaluateJSReturningArray`
   - `takeSnapshot`
   - `showTouchIndicator`
   - `showTouchIndicatorForElement`
   - `screenshotViewportMetrics`
   - `screenshotPayload`
3. Replace direct `context.renderer` access in targeted handlers with `try context.resolveRenderer(tabId: tabId)` when the handler needs to validate or inspect the renderer for the requested tab.
4. In `catch` blocks for targeted handlers, add:

```swift
if let tabError = tabErrorResponse(from: error) { return tabError }
```

before the existing fallback error response.

## Known Constraints

- Some navigation and cookie helpers in `HandlerContext` are still active-tab convenience wrappers. In those handlers, tab support is limited to validating the requested tab before continuing with the existing behavior because no tab-aware helper exists there yet.
- Tab management endpoints in `BrowserManagementHandler` are intentionally out of scope.

## Cross-Provider Review

External adversarial review highlighted three points worth preserving during implementation:

1. Replacing `context.renderer` guards with `resolveRenderer(tabId:)` must happen everywhere a targeted handler branches on renderer existence or engine type. Leaving a single `context.renderer?.engineName` check behind would silently reintroduce active-tab behavior.
2. Handlers that already use `try?` for overlay or focus helpers still need the `tabId` pass-through even though they do not gain tab error mapping from those non-throwing call sites.
3. `NavigationHandler`, cookie helpers in `BrowserManagementHandler`, and annotation metadata in `LLMHandler` still depend on active-tab convenience properties in `HandlerContext`. That inconsistency should be kept explicit and limited to validation-only changes in this patch rather than hidden behind partial rewrites.
