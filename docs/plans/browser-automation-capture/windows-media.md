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
1..256 MiB retained-media budget (default 64 MiB). Empty formats support
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