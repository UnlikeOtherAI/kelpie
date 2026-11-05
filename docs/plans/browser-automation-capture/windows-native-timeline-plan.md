# Windows owned native animation timeline: review proposal

This is a test design only. It has not been implemented, compiled or run.
The 5877 single-frame WGC, native Stop and G08 exported-media results remain
separate evidence. The earlier WGC failure and launch failures remain preserved.

## Entry point and ownership

Use the shared G08 fixture at c1495174 or its reviewed successor and production HTTP `play-script` request
in one fresh Session1 browser per curve, with GIF and MP4 enabled. Register and
launch through the public CLI, pin the exact PID, executable path, process
creation time, listener and launch identity, and use the existing standard UIA
provider only to identify the one exact owned `KelpieScriptPresentation`
HWND. The fixture's own loopback event receiver supplies Start and Finish
facts without evaluating the page while a script owns it. Refuse missing, dropped, reordered or untrusted calibration Finish, Start and final Finish facts; retain their document and viewport identities. No test route, product debug API,
physical input, foreground switch, desktop/monitor item, picker, access
request or borderless permission is used.

## Bounded native sampling

Extend the test-only owned-window WGC helper with an explicit timeline mode;
the existing one-frame mode and its 8-second internal/10-second parent bounds
stay unchanged. Timeline mode uses a single `CreateForWindow` item and
free-threaded two-frame pool, cursor capture disabled, secondary windows
excluded, standard OS border retained. Recheck PID, executable, creation time,
HWND class and visibility before item creation and before and after each deep-copy acquisition. A frame is sealed only after both checks; if identity changes during copy it is discarded. After session/pool closure, persist only sealed buffers within the 35-second parent bound, without reacquiring the hidden or destroyed HWND. Natural item closure ends collection and is recorded; it never proves missing phases. Ownership change, dimension change, deadline or cancellation fails closed and closes the frame, pool, session and device.

The caller starts the timeline helper as soon as the owned presentation HWND is visible in the canonical recording. No lead-in wait is added: the Windows overlay hides its canvas while the presentation has no pointer, marker or commentary. If discovery or helper startup misses the required calibration frames, report insufficient. Timeline mode runs at most 26 seconds, 20 frames/s maximum and 520 accepted frames maximum, with a separate parent bound of at most 35 seconds including teardown. The old one-frame 8-second internal and 10-second parent bounds remain unchanged. The helper must begin early enough to capture the first Finish pre-dispatch pointer baseline, or report insufficient evidence. Do not synthesize duplicate frames.
Record WGC `SystemRelativeTime` and callback receipt monotonic time for each
frame, acquisition count and dropped/late frames. A two-frame queue replaces
rather than accumulates frames under load. A stalled callback, missing clock,
nonmonotonic time or budget exhaustion is a failure or insufficient evidence.
The parent has a separately reviewed bounded teardown allowance; a helper
deadline does not become an excuse to extend the existing one-frame deadline.

Timeline capture dimensions are bounded at 4096 per side and 2,097,152 pixels; this includes the observed 1918 x 830 surface. Larger targets refuse before allocation.
Only one deep-copied BGRA frame may be processed at once; cap all helper memory
at 128 MiB within the existing 2 GiB one-CPU Job. Persist at most three
independently hashed, unmodified native BGRA/PNG evidence pairs per curve
(early, middle, late, selected online); the other frames are reduced to
bounded per-frame measurements then discarded. Enforce a 64 MiB output cap
and fresh paths. Do not persist renderer pixels, synthesize backgrounds in
native images, composite windows, or capture Stop via the presentation item.
Retain reported native alpha mode; validate premultiplication and every output
hash. An absent or invalid native frame is never a substitute image.

## Canonical oracle and correspondence

The common oracle expects RGB against a white fixture. For numeric analysis
only, derive a clearly labelled white-backed RGB sample from each actual
transparent WGC BGRA frame using the API-reported straight/premultiplied alpha,
and resample to the export dimensions with a documented fixed transform.
Keep the raw native evidence unchanged. Use the same shared
`scriptPointerPosition`, `scriptTapPresentation`, G08 pixel and timeline
oracle and the same scene targets/color/radius as exported media. The native
oracle must require dense early/middle/late C and S points, ease, endpoint,
marker color/center, fade, wobble and clear tail; missing samples, instability,
or inadequate timing coverage report insufficient evidence, not a pass. In particular, WGC may not emit repeated unchanged clear frames; absence of callbacks is not proof of a clear tail. If three actual post-clear frames are unavailable, the existing oracle remains insufficient rather than duplicating the last frame.

The current shared fixture clicks Finish, Start, then Finish with 3.5-second waits. It requires at least two actual stable pointer-only endpoint frames before the first Finish marker, the first marker at least 65% of a pointer duration later, and the final clear tail to match that calibrated ROI. The full 26-second cap follows that exact recording; if startup begins too late or WGC emits no fresh clear frames, report insufficient evidence and do not infer missing phases. Record actual
fixture event receipt, WGC monotonic frame times, native fitted pointer/marker
onsets, exported PTS and separately fitted onsets. Compare native and exported
curves and marker evolution on their independently fitted relative phase,
including bounded residuals and sample gaps. A common absolute clock mapping
between exported PTS and WGC `SystemRelativeTime` is not currently exposed:
do not call those frames simultaneous or claim a precise native/export latency.
If a verifiable common clock is found in the existing public contract, document
its uncertainty before any absolute-time assertion.

## Before execution

Root must review helper bounds, alpha conversion, actual fixture-to-window
geometry and the phase-comparison thresholds before compilation or execution.
Run focused synthetic tests for alpha modes, queue/drop handling, clock order,
timeout/late callbacks, invalid HWND/size/ownership, insufficient phases and
known C/S/ease/fade/wobble perturbations. Then compile only the test helper
under the approved Job, run one C and one S journey with distinct fresh
profiles/output roots, and preserve all failures. The test must verify public
stop, exact process exit, listener, readiness and alias cleanup before releasing
its task. A native validation pass is still not a signed-release pass.

## Concrete dataflow for review

Timeline mode owns the existing exact-HWND WGC item and a two-frame pool. A
single-slot handoff keeps only the latest pending frame and increments an
explicit replacement counter; the callback never performs PNG I/O or invokes
Node. A worker accepts no more than 20 real frames per second. It sends a
length-prefixed binary record over its owned child stdout pipe: sequence,
WGC system-relative time in 100 ns, callback monotonic time, original and
analysis dimensions, API alpha mode, stride and nearest-neighbor sampled BGRA.
Dimensions and payload length are validated on both ends. A bounded parser
holds at most one complete analysis frame and a partial record; invalid,
oversized, truncated, duplicate or nonmonotonic records fail closed. A blocked
pipe or decoder is bounded by the 26-second session and 35-second parent Job
deadline; no queue grows while waiting. The helper closes the capture session
before persisting up to three preselected raw/PNG pairs; if it cannot clean up
and finish within the parent deadline, retain the failure and do not promote
its output. Raw saved frames are untouched full-resolution WGC bytes, not the
analysis stream.

For each accepted frame, Node converts sampled BGRA to white-backed RGB with
the checked `wgc-g08-rgb.mjs` transform and invokes the shared
`measureG08Frame` directly. Its actual sample records then enter the shared
`evaluateG08` at c1495174 with the same configuration and three scene events.
That oracle owns the path, easing, calibration ROI, fade, wobble, color and
clear-tail thresholds; the C++ helper does not implement a second pixel or
animation oracle. Persist only bounded measurements and three full-resolution
native frame pairs. To avoid retaining every full frame, the fixed evidence
samples are clock-position snapshots labelled as such, not asserted to be
early/mid/late visual phases unless measurements confirm their phase.

Both native and exported media must first independently pass the shared
oracle. For a further relative-phase comparison, interpolate only inside
intervals where both streams have real bracketing samples and no gap exceeds
the shared oracle's phase gap limit. Evaluate 20 fixed normalized motion phases
from 0.05 through 0.95 using each stream's one fitted onset and the same
2.4-second duration; require native/export pointer RMS <=6 analysis pixels and
maximum <=12. For 20 marker phases from 0.1 through 0.8, use each stream's
single fitted marker onset and 3-second duration; require alpha RMS <=0.12 and
radius RMS <=2.5 analysis pixels after each stream's single bounded radius
bias. Require at least 15 real-bracketed samples in each comparison; otherwise
report insufficient evidence. These proposed cross-stream thresholds are
additional to the stricter independent canonical checks and require root
review. They do not assert same-clock simultaneity or latency.

## Identity provenance

The fixture event's JavaScript-generated document ID is only a consistency
fact within that fixture. It is not the native document authority and is not
equal to the native artifact document ID. The harness must bind the owned HWND
to the exact process, launch and listener; poll public active status for the
same run ID while sampling; and match the terminal result and both artifacts
to that run. Both artifacts must agree on their native document ID, viewport
and size, and trusted tab/provenance facts must show the same intended
document before and after the run. A fixture event ID cannot establish this
binding by itself. If the public contract cannot exclude intervening navigation
or bind the active run to native document provenance, report insufficient
evidence rather than assigning the page-supplied ID as authority.

## Capture-free helper verification

On Maxis, source revision aab3c236 compiled the C++ helper with /W4 /WX
and the UI Automation helper with /warn:4 /warnaserror under separate
one-CPU, 2 GiB jobs. The C++ buffer and bounded-stream self-tests passed;
the bounded-writer test replaced one pending frame and stopped in 2041 ms.
The first C# invocation failed because its relative source path was resolved
incorrectly; the absolute-path retry passed. Both receipts are retained in
D:/BuildArtifacts/kelpie/capture-windows-resume-20261105/wgc-timeline-aab3.

The helper hashes are 247bfd425aecc614d898846fb4d1ac3deb33088448ce9e4361f91028cf14c0b9
(C++) and fbfaa6d364d68260d90dda27dc632d62485a4f479e7d083a0960c2efe1ecb780
(C#). The 23 focused Node checks passed. This is capture-free verification;
the public orchestration and native timeline have not yet been exercised.