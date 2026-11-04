# Architecture and security review

Review status: proposed contracts reviewed; implementation audit and real-flow
evidence pending. Base: `b6784ff723b27da4096fdd8d9227f2a00dfc9084`.

## Accepted direction

Extend the existing strict versioned browser contract and play-script extension.
Keep one native-owned gateway/reference registry and exact-socket command queue.
Observation implementations remain fixed readers, never model-provided evaluation.
Recording can coordinate nested browser work only through the existing admitted
outer-request pattern; it must not clear or bypass a late-mutation ownership fence.

Reusable workflows resolve typed inputs and secret references before dispatch.
Assertions, extraction and readiness predicates have explicit outcomes. A mutation
with unknown completion stops execution and retains `mayHaveCompleted`; retrying
the same click would be a duplicate-action bug.

Semantic targets resolve one visible enabled object, compute its CSS viewport
center and hit-test it. Recheck object identity, document generation, viewport and
geometry after pointer presentation and immediately before dispatch. A reference
from a previous document must never become a selector re-query into the new one.
macOS currently proposes synthetic coordinate events: report that guarantee,
never describe it as trusted OS input.

## Capture consistency

A frame must couple pixels, document identity, viewport dimensions/scale, pointer
state and monotonic elapsed time. Sampling unrelated clocks or taking a later
screenshot after marker fade creates plausible but false evidence.

The proposed fixed canvas follows the initial viewport aspect ratio. Viewport
resize stops with partial `CAPTURE_VIEWPORT_CHANGED`, avoiding stretched frames.
Navigation may continue only with a fresh document generation and cleared prior
pointer/marker state. Check document identity before and after asynchronous frame
capture; discard or refuse a torn frame. A step PNG must capture the intended
overlay while it exists, not annotate a later document.

Use one encoder admission queue with a hard bound. When busy, drop presentation
frames and report the count, preserving real timestamps. GIF delay quantization
must preserve elapsed time within stated tolerance; MP4 presentation timestamps
must be monotonic. Duration/bytes limits and cancellation finalize partial output
when possible. Encoding failure cannot return a successful complete artifact.

## Authentication and artifacts

The proposed native owner is derived in the authenticated HTTP route from a
listener incarnation plus authenticated client/grant and copied before asynchronous
work. TaskLocal propagation is a transport context mechanism, not the authority.
Request-body session IDs, tab IDs and run IDs cannot confer ownership.

Every status, cancel and chunk request must pass current authentication and grant
revocation checks before comparing immutable owner. Same client ID with a different
grant must not inherit data accidentally. Token rotation behavior must be explicit.
Do not return or persist bearer tokens or token hashes in artifacts. Local native
Stop remains a UI action; it must not create an unauthenticated HTTP bypass.

Nessie cannot inherit a new recording permission merely because it has a connection.
Its existing session pins and authorization remain authoritative. Fail closed if
no authorized owner context exists, and document the limitation.

Manifests contain opaque run/artifact IDs, MIME, size, SHA-256, partial state,
timestamps and bounded provenance. Retrieval accepts bounded integer offset/length,
not a path, URL, shell command or environment name. Authenticate before revealing
existence. Reassemble chunks in an independent process and verify digest and size.
Cleanup must distinguish active runs from expired completed artifacts and cannot
delete an active output because an encoder temporarily stopped making progress.

## Observation and backend boundaries

Priority/scoped snapshots remain value-free, including inherited editors and
accessible-name paths. Extraction has deterministic nested records, explicit
missing/ambiguity outcomes and provenance. Publisher metadata/JSON-LD reads only
allowlisted fields with bounded depth, item count and total text; arbitrary script
objects and credential-like fields are not copied.

Page status reports available facts and unavailable diagnostics separately.
Document complete is not task complete. Immediate readiness is an explicit
document/unique-visible-selector predicate; workflows own bounded polling.

An operator-supplied already-connected Playwright browser may allocate isolated
contexts. Model-supplied endpoints cannot be attached. Owner checks cover reads,
writes and teardown. Restricted Lightpanda cannot inherit Playwright's full method
list. No screenshot, geometry, pointer or trusted-input claim without real backend
evidence. No copied AGPL implementation is introduced into the Apache package.

WebMCP discovery/evaluation is capability-gated. Page tool descriptions and results
are untrusted data and cannot expand session authority or bypass typed workflow
validation. Availability must be proven by an actual supported browser API.

## Open evidence questions

- Verify renderer-frame/document identity handling in source and navigation races.
- Verify resize, byte limits, dropped-frame duration and partial media finalization.
- Verify current-grant revocation, listener restart and token rotation behavior.
- Verify per-step screenshots contain real overlay pixels and correct document.
- Verify actual native input event trust against the advertised guarantee.
- Verify canonical and rich legacy entry points share strict validation/ownership.
- Verify optional backend and WebMCP capabilities against running implementations.
- Verify no additional product screens or settings beyond the requested behavior.
## Run ownership and asynchronous finalization

Ownership must remain held through encoder finalization and cleanup, including
off-main-thread GIF encoding. A new run cannot replace mutable presentation or
artifact state while the prior run finalizes. Local Stop must remain responsive
through this phase. Distinguish cancellation requested from terminal cancellation.
Bound outstanding screenshot callbacks as well as encoder frames. Hash media by
streaming it; chunk retrieval cannot read the entire file for every small chunk.
Check actual transport/C ABI envelope limits after base64 expansion. Exercise
bearer revocation during a run/download, same-client-name different grants and an
abandoned HTTP/direct-MCP request. Each must reach a bounded, truthful terminal
state or retain a documented completion fence that retires automatically.