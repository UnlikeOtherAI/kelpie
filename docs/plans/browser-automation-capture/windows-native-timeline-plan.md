# Windows owned native animation timeline: review proposal

This is a test design only. It has not been implemented, compiled or run.
The 5877 single-frame WGC, native Stop and G08 exported-media results remain
separate evidence. The earlier WGC failure and launch failures remain preserved.

## Entry point and ownership

Use the existing shared G08 fixture and production HTTP `play-script` request
in one fresh Session1 browser per curve, with GIF and MP4 enabled. Register and
launch through the public CLI, pin the exact PID, executable path, process
creation time, listener and launch identity, and use the existing standard UIA
provider only to identify the one exact owned `KelpieScriptPresentation`
HWND. The fixture's own loopback event receiver supplies Start and Finish
facts without evaluating the page while a script owns it. Refuse missing,
dropped, reordered or untrusted facts. No test route, product debug API,
physical input, foreground switch, desktop/monitor item, picker, access
request or borderless permission is used.

## Bounded native sampling

Extend the test-only owned-window WGC helper with an explicit timeline mode;
the existing one-frame mode and its 8-second internal/10-second parent bounds
stay unchanged. Timeline mode uses a single `CreateForWindow` item and
free-threaded two-frame pool, cursor capture disabled, secondary windows
excluded, standard OS border retained. Recheck PID, executable, creation time,
HWND class and visibility before item creation, each accepted frame and any
persistence. Item close, ownership change, dimension change, deadline or
cancellation fails closed and closes the frame, pool, session and device.

The caller starts timeline mode 1.5 seconds after receipt of the fixture Start
fact. It collects actual frame arrivals for at most eight seconds, 20 frames/s
maximum and 160 accepted frames maximum. Do not synthesize duplicate frames.
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

The eight-second window is deliberately placed to cover the remaining
3.5-second wait, 2.4-second motion and 3-second marker including its clear tail;
if scheduling starts too late, do not infer missing phases. Record actual
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
