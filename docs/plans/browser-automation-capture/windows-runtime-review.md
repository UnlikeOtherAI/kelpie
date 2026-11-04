# Windows capture draft source review

Reviewed Git tree: 46ae1dbaa490382055a562321fc5231ebc5e5bc5.
Base: bb663ded9f7fe48e482434278a047b651cf54a57.
This is an uncompiled tree, not a release or native acceptance result. Read-only
review started no process, test or UI session. Required shared helpers and codec
follow-up integration were still pending.

## Findings and evidence questions

| ID | Source and observation | Required result |
|---|---|---|
| WIN-01 | play-script bypasses the persistent MCP mutex; an older legacy request can pass Allows before run admission | Owner already identified and is fixing a short admission gate plus Allows recheck after GuardDispatch obtains the mutex. Verify both orderings in the final compiled tree |
| WIN-02 | ScriptNativeOverlay WM_TIMER advances elapsedMs every 33 ms while Sample retains a request-time presentation across asynchronous Screenshot | Hold the displayed state through the sample or document and measure the timing tolerance. A screenshot may take 3 seconds, longer than the default 700 ms fade; do not claim exact displayed/exported parity |
| WIN-03 | Sample increments dropped once for any cadence overrun and uses integer 1000/fps milliseconds | Define droppedFrames as actual skipped slots or rename/document the count. Use a fractional/absolute cadence if fps is an upper rate. Exercise slow screenshots and encoders with actual timestamps |
| WIN-04 | Sample adds first_document as documentId to a multi-document movie artifact | Label it explicitly as initial document or retain bounded transition provenance. Do not imply that every movie frame belongs to that document |
| WIN-05 | maxDurationMs is checked at the loop start, before screenshot/encode; Finish uses later elapsed time | Specify bounded in-flight/finalization grace separately from sampling duration and test the smallest duration. A retained-media cap does not establish a strict instantaneous time or scratch cap |
| WIN-06 | Artifact Expire runs only during Publish/Read and shutdown removes registered artifacts | Document lazy expiry honestly or schedule owned cleanup. Test expiry without another download and cleanup after failed publication; no process-wide temp deletion |

WIN-02 through WIN-04 were sent to the runtime owner. WIN-05/06 are acceptance
boundary questions, not measured runtime failures.

## Source invariants that look sound

Transport admission sets an opaque listener-incarnation owner only after the
existing local bearer check. The current server has one local control grant.
Request bodies cannot choose the owner, and outbound account calls have no such
scope. Run status/abort and artifact lookup compare that owner; native Stop holds
the run's immutable cancellation token. Listener restart creates a new owner.
The final test must distinguish this actual single-grant model from unsupported
claims about multiple named clients or live token rotation.

The run remains active through sampler join, encoder finalization, ephemeral
target cleanup and presentation cleanup. Shutdown requests abort and the existing
HTTP drain keeps admitted request work alive while CEF continues pumping. This
supports orderly ownership, but needs compiled cancellation/shutdown evidence.
The handler destructor alone is not evidence that every callback is retired.

The sampler admits one screenshot at a time and performs encoding on the same
worker that constructs and destroys the codec. It compares document generation
and CSS viewport before/after each screenshot. Mixed-document frames are dropped;
viewport changes fail explicitly. Target steps request pre-input marker evidence
with an expected document, then recheck before trusted CDP dispatch.

The native input path reports its asynchronous recheck-to-dispatch gap. It fences
the exact target between native commands and queues key/button release after
uncertainty without replaying the action. Actual focus, replacement, navigation,
cancellation and next-run behavior still require CEF tests.

The capture service creates a unique directory with current-user/SYSTEM ACL,
streams file hashing in 64 KiB blocks, returns opaque artifact identifiers and
limits reads to 1 MiB. Status excludes outputs and values. Declared or DOM-inferred
sensitive edits reject capture and terminal output values are redacted.

## Required native evidence

Use the exact compiled candidate through direct HTTP, direct MCP and CLI MCP.
Record binary/source hashes and the changed recording/Stop state only.
Exercise delayed screenshot, navigation during a frame, resize/DPR/zoom,
same-grant status/cancel/download, invalid and restarted grants, abandoned
requests, native Stop, failed finalization and a subsequent successful run.

Decode every retained GIF/MP4/PNG and inspect its visible frames. Compare native
and exported marker color/position/wobble/fade using the declared timing policy.
Check duration, skipped slots, final fade, hashes, chunk boundaries, partial flags
and bounded retention. Source review and codec decode do not close these gates.
Computer Use remains off; machine interfaces can be used only after the
coordinator assigns the exact candidate and resource slot.

## Owner response after this tree
The runtime owner is implementing a native presentation latch: while a renderer
snapshot is in flight, the timer pauses and newer model updates are withheld from
live display. Frame/discard/error releases the latch and restores the current
model. This is not a simultaneous OS screenshot; slow capture can reduce visible
pointer cadence. The owner also plans fractional steady-clock cadence with
skipped-slot accounting and explicit initial-document semantics for movie
metadata. These are follow-up plans, not changes verified in the reviewed tree.
