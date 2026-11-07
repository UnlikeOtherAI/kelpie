# Annotation lifecycle expiry for LLM annotations

## Problem

`screenshot-annotated` returns a numbered list of interactive elements, but `click-annotation` and `fill-annotation` rebuild that list later from the live DOM. If the page has navigated or otherwise changed, annotation indices can silently point at different elements or disappear. The protocol already defines `ANNOTATION_EXPIRED`, but the handlers never emit it.

## Root cause

The handler context does not persist any annotation session state. Annotation-driven actions therefore have no invariant tying them to the screenshot that produced the indices.

## Simplest fix

Persist a small annotation session in each platform handler context when `screenshot-annotated` succeeds:
- `annotationSessionId: String?`
- `annotationPageURL: String?`
- `annotationElementCount: Int?`

At screenshot time:
- Generate a random session ID.
- Capture the current page URL from the handler context.
- Capture a minimal DOM fingerprint as the annotation element count (`annotations.count`).
- Store all three values in the handler context.
- Return `annotationSessionId`, `validUntil: "next_navigation"`, and the lifecycle hint in the response.

At `click-annotation` / `fill-annotation` time:
- Read the current page URL from the handler context.
- If it does not match `annotationPageURL`, return `ANNOTATION_EXPIRED` with a message telling the LLM to take a fresh `screenshot-annotated`.
- Include the stale session ID in the error diagnostics payload.
- Otherwise keep the existing activation/fill flow unchanged.

## Scope and tradeoffs

- This intentionally uses URL change as the validity boundary because that is the requested behavior and it matches the new `validUntil` contract.
- `annotationElementCount` is stored now for future strengthening but not used for rejection in this patch. That keeps logic identical across platforms and avoids inventing a stricter lifecycle than the docs promise.
- No request parameter changes are required for `click-annotation` or `fill-annotation`; the handlers validate against the last stored annotation session.

## Files

- `core/apple/macos/Handlers/HandlerContext.swift`
- `core/apple/ios/Handlers/HandlerContext.swift`
- `core/android/src/main/java/com/kelpie/browser/handlers/HandlerContext.kt`
- `core/apple/macos/LLM/LLMHandler.swift`
- `core/apple/ios/LLM/LLMHandler.swift`
- `core/android/src/main/java/com/kelpie/browser/llm/LLMHandler.kt`
- `docs/api/llm.md`

## Cross-Provider Review

Reviewed with `max` on 2026-04-13.

Accepted:
- Persist the annotation session only after screenshot capture and payload assembly succeed. This avoids orphaning a new session when `screenshot-annotated` fails partway through.
- Document the diagnostics payload shape for `ANNOTATION_EXPIRED`.

Rejected:
- URL canonicalization beyond exact stored URL matching. The requested contract is URL equality, and broadening that in this patch would create platform-specific behavior.
- Additional tab identity tracking. The requested fix is URL-based and should stay minimal.
- Using `annotationElementCount` for expiry now. The task explicitly requires storing it, but the new public contract says annotations remain valid until URL change, so count-based expiry would make the implementation stricter than the documented lifecycle.
