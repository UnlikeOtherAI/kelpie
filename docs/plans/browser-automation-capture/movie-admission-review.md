# Independent critical movie admission review

VIS-01/VIS-02/CAP-01/CAP-02/CAP-03. Source review only; actual final all-frame
GIF/MP4 proof on the correct pre/post-navigation documents remains mandatory.
Step PNG, a sampled bitmap, an append Bool or elapsed FPS interval alone is not
proof of a committed movie marker. Computer Use remains OFF.

## iOS503a553688815e4e46487263d480d47c71a7b1cf

IOSFrameSampler.markBeforeInput holds progress0 through receive acknowledgement,
then waits a cancellable requested interval and the action rechecks exact target
before dispatch. GIF receive stages an exclusive uniquely indexed PNG; the GIF
encoder later streams every staged image unless it returns partial/error,
which IOSWorkflowMedia converts to failure/partial.

ScriptVideoWriter.append(true) means retained raw pending buffer, not committed
MP4 bytes. The next accepted append submits that pending sample before replacing
it, and throws if AVAssetWriterInput.append fails. Finalization submits the last
pending buffer or throws; sink budget exhaustion can omit a prefix-tail sample,
but media checks budgetExceeded and marks failure/partial. I found no source path
silently replacing the accepted marker on nominal success, conditional on
AVFoundation's actual output behavior. This is not an encoded-byte ACK.

The final submittedFrames versus sink.frameCount equality guard was missing.
The iOS owner agreed and requested that conservative normal-success guard from
the shared Apple codec owner. It is pending a frozen reviewed checkpoint.
Actual iOS lowfps test compiled; simulator execution remains blocked on user
handoff, so no final marker or UI acceptance is claimed.

## Androidfc1d7b507d0ecfe76c1c9c2b20698dcd20e4f78a

The held old-document marker precedes input and actual per-format timestamp
admission plus an interval precedes animation restart/exact-target recheck.
GIF ACK occurs after writing the pending frame with its pendingDocument.
Video.frame can return true for a dropped input, but lastWrittenMs only advances
after MediaMuxer.writeSampleData; the admission loop uses that written timestamp,
so append Bool alone does not qualify a marker.

A separate attribution finding remains: ScriptCapture assigns that written
timestamp the current sampled frame.documentId, although drain may have written
an older queued frame. The marker-time threshold likely prevented a later marker
qualifying from that old timestamp, but the claimed document is still wrong
across navigation. Android owner accepted a bounded queued PTS-to-captured-document
mapping (max4) and fail-closed unknown attribution, plus decoder regression.
That follow-up is not yet reviewed or runtime-proven here.

The original MOB-01..04 findings have source fixes in fc1 per owner and examined
movie code; actual JNI-backed readiness/extraction and all-frame decoded
movies-only fps1 navigation still remain acceptance gates.

## Windows and other runtimes

Read-only Windows audit used immutable staged tree
aaba23cccfef22d6db40729473a8aa5603fbaf90 overdc0648. Critical codec/service/
sampler/action paths only were inspected; status/key drafts were outside scope.
GIF count advances after complete source-image writes; H.264 count advances after
retained compressed WriteSample, never raw ProcessInput. The minimum prefix drains
a bounded18-entry FIFO of marker/action/document metadata. Held progress0 keeps
post-request frames on the same marker; exact ACK plus10s/cancel/error gating
precedes animation reset and exact native target dispatch. Final video drain
rejects leftover timings; finalization failures propagate and discard the failed
format rather than becoming nominal success. No new source blocker was found.
The source prefix/decode tests assert raw-first-pending and final decoded counts,
but this reviewer did not run them. The earlier real fps1 movie marker omission
remains open until final actual marker-pixel/document artifacts prove closure. Linux reuses desktop code but needs its own GTK/OSR outcomes and
sandbox proof; Mac requires its own renderer/codec path. No platform inherits a
runtime or UI pass from another platform's source or codec result.
