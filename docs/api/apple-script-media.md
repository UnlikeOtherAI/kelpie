# Shared Apple script media

The macOS and iOS adapters use the same Foundation/CoreGraphics/ImageIO/AVFoundation source helpers. These helpers are a source checkpoint; native HTTP/MCP playback, actual renderer sampling, native Stop and installed app acceptance remain separate requirements.

## Source and platform boundaries

Explicit iOS Project.swift references may include these macOS-path files:

- ScriptCaptureError.swift: fixed public capture diagnostics.
- ScriptCaptureBudget.swift: one flat owned directory and its aggregate byte bound; exclusive output handles and rejecting ImageIO consumers.
- ScriptArtifactStore.swift: expiring authenticated-owner/run artifacts, streamed SHA-256, strict integer ranges and bounded byte chunks.
- ScriptGIFEncoder.swift and ScriptImageEncoder.swift: bounded frame-at-a-time GIF assembly and PNG.
- ScriptVideoWriter.swift and ScriptVideoSegmentSink.swift: native H.264 fragmented MP4 with rejecting complete-unit output.
- ScriptOverlayDrawing.swift: CoreGraphics composition using authoritative core-automation numeric presentation functions.

They import no UIKit or AppKit. Renderer snapshot, coordinate mapping, native view and sampler scheduling belong to each platform adapter. Include kelpie/script_presentation.h in the platform bridging header and link the existing core-automation library.

AVAssetWriter segment output is available from iOS 14 and macOS 11 in the pinned Xcode SDK; existing iOS 16/macOS 14 minimums are retained. CMSampleBuffer image timing and bounded CVPixelBufferPool allocation also support those targets.

## APIs

ScriptCaptureBudget(directory:maximumBytes:) owns one flat output bucket. output(url:) opens with O_EXCL; Output.write(Data)/appendUnit(Data)/close() preserve exclusive ownership. appendUnit rolls back a failed unit write. withConsumer(url:encode:) closes explicitly and removes only its newly created file if encoding or close fails. Output, queued PNG and encoder scratch buckets must be separate. No model field becomes a path.

ScriptImageEncoder.png(image,to:budget:) writes a PNG. gif(frames:fps:endSeconds:to:budget:shouldContinue:) returns ScriptGIFEncoder.Result(frameCount,durationMs,partial). Frames are timestamped staged PNG URLs. ImageIO encodes only one input image at a time under a 16 MiB scratch bound; Swift streams its palette and LZW subblocks into GIF89a. Loop count is zero, dimensions stay fixed, and cumulative centisecond quantization retains elapsed time. The complete next frame and trailer are admitted before append. Exhaustion after a valid frame finalizes a playable partial GIF; no valid frame returns an error. The optional Sendable shouldContinue callback is checked between frames; Stop/deadline after a completed frame finalizes a valid partial prefix, while cancellation before the first frame returns CAPTURE_CANCELLED without an artifact.

ScriptVideoWriter(url:width:height:budget:) requires the shared aggregate output budget. append(CGImage,seconds:) returns false under backpressure. One pending raw buffer supplies an explicit CMSampleBuffer duration when the next timestamp arrives; finish(endSeconds:) supplies the terminal duration. A three-buffer allocation threshold bounds queued raw memory. Presentation timestamps and durations use one cumulative 600 Hz timeline; independent duration rounding cannot shorten the movie.

The native writer emits complete initialization and moof/mdat units at a preferred 0.25-second segment interval, H.264 at 4 Mbit/s, with frame reordering disabled. Each unit is admitted through the rejecting file sink. No partial fragment is published. budgetExceeded, encodedFrameCount, rejectedFrameCount and durationMs describe committed media; no committed sample means no successful MP4 artifact. A complete retained prefix is partial. Finalization waits at most two seconds for input readiness before failing safely. Runtime capture and owner controls must keep their run gate through finalization.

ScriptOverlayDrawing.draw(in:size:viewport:pointer:marker:now:flipped:) draws native viewport points into a view or bitmap. Marker colors and capture canvases use explicit sRGB. C/S motion and marker scale/alpha use core-automation C ABI primitives. The adapter maps CSS/visual viewport coordinates once; this model sends no page hover or OS cursor input.

ScriptArtifactStore.add(url:runID:mimeType:owner:extra:) streams hashes in 64 KiB blocks and preserves validated partial provenance. read(body:owner:) returns runId/artifactId plus MIME/hash/size and base64 bytes; booleans, fractions, unknown fields, invalid ranges and foreign owners refuse. Retention is one hour with 256 MiB aggregate eviction. Normal transport authorization remains mandatory on every request.

## Reproducible verification

Run on macOS, with a coordinator resource slot:

```sh
bash scripts/testing/apple-script-codec.sh
```

The script uses only its ignored .cache directory, one compiler at a time and nice 10. It does not generate an Xcode project, start a simulator, launch an app or touch another native build cache. tests/apple/script-codec.swift decodes every normal GIF frame, checks palettes/delays/loop, stresses high resolution, exercises partial aggregate budgets and exclusive/close-fault behavior, and uses AVAssetReader for normal, min-cap, rejected-fragment, one-frame stop, next-run and backpressured MP4s.

Memory-retention checks use task_vm_info.phys_footprint because RSS includes variable shared/mapped framework pages. The suite keeps a separate resident sanity bound. Actual frame sampling, foreground UI visibility, request ownership, manual playback and renderer parity are not established by this standalone suite.

## Checked source checkpoint (4 November 2026)

On dictator, macOS 27.0 build 26A5378j, Swift 6.4, arm64 targeting macOS 14: the scoped eight-file SwiftLint pass had zero violations; standalone compilation had no warnings. The source-level codec suite passed GIF 400-frame decode/palette/loop/timing, 32/128-frame 1920x1080 encoding stress, aggregate-byte partial output, exclusive-file and injected-close failure, cancellation before first frame, cancellation after three valid frames and a subsequent successful GIF run. AVAssetReader passed normal 30-frame/1 s, retained 8-frame/0.266667 s prefix, one-frame 0.75 s stop, next recording 0.5 s, and 3-frame/34 s backpressure cases (997 rejected submissions). FFmpeg independently fully decoded the produced GIF, PNG and MP4 files.

The final stress run measured physical footprint 17.0 MB before high-resolution encoding, 36.7 MB after 32 frames and 56.0 MB after 128 frames; whole-suite peak footprint was 72.4 MB. Artifacts and logs are ignored under .cache/apple-codec/run-14 and .cache/apple-codec/acceptance-14.log. These are codec checks, not native renderer, UI, HTTP/MCP or installed-release acceptance.
