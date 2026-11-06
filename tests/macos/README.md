# Hosted macOS workflow acceptance

The existing macOS workflow defaults to compilation only. A coordinator can explicitly dispatch it with `runtime_acceptance=true` to build a separate clean app-only product and launch that ad-hoc test-signed app on that dedicated hosted runner. This never attaches to a local app, simulator, Device Hub, or existing listener.

The driver requires the checked-out revision to equal GITHUB_SHA, refuses tracked source changes, and pins executable/debug-library/CEF framework hashes, CEF version, PID and both public/app-owned listener owners. Startup waits for absent listeners but immediately refuses foreign or ambiguous owners; later calls require the exact owner. Bounded teardown records whether both owned listeners were released. It pairs through the native dialog using AppReveal's existing NSControl action interface. All web interaction uses public script/HTTP/MCP/CLI routes; no global mouse or keyboard helper is used. A synthetic local HTTP fixture records hit coordinates and document events without recording field values.

The initial corpus covers both WebKit and pinned CEF: native renderer selection; strict version discovery; semantic label/role edits and button centers; deterministic extraction with provenance; canonical status/readiness/snapshot; direct and generic MCP; ambiguity/obscured/disabled refusal; foreign owner status/abort/artifact; clipped/scrolled centers, replaced-hit uncertainty, focus-readonly recheck, strict whole-script admission, failed predicates, explicit screenshot semantics, duration/min-byte recovery, malformed and interrupted transfers, active-grant revocation and recovery; unknown session preflight; prior-output secret reflection refusal; native Stop with partial GIF and recovery; corrected scrolled-surface pixels; and one-FPS movies-only/all-format navigation markers. Every requested movie is fully decoded, including pre-navigation marker/document pixels. The common artifact-protocol helper also retrieves an actual deterministic native PNG larger than 262KiB over distinct HTTP, direct named MCP and generic MCP calls, comparing every bounded chunk and final bytes/hash; its transport callbacks honor cancellation. Public CLI pairing, typed workflow artifact download, pinned status and stdio MCP run on WebKit. A bounded public 15M fixture model is pinned by repository revision, SHA-256 and exact bytes before native inference.

Both recorded hosted attempts stopped before launch; actual native corpus execution remains pending. Runtime preparation uses .build-runtime and refuses any embedded XCTest/XCUI test frameworks, while the original build-for-testing product remains separate compile evidence. Runtime failure reports use fixed diagnostic codes. Pairing grants, raw app/CLI logs, recipes, model files and token stores remain private and are never uploaded. Evidence consists of bounded synthetic fixture media, app-owned screenshots and sanitized structured reports. The final report is not full platform acceptance: native pinch lacks a supported public input, and the complete canonical 48-item ledger still requires the remaining dedicated cases, including detailed curve/ease/wobble native-versus-export comparisons, renderer-callback/resize races, actual backpressure evidence and installed-release verification. Added safety cases remain unexecuted until a later exact hosted dispatch; source checks do not close those rows.

Run lightweight fixture tests with `node --test tests/macos/runtime-harness.test.mjs`. All driver modules support `node --check`; the signing script supports `bash -n`. The workflow runs these in its lightweight scope job, even for unrelated changes that correctly skip native compilation.

## Standalone synthetic writer calibration

`script-video-identical-frame.swift` is an isolated test source; it does not launch Kelpie or inspect a browser. It submits one frozen pointer-on-white image, then an intentionally varying negative sequence, through the existing `ScriptVideoWriter` and its actual budget/sink. A maximum of 40 attempts per case are made at nominal 20 fps; rejected appends are counted and not retried. The harness requires at least 16 accepted frames, no dropped output fragments and an 8 MiB combined output cap. It retains source ROI hashes and exact accepted 1/600-second ticks, never raw page pixels.

On an explicitly authorized macOS test host with Xcode, Node and FFmpeg, from the repository root, create a new ignored output directory by passing a path that does not exist to the standalone executable. For example:

```sh
mkdir -p .cache/writer-calibration
xcrun swiftc -parse-as-library tests/macos/script-video-identical-frame.swift \
  apps/macos/Kelpie/Handlers/ScriptCaptureError.swift apps/macos/Kelpie/Handlers/ScriptCaptureBudget.swift \
  apps/macos/Kelpie/Handlers/ScriptVideoSegmentSink.swift apps/macos/Kelpie/Handlers/ScriptVideoWriter.swift \
  -o .cache/writer-calibration/calibration
.cache/writer-calibration/calibration "$(pwd)/.cache/writer-calibration/output"
node tests/macos/script-video-calibration.mjs .cache/writer-calibration/output/input.json .cache/writer-calibration/output/result.json
```

The verifier reuses the bounded G08 frame stream and FFmpeg passthrough helpers, requires a 1/600 output time base and exact one-to-one accepted/decoded ticks, and checks the varying negative. It reports whether the stable input produced one or multiple decoded ROI hashes; either is an observation, not a tolerance or a G08 acceptance result. Mismatched counts, timestamps, size limits or a nondiscriminating negative fail closed. This source has not yet been run on the macOS test host.
