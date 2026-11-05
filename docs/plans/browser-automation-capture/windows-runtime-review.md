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
| WIN-07 | Play snapshots owner once; Cancelled checks abort/deadline/capture_error only, with no current grant callback | Fresh status/download auth does not prove active-run revocation. Re-admit grant before actions/sample boundaries or explicitly define accepted run lifetime authority |
| WIN-08 | output title/url evaluates the full page string through the bridge, then outputs.dump checks the 256 KiB budget | Bound page-controlled output before bridge serialization and return an explicit limit result. A post-copy output cap is not a bounded observation |

WIN-02 through WIN-08 were sent to the runtime owner. WIN-05/06 are acceptance
boundary questions, not measured runtime failures. WIN-07/08 are source gaps;
no native failure has been reproduced.

## Source invariants that look sound

Transport admission sets an opaque listener-incarnation owner only after the
existing local bearer check. The current server has one local control grant.
Request bodies cannot choose the owner, and outbound account calls have no such
scope. Run status/abort and artifact lookup compare that owner; native Stop holds
the run's immutable cancellation token. Listener restart creates a new owner.
The final test must distinguish this actual single-grant model from unsupported
claims about multiple named clients or live token rotation. In this tree the
accepted run retains authority until explicit abort, shutdown or deadline. There
is no per-action/per-sample authorization callback. BeginShutdown requests local
abort and drains HTTP work; denial of a subsequent status/download request alone
does not stop an already admitted run. Immediate grant revocation is unverified
and must not be inferred from immutable owner checks.

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

## Frozen overlay foreground review
Reviewed overlay source in tree 6ca7d1205a8eb758a74d90156e3c44b48b7ea633.
This follow-up reviews script_native_overlay.cpp only, not the entire newer tree.
Canvas and Stop are owned WS_POPUP windows. Show checks viewport visibility and
owner minimization, then repeatedly calls SetWindowPos(HWND_TOP) with
SWP_NOACTIVATE. It has no current foreground/owner activation policy.
WIN-09: the source does not guarantee that presentation stays behind another
foreground app. SWP_NOACTIVATE prevents activation; it is separate from the flags
that preserve window/owner Z order. See Microsoft's
[SetWindowPos reference](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos).
This is a source/API inference, not a reproduced desktop failure.
The runtime owner received a scoped post-compile requirement: check the foreground
and owner-window policy on the UI thread for every show/latch/timer callback, hide
when another app or a covering owner modal is foreground, preserve the owner's
Z order, and restore only the current valid model on owner activation. The latch
pauses the animation timer, so foreground loss must not depend on that timer.
Keep the separate interactive Stop HWND.
Required real native cases are switching foreground during fade and an in-flight
snapshot latch, owner minimize/restore, a modal over the renderer, and returning
to Kelpie without activation or Z-order theft. Preserve the frozen first compile;
apply and test the fix afterward. No CUA, UI action or test was performed here.

## Committed Windows runtime review

Reviewed commit: 8423d7df8b4fa21b7e3c2b8ec24cfd3a9e4b4f64,
base9b939695ed276130e3b5d78463712a02f6f5c84d. This supersedes frozen tree e1f96def;
recording/runtime implementation differs only by trailing blank-line cleanup.
Review was read-only. No app, browser, build, test or Computer Use was started.

| Prior finding | Source at this checkpoint | Remaining evidence |
|---|---|---|
| WIN-01 admission race | TryScriptAdmission holds the persistent mutex across running-state admission; router rechecks Allows after GuardDispatch | Actual competing request orderings and late pending completion |
| WIN-02 displayed/exported time | presentation_latched withholds later display updates during Screenshot; policy timer stays active | Native display/frame correspondence and slow screenshot timing; no simultaneous OS-screen claim |
| WIN-03 cadence/drops | Fractional steady-clock interval and skipped-slot accounting replace integer cadence | Burst step tickets may bypass nominal movie cadence; owner question below |
| WIN-04 document provenance | Plan explicitly defines movie documentId as initial generation, PNG as sampled generation | Public API wording and actual navigation/torn-frame corpus |
| WIN-05 duration/finalization | Pre-acquisition duration check and one in-flight frame; run retains ownership through sampler/finalization | Measured in-flight/finalization grace and responsive abort/next run |
| WIN-06 retention | Private directory, bounded total storage, one-hour lazy expiry on Publish/Read/shutdown documented | Expiry/cleanup/recovery actual service flow |
| WIN-07 grant freshness | Listener-incarnation revalidate callback before actions and sampled frames; shutdown closes admission | Actual listener/revocation/late callback behavior |
| WIN-08 output copy | Fixed output reader refuses >16,384 characters before returning across bridge | Real large-output refusal and secret cases |
| WIN-09 foreground policy | Timer remains active while latched; Show checks foreground, modal/disabled owner and minimization, uses no-Z-order flags | Actual foreground/modal/minimize/restore UI tests remain blocked by user Computer Use hold |

New source finding WIN-10 / SEC-01: Encoded emits uppercase percent triplets and
Scrubber::Text uses byte-exact comparisons. Secret a b+! is scrubbed in
a%20b%2B! but survives in equivalent a%20b%2b!; form a+b%2b%21 has the same problem.
The Windows owner received the exact case and a focused mixed/lowercase percent-hex
regression request. Treat percent hex digits case-insensitively without folding
ordinary secret text. This is a deterministic source finding; no native app
failure was reproduced by this reviewer. SEC-01 remains open.

WIN-03 source/evidence question: requested_step>=0 wakes before the next cadence
slot, then Capture::AddFrame feeds all frames into GIF/MP4 before optional PNG.
A zero-wait burst can exceed requested movie fps despite the fractional timer.
The owner was asked to enforce/coalesce the declared movie rate while retaining
step PNG evidence, or document and measure a bounded mandatory-frame policy.
This is not yet a measured native failure.

SESSION_UNSUPPORTED preflight is present for every supplied external sessionId,
before admission/target/navigation. Absent ID uses existing authenticated local
grant plus pinned tab. No body-selected authority or parallel allocator is created.
The generic script MCP path builds a transient gateway from the same registry,
strict generated schema and callable-router filtering before bypassing the long
persistent mutex. Native owner/CAPI tests exercise this owner-context plumbing;
they do not establish actual CEF playback or media acceptance.

The owner reports a shipping build and owner/redaction/compositor/codec tests.
Those reports do not close native HTTP/MCP/CLI capture, media-decode artifact
lineage, UI or installed-release requirements. Common registry checkpoint07beb
and main merge9b939695 were separately verified; no extra Windows build was run here.

### Follow-up evidence: matcher, cadence and exported pixels

The Windows owner committed percent-triplet-only mixed/lower-hex matching at
cda68d21d5cc92495854a3607350fc0067912f20; the focused native matcher test passed.
Root integrated that checkpoint and movie cadence fix at
cdf0a7fbdfed2afb94fb1f56222da725ef204a88. Shared redactor lift
9f752a56335a15e1662016dc6db934a79adba7b5 passed public C ABI and no-CEF desktop
delegation tests2/2. These source/unit results close the identified matcher
algorithm defect, not actual-app SEC-01 acceptance or final FPS measurement.

Root independently inspected exported8423 pixels using local view_image, without
Computer Use: the confirm-order PNG showed the red marker centered on Confirm
order with the pointer; a later sampled frame showed the marker gone on the same
fixture document a9695709. The files and owner cross-host-decode-report.json are
under C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/native-8423/.
The owner report records eleven artifact hashes/byte lengths and full
single-thread GIF/MP4/PNG decode/timing. Root's visual observation is separate
reviewer evidence; it does not prove the local native overlay or Stop control.
Two owner-flow assertions and encoded-secret/FPS retests remained pending at
that observation. Computer Use remains OFF.
