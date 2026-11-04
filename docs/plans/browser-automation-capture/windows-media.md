# Windows native capture encoders

The Windows encoder seam accepts composited BGRA8 viewport frames on one capture
worker. WIC compresses GIF frames and PNG screenshots; the Windows software H.264
transform and Media Foundation MP4 sink produce video. No ffmpeg executable or
downloaded codec is required. The existing CEF sandbox/bootstrap is untouched.

## Interface

Files live under apps/windows/src:
- script_media_encoder.h/.cpp: validation, ownership, actual frame intervals,
  bounded pending frame and shared retained-byte budget.
- script_media_gif.cpp: WIC palette/LZW compression and bounded GIF framing.
- script_media_video.cpp: fixed BT.601 BGRA-to-NV12 conversion, synchronous native
  H.264 baseline transform and compressed-sample MP4 remux.
- script_media_png.cpp and script_media_internal.h: WIC PNG and internal helpers.

Create(directory, formats, fps, maxBytes) accepts gif/mp4, 1..60 fps and a
1024-byte..256 MiB retained-media budget (default 64 MiB). Empty formats support
screenshots alone. The directory must exist and capture.gif/capture.mp4 must not
already exist. The caller supplies a private per-capture directory.

AddFrame validates finite, strictly increasing elapsed timestamps, dimensions,
stride and byte count before admission. The first timestamp becomes zero in
exports. Dimensions cannot change within a recording. Frames are top-down BGRA8
with an explicit stride (zero means width times four), at most 4096 per dimension
and 8,388,608 pixels. MP4 requires even dimensions. The caller resizes/composites
before submission.

The encoder retains one raw frame to derive its duration from the next timestamp.
Finish(terminalElapsedMs) supplies the final frame's end in the caller's clock.
Call it on Stop, cancellation and failure on the same worker; do not abandon the
worker during finalization. A rejected timestamp leaves the run finalizable with
a valid timestamp. Repeated successful Finish returns the same manifest. If one
format fails finalization, the other is still finalized; another Finish retrieves
the successfully completed manifest. An empty run creates no media files.

AddFrame false or WriteStepPNG false means CAPTURE_BUDGET_EXCEEDED: stop sampling,
then Finish. Previously admitted output remains available. WriteStepPNG encodes
to bounded memory, admits its exact encoded bytes to the shared budget before
writing, and accepts only PNG files in the capture directory. The service owns
the screenshot manifest. Static WritePNG is a separate, caller-budgeted helper
and is not included in encoder byte accounting.

## Timing and limits

GIF rounds cumulative boundaries to 10 ms units, preventing per-frame rounding
drift. Unrepresentable intervals are counted as dropped. Holds exceeding the
655.35-second GIF delay field are split into repeated frames. Every admitted
frame has its full compressed data before append; the trailer is reserved with
the first frame. Each frame owns its palette, so changing colors do not inherit
an earlier frame's color table. GIFs loop.

MP4 preserves caller intervals at 100 ns resolution. Baseline H.264 avoids frame
reordering. Low latency and synchronous output pumping bound the timing queue to
16 entries; no unbounded raw queue is created. Encoded sample bytes are admitted
before the MP4 sink sees them. A conservative reservation charges twice the
compressed size plus 512 bytes per sample and 64 KiB fixed container/footer
headroom. A budget stop can therefore finish below the nominal byte cap. The
transform is drained, excess samples are counted as dropped, and accepted samples
are finalized into a playable container.

bytes_written reports actual on-disk GIF/MP4 and admitted step PNG bytes, rather
than the conservative reservation. Raw frames, WIC conversion/compression scratch,
NV12 buffers and native codec allocations are transient and are not retained
artifact bytes. Frame validation bounds input allocations independently. No
maximum-resolution process-memory claim has been verified.

Failures use fixed codes without page text or file paths. The service owns
authentication, opaque IDs, retention, SHA-256, chunk retrieval, input semantics,
native overlays and user-visible cancellation/restoration.

## Focused verification

Host: Windows 11 Maxis. Base: ef9f8eda5a9a44bb2c4e13eb8d995adf1a4581f7.
Compiler: VS2022 BuildTools MSVC 14.44.35207, Windows SDK 10.0.26100.0.
Source test: apps/windows/tests/script_media_encoder_test.cpp.

The single compiler invocation used:
cl /std:c++20 /EHsc /W4 /WX /utf-8 /MD, with src include path, the four encoder
translation units and the test translation unit; linked ole32, windowscodecs,
mfplat, mfreadwrite, mfuuid, wmcodecdspuuid, propsys and psapi. The executable and
artifacts were written under the assigned worktree's ignored .build-media/.
TEMP and TMP pointed to .build-media/tmp. No CEF/full app build or service ran.

The final focused run passed:
- Native WIC decoded every GIF frame and PNG pixel; native Media Foundation
  decoded every MP4 frame. Red top/blue bottom fixtures verified color and
  orientation, plus dimensions and ordered presentation timestamps.
- Irregular 137/453/421 ms intervals retained a 1011 ms timeline (GIF rounded
  cumulatively within 5 ms; MP4 duration matched within 2 ms).
- Invalid options, frame bytes, dimensions, timestamps, NaN, owner thread,
  duplicate output and invalid step paths were rejected.
- Stop during the first frame produced decodable GIF/MP4; a subsequent capture
  succeeded; Finish was idempotent and empty capture emitted no media.
- With a 1,048,576-byte cap and 256x192 noise, GIF retained 15 frames /
  1,023,447 bytes; MP4 retained 15 frames / 488,093 bytes. Every partial frame
  decoded; dropped counts were nonzero and actual bytes stayed within the cap.
- Shared screenshot/GIF/MP4 retained 174,825 bytes. An oversized PNG wrote no
  file; byte accounting matched directory contents and the stop remained sticky.
- Sixty GIF frames over one second had exactly 1000 ms total delay. A 700-second
  final hold split into two decodable frames without delay overflow.
- GetProcessMemoryInfo for the entire final test process reported peak working
  set 37,982,208 bytes and peak committed memory 48,422,912 bytes. These are this
  small-fixture process's transient peaks, not retained artifacts or a production
  maximum-resolution guarantee.

Preflight CPU was 20%, with 13.57 GiB free RAM before the final run. One compiler
job and one software encoder test process ran sequentially.

Pending: runtime-owner CMake registration and full sandboxed native app build;
real browser entry point, HTTP/MCP/CLI flows; continuous capture of actual overlays;
manual viewing of user-produced media; published/installable release acceptance.
These checks are not claimed by encoder-level decode tests.
## Ownership and small-budget follow-up

The authoritative minimum follows the shared scriptCaptureSchema: 1024 bytes,
without upward clamping. When the first MP4 sample cannot reserve container
headroom, the output is empty with budget_exceeded rather than an oversized or
invalid file. GIF and PNG admit only outputs that fit their exact retained cost.

Lazy GIF opens use Win32 CREATE_NEW and hold the handle through finalization.
MP4 atomically creates its exact owned Win32 file and passes a native IStream
adapter to MF; the sink URL is informational. The handle denies delete/rename
until completion or exact-handle rollback. Byte accounting includes only this encoder's
owned files. PNG failure cleanup retains a duplicate handle to the exact newly
created file, marks that file for deletion on partial write/close failure and
never follows a potentially replaced path to perform rollback.

Follow-up regression cases cover two encoders created in the same directory
before either opens output, unchanged winning bytes, zero loser accounting,
completed sibling preservation, injected partial writes/close failure, canonical
1024-byte budgets, decoded MP4 chroma, padded stride and changing GIF palettes.
All follow-up cases passed in the coordinator's CODEC-2 slot on Maxis, together
with every earlier codec check. The same /W4 /WX compiler invocation passed with
no warnings. Native decoders verified MP4 U/V chroma and padded input stride as
well as changing GIF palettes. Both pre-created encoder collision cases preserved
the first output byte for byte, reported zero bytes for the losing encoder and
left the winning media decodable. A completed GIF survived an MP4 ownership error.
Injected partial PNG writes and failed closes removed only newly owned files;
a pre-existing PNG remained unchanged. Canonical 1024-byte budgets were honored
without clamping or oversized output.

The follow-up executable/artifacts are under .build-media/run-3. Preflight CPU
was 19%, with 23.80 GiB free RAM. One compiler and one test ran sequentially.
GetProcessMemoryInfo reported peak working set 37,859,328 bytes and peak committed
memory 49,905,664 bytes for this run. Earlier verification above is for 2a0858f0;
the follow-up has the same full-app/manual-verification limits.
## MP4 exact-handle failure cleanup

MP4 now opens a Win32 CREATE_NEW object with read/write/delete rights and retains
a duplicate cleanup handle. The internal OwnedMediaStream implements IStream;
MFCreateMFByteStreamOnStream wraps it, so MF never opens an output filename.
Finalization checks the MF Close HRESULT, native flush and both handle closes.
Failure cleanup marks the exact retained handle for deletion before releasing
handles. No filesystem identity query, path reopen or DeleteFileW(path) is needed.

Constructor failure after CREATE_NEW cleans through the original delete-capable
handle. A live stream denies rename/delete. After rollback, a newly created file
under the old name survives destructor cleanup. A completed stream releases both
handles without deleting output. Internal fault regressions cover constructor
duplicate failure, flush failure, close failure and replacement preservation,
alongside the full native codec corpus.

The CODEC-3 /W4 /WX compile and full native codec run passed on Maxis. The new
MF IStream adapter produced fully decodable output with the same colors, timing,
frame counts and budget results as before. Fault tests passed for constructor
duplication failure after CREATE_NEW, flush failure, first-handle close failure
and second-handle close failure after the first close succeeded. Rollback removed
only the held original object, a later replacement survived destructor cleanup,
and completed output remained intact. All prior decode, Stop/recovery, 1024-byte
budget, PNG cleanup, collision, sibling, stride, chroma and palette checks passed.

Artifacts are under .build-media/run-4. Sustained preflight CPU samples were
10%, 14%, 5%, with 23.95 GiB free RAM. One compiler then one native test ran under
the granted bounded-parallel slot. Test-process peak working set was 38,309,888
bytes and peak committed memory 49,696,768 bytes. Full native app/UI acceptance
remains outside this encoder test checkpoint.