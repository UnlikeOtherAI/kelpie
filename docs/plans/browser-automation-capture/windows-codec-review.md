# Windows codec source review

Reviewed revision: `2a0858f0a3e25aca6aadbb33eefcc5a28564a0ed`.
Review mode: source and reported test evidence only. No compiler, encoder,
browser, native app or Computer Use session was started by acceptance.

## Findings requiring resolution

| Finding | Source | Required result |
|---|---|---|
| Canonical and codec byte limits differ | script-workflow.ts accepts maxBytes=1024; ScriptMediaEncoder::Impl requires at least 1 MiB | One documented admission contract. Do not silently raise a caller's cap. Align schema, runtime, codec and native validation; test smallest allowed limits |
| Newly created PNG may be left partial and untracked | WritePNGBytes creates with CREATE_NEW, then can throw after WriteFile/CloseHandle; WriteStepPNG records path only after success | On failure, remove only the new file owned by that write or register it for explicit failed-artifact cleanup. Never erase a pre-existing file; test write/close failure |
| Lazy media open permits competing captures in one directory | Impl constructor checks existence before first frame; WicGif later opens ofstream with out; MP4 sink opens lazily without an explicit exclusive reservation | Enforce exclusive output/directory ownership across construction and first write. Two encoders created for the same directory before either writes must not overwrite each other. GIF out mode can truncate an existing output |
| Color evidence does not fully test MP4 chroma | Decode checks NV12 Y values at top and bottom only | Assert decoded UV or RGB colors within codec tolerance. Wrong/absent chroma can pass current checks. Add changing GIF palettes and padded BGRA stride cases |
| Finalization failure needs independent recovery evidence | Finish catches per-format errors, stores successful outputs, marks finished, then rethrows | Inject failure in one format, retrieve successful sibling manifest through repeated Finish, preserve valid file and truthful partial/error state; clean only invalid owned scratch |

The codec and runtime owners received these findings. The byte-limit and failed-PNG
findings were also raised by the coordinator. No finding is closed by this source
review alone.

## Timing and format assessment

The encoder retains one raw pending frame and derives its duration from the next
actual timestamp. It normalizes the first admitted timestamp to zero. Finish
supplies the final end timestamp. The runtime must sample before the first visible
script action if it wants the export to contain that action.

GIF rounds cumulative boundaries to centiseconds, rather than rounding each
interval independently. It splits a hold longer than the 16-bit delay field,
reserves its trailer, carries each frame's palette and adds an infinite-loop
extension. This design avoids accumulated timing drift. Full WIC decode reported
by the owner supports basic framing validity; changing-palette/color and
user-visible final-fade evidence remain pending.

MP4 uses explicit BGRA-to-NV12 conversion and a synchronous Windows H.264 baseline
transform, then remuxes compressed samples with their supplied timestamps.
Baseline/no-B-frame intent avoids reordering. The queue of pending timing records
is capped at 16. Actual Media Foundation decode and irregular timestamp/duration
checks are stronger evidence than a file header check. The reported tests do not
prove production-resolution memory use, backpressure in the native sampler or
a displayed/exported overlay match.

## Retention, memory and ownership boundaries

The shared budget charges exact encoded GIF/PNG bytes and conservative MP4
compressed-sample/container reservations. bytes_written returns actual retained
files. This is a retained-output cap, not a strict instantaneous memory or disk
scratch cap. Raw BGRA, NV12, WIC conversion/compression and native transform
allocations have separate transient costs. Do not claim a maximum-resolution
memory bound from the small-fixture process's measured peak.

The runtime must scale to the codec's maximum dimension/pixel count and even MP4
dimensions before admission, preserving the documented fixed canvas. maxWidth
alone does not constrain an extremely tall viewport. It must enforce requested
duration/FPS limits, stop sampling before Finish and keep finalization plus
destruction on the construction worker. Public methods check thread identity;
the destructor relies on the owner's lifecycle guarantee.

Cancellation is not permission to abandon the worker or delete the run.
A retained valid artifact must survive another format's failure. A budget too
small to retain even one encoded frame must produce an explicit incomplete/error
result, not a successful media claim. The service owns source/document provenance,
authentication, opaque IDs, SHA-256, chunk reads, retention and partial flags;
none of those is established by this codec-only interface.

## Evidence scope

The owner reports compilation with MSVC /W4 /WX on Windows 11 Maxis, full WIC
decode of GIF/PNG, full Media Foundation decode of MP4, irregular interval
timing, first-frame Stop/finalization, next capture, repeated Finish, malformed
frames/timestamps, ownership checks, byte-limit partial output and combined
PNG/GIF/MP4 byte accounting. Exact reported commands and artifact locations are
in windows-media.md.

These results cover native codec interfaces, not the full Kelpie executable,
CEF capture, UI overlays, direct MCP, CLI forwarding, authenticated remote
artifact retrieval, manual playback or installed published releases. Canonical
requirements CAP-01 through CAP-08, VIS-01/02 and ART-01 through ART-04 remain
open at the integrated native-app level.

## Follow-up source review

Reviewed follow-up: 8369571f6b821cc4bcfc853de2a78f5fc25e142d.

The original byte-limit mismatch, lazy-open overwrite, partial PNG cleanup and
color-oracle gaps are addressed in source. The codec now accepts 1024 bytes
without clamping. GIF uses CREATE_NEW; MP4 uses MFCreateFile FAIL_IF_EXIST and
passes that stream to the sink. bytes_written counts only files the writer owns.
PNG failure keeps a duplicate handle to the exact newly created file and marks
that handle for deletion after write/close failure.

Durable added checks are SmallBudgets, ExclusiveOwnership, PngFailureCleanup and
GifPaletteChanges in script_media_encoder_test.cpp. Timing now supplies padded
BGRA stride; decoded MP4 checks UV as well as Y. ExclusiveOwnership creates two
encoders before either writes, verifies byte-identical decodable winner output
and zero loser bytes, and preserves a completed GIF after an MP4 collision.

The owner reports these checks passed under MSVC /W4 /WX on Maxis. Acceptance
reviewed source and test assertions, but did not independently run codecs or
visually inspect media. These results resolve the original source issues and
strengthen codec evidence; full native capture remains pending.

Two follow-up ownership questions were sent to the codec owner:
MfVideo::Discard closes its stream before DeleteFileW(path), leaving a possible
path-replacement interval unlike the handle-bound PNG rollback; Finish ignores
the byte-stream Close HRESULT. The unique private runtime directory limits normal
exposure, but the codec helper's same-directory contender contract needs explicit
cleanup ownership. These questions remain open until the next source response.

## Exact-handle stream draft
The codec owner replaced the identity/reopen proposal with OwnedMediaStream,
an internal IStream owning a CREATE_NEW read/write/delete handle and duplicate
cleanup handle. Reviewed draft blobs: script_media_owned_file.h
cf6cc64b7ba4d40f1b07e245a5e97b2e11b00306 and script_media_video.cpp
d1c3e9415c59f64f05f009b522fee5542c26445e. These are source blobs, not a tested commit.
MFCreateMFByteStreamOnStream wraps the held object; the encoder no longer opens,
reopens or deletes its pathname. Constructor duplicate-handle failure marks the
original exact handle for deletion. Normal completion checks MF Close, flush and
both native closes. Failure marks the surviving exact handle for deletion before
closing. This addresses the prior path-replacement and constructor-identity
failure holes without a pathname fallback. No new source blocker was found.
ExactHandleRollback adds constructor duplicate failure, flush/close failures,
denied live rename/delete, replacement preservation after abort and completed-file
preservation. The reviewer requested a second-close fault too. The real MF wrapper,
full decode, budget and collision suite remain required under the coordinator's
queued CODEC-3 slot. No test was run by acceptance.

## Closed codec source findings
Final re-review: 2b2dc1c2673541ddfe13f2ab970283f396c4c3fd, integrated by the
coordinator before b217364a. The committed stream and video adapter match the
reviewed exact-handle design. ExactHandleRollback now includes the requested
second-close fault after the primary handle has closed successfully.
The codec owner reports CODEC-3 /W4 /WX and the full native run-4 corpus passed
on Maxis: real MF adapter decode, timing, color, frame counts, byte limits,
constructor duplicate failure, flush/first-close/second-close failure, live
rename/delete refusal, replacement preservation after rollback and completed-file
preservation. The prior GIF/PNG/MP4 collision, sibling, stride, chroma and palette
checks also passed. The recorded artifact root is
D:/Worktrees/kelpie/capture-windows-media-20261104/.build-media/run-4;
source and test assertions were independently read by acceptance.
This closes the reviewed codec source defects and their owner-run codec regression
gates. Acceptance did not rerun the suite or visually inspect decoded frames.
The 38,309,888-byte reported peak working set belongs to this fixture run, not a
production-resolution memory guarantee. Full-app capture, native display, MCP/CLI,
remote retrieval and installed-release acceptance remain pending.
