# Native privacy final source review

Reviewed immutable integration b7a1fc687b47c6c1edb90be45c9b0afa141a3072.
Reviewer: common contracts/acceptance,2026-11-05 UTC. Source closure is not native
runtime acceptance; prior actual f188/81ed security failures stay immutable.

## Callback, sampler and first-error ordering

Mac84a069cb includes40f85d61 callback/known handling,5a0c6d51 sampling stop and
8bb0b326 known-nonsensitive guard handling. Independent read confirms:

- Metadata is consumed inside the actual renderer operation before deadline
  retirement completion and post-result document/cancellation guards.
- sensitive:true protects regardless of known flag. False is trusted only with
  sensitivityKnown:true; missing/invalid classification after started evaluation
  registers the current edit literal, and capture gets an independent discard
  latch. Click/tap have no edit literal but still discard uncertain capture.
- valueReturned distinguishes a real known-false response followed by a guard
  failure from a missing response. Safe known-false guard failures retain valid
  partials rather than becoming blanket privacy disposal.
- ScriptCapture.stopSampling marks stopped/cancels frameTask before waiting for
  existing renderer retirement. Final redaction and capture.finish follow that
  fence, preventing continued admission or early media publication while waiting.
- A pre-existing action error survives redactor/capture/Stop cleanup errors.
  Redaction failure still discards all capture. Successful post-input sensitive
  classification refuses capture after consuming metadata; it does not claim
  that an already completed edit never occurred.

iOS440de54c and Androide7a6fe48 add actual post-input type/autocomplete vectors
(capture/noCapture). Their thin consumers preserve helper failure before adding
a successful post-input capture refusal. Known classification comes from the
same shared helper; no platform DOM classification fork was introduced.
Their real runtime outcomes and cancellation-retirement liveness remain pending.

Windows81ed focus privacy passed but actual oninput probe still leaked all four
variants. Owner b63b3fa2 compiled and scrubbed noCapture autocomplete; post-input
type change exposed an overstrict post-edit TARGET_MOVED result. The next proposed
privacy-only post-insert inspection is coherent only after confirmed native insert:
keep pre-input guards unchanged, consume fresh metadata first, preserve transport/
missing classification uncertainty, and apply capture sensitivity refusal without
retroactively reapplying geometry/type eligibility to an acknowledged edit.
This is a private native stage, not a public policy override. Final source/runtime
checkpoint remains Windows-owned.

## Error envelopes deliberately remain distinct

| Surface | Expected behavior |
|---|---|
| Native HTTP play | Detailed fixed first concrete action/privacy error; privacy discard independent of code; success may remain true for completed noCapture edits with scrubbed outputs. |
| Direct/generic MCP play | Existing gateway failure envelope COMMAND_FAILED remains; no new arbitrary native error forwarding. Preserve uncertainty. Recover safe detailed terminal metadata through owner status. |
| Owner v1 status | Query success:true even failed/aborted run, playing:false after retirement, runSuccess:false and original safe runError; no outputs/secret literals. |
| Active current artifact | Valid owner request ARTIFACT_NOT_READY; foreign ARTIFACT_NOT_FOUND; no data; validate canonical request before phase decision. Prior safe terminal artifacts remain readable. |
| Direct/generic MCP artifact | Only approved ARTIFACT_NOT_READY/ARTIFACT_NOT_FOUND normalize with safe fixed gateway text; raw native/page messages and data never pass through. |

SENSITIVE_CAPTURE_REFUSED is the canonical inferred-sensitive capture refusal.
A preceding concrete target/transport error may remain the first error while
capture is still discarded and earlier outputs scrubbed. Do not overwrite it
merely to make privacy test codes identical. Missing classification alone does
not prove input occurred: retain actual mayHaveCompleted. NoCapture registration
is scoped to the current attempted edit, not all ordinary inputs.

## Finite remaining runtime cases

Each renderer/device needs returned-late and missing-result target callback
cases, successful post-input classification, known-false guard failure retaining
ordinary partials, noCapture scrub, current/foreign/prior-run download branches,
and next-run recovery. Observe that canceled/timedout callbacks actually retire
before terminal outputs/artifacts become visible. Existing retirement fences
must not be bypassed or replaced with unsafe release/replay to make a test end.
