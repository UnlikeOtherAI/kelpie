# Android Dialog Handling Plan

**Goal:** Replace Android browser dialog stubs with real JavaScript dialog interception for `alert`, `confirm`, and `prompt`.

## Root Cause

Android currently advertises dialog support in the API docs, but the browser management endpoints are hardcoded stubs. Because `WebChromeClient` does not intercept JavaScript dialogs yet, there is no place to capture the pending `JsResult` / `JsPromptResult`, so `get-dialog` and `handle-dialog` cannot operate on real browser state.

## Design

1. Add a small `DialogState` holder in `core/android/src/main/java/com/kelpie/browser/browser/DialogState.kt`.
   - Track one pending dialog at a time via `current`.
   - Store dialog type, message, default text, and the WebView completion object (`JsResult` or `JsPromptResult`).
   - Support an optional `autoHandler` mode: `null` means queue, `"accept"` auto-confirms, `"dismiss"` auto-cancels.
   - Mirror iOS and the documented API by also storing `autoPromptText` for auto-accepted prompts.

2. Intercept dialogs inside `WebViewContainer` through `WebChromeClient`.
   - `onJsAlert`, `onJsConfirm`, and `onJsPrompt` will enqueue a `PendingDialog`.
   - Each override returns `true` so Android does not show the platform default dialog.
   - Auto-handled dialogs must immediately resolve their WebView result through `DialogState.enqueue`.
   - `onPageStarted` will cancel any queued dialog before a new navigation continues, so stale `JsResult` objects never leak.

3. Wire `DialogState` through `HandlerContext`.
   - The handler layer reads `ctx.dialogState.current` for `get-dialog`.
   - The handler layer resolves the pending dialog through `ctx.dialogState.handle(...)`.
   - `DialogState.handle(...)` must post result completion to the main thread because HTTP handlers do not run on the UI thread.

4. Replace the dialog endpoint stubs in `BrowserManagementHandler`.
   - `get-dialog` exposes the currently queued dialog using the documented shape.
   - `handle-dialog` accepts or dismisses the current dialog and reports the handled dialog type.
   - `set-dialog-auto-handler` maps the API request to `DialogState.autoHandler`.
   - `set-dialog-auto-handler` also stores `promptText` into `autoPromptText` to match iOS and the shared API schema.

## Constraints

- Keep the implementation single-slot and simple. Android `WebView` only needs the currently pending dialog for this API.
- The dialog completion object must always be resolved. A leaked `JsResult` / `JsPromptResult` would block the page.
- Match the existing documented contract where possible:
  - `get-dialog` returns `defaultValue` for prompts.
  - `handle-dialog` accepts `promptText` and reports `dialogType`.
  - `set-dialog-auto-handler` treats `"queue"` as no auto-handler and stores `promptText` for auto-accepted prompts.
- Clear any pending dialog during activity teardown so destroyed WebViews do not leave stale dialog state behind.

## Cross-Provider Review

Reviewer: `max` adversarial review on 2026-04-06.

Accepted findings:
- `JsResult` / `JsPromptResult` resolution must happen on the main thread.
- Pending dialogs must be cancelled on navigation to avoid stale WebView result objects.
- Pending dialogs must be cleared during activity teardown.
- Android should support `promptText` for auto-accepted prompts to stay aligned with iOS and the shared API docs.

Rejected findings:
- No extra endpoint is needed to query the current auto-handler state. The existing contract does not expose that state separately.
