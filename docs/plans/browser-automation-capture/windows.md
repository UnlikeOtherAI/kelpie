# Windows native automation capture

## Checkpoint

This implementation checkpoint has compiled on Maxis with shipping local inference enabled, pinned sandboxed CEF152 and static CRT. Dedicated worktree: D:/Worktrees/kelpie/capture-windows-20261104, branch codex/capture-windows-20261104. Base9b939695 (including main195eb90f); merged-main shipping rerun passed; actual HTTP/MCP/CLI browser capture flows remain pending. Computer Use is paused, so no native chrome or foreground-switch UI acceptance is claimed.

## Contract and implementation

The existing authenticated loopback /v1 and /mcp entry points admit strict version:1 play-script. Unversioned scripts are refused by this adapter. The portable generated validator owns shape/defaults. Native admission additionally refuses unresolved input/secret references, duplicate output names, unsupported external session IDs and sensitive actions combined with capture or screenshot steps. It never resolves environment variables.

DesktopScriptHandler owns one synchronous run and blocks unrelated router work with BUSY. Status, abort and artifact chunks bypass the persistent MCP mutex, including generic extension wrappers. They still require the normal current bearer and immutable admitted owner. The owner is an opaque random listener incarnation scoped to the one local control grant; it is never accepted from a body or returned publicly. A listener restart or rotated grant cannot inherit artifacts. The local control grant is immutable for a listener lifetime; there is no per-client mid-listener revoke API. Trusted server admission is revalidated before each action and sampled frame. Listener drain/restart cancels future work through the run lease. Outbound account calls have no local owner scope and refuse script admission.

Progress contains action names/indexes, counts and elapsed time. It contains no authored action values. Terminal status removes outputs. Explicit terminal outputs are bounded to 256 KiB and recursively redact declared or DOM-inferred sensitive values. Errors use fixed codes and generic messages. Script bodies, token values and native output paths are not logged or returned.

### Semantic input and presentation

The shared ephemeral resolver retains exact object identity, document, visible clipped center, hit target and viewport. Pointer motion uses the shared core-automation numeric primitives. It never moves the system cursor or sends page hover events.

Windows input uses trusted CDP input. The adapter rechecks after pointer movement, before dispatch and between native commands. There is an asynchronous renderer-command gap between a check and a CDP event; this is explicitly reported as rechecked-before-dispatch-with-async-gap. It is not an atomic semantic input guarantee.

A native cleanup task releases a potentially pressed button outside the viewport and releases modifier keys on the same tab generation after uncertainty/cancellation. The engine's pending gate includes that task, so a next run cannot overtake cleanup. The action is never retried. Focus must remain on the exact text target before key commands. These paths require actual native race/recovery testing.

A transparent layered native window draws markers/pointer only over renderer bounds. A small separate native Stop button remains interactive. Both native display and exported pixels use the same compositor and marker timeline. Marker duration, radius, color, wobble and fade are configurable. Stop copies the run's immutable cancellation token; it cannot acquire another run's authority through a mutable request body.

### Sampling and media

The sampler runs on one worker and admits the first real renderer frame before visual actions. Each frame checks engine document generation and CSS viewport before/after the asynchronous screenshot. The duration limit is checked before acquisition; at most one in-flight snapshot/encode plus bounded finalization may complete after it. Navigation notifications clear the live presentation immediately, and owner-thread tab/generation/document validation filters queued stale displays. A changed document discards the mixed frame; viewport change stops with CAPTURE_VIEWPORT_CHANGED. Frames are scaled with fixed aspect ratio to at most maxWidth and 1920 pixels high, with even dimensions for H.264.

Presentation is latched and displayed at the screenshot request timestamp. Native animation pauses while that snapshot is in flight; later presentation updates are held until the frame completes or is discarded. Renderer screenshot completion is asynchronous; this is not a simultaneous operating-system screenshot of browser and native overlay. The exported overlay is composited from that same latched native presentation. No screen-recording permission or external ffmpeg runtime is required.

A tap step requests prior-document marker evidence before trusted mousePressed, then rechecks the target. Post-action frames show the resulting document without carrying the old marker forward. Step tickets distinguish multiple captures for the same action. A movie manifest's documentId names its initial engine generation, while each PNG names its sampled generation; the movie field does not imply one unchanged document throughout. Successful runs sample the final fade tail. Explicit Stop or limits produce partial media.

The codec worker owns construction, encoding, finalization and destruction. It uses WIC GIF/PNG and Media Foundation H.264 MP4 through the existing sandboxed CEF app path. WriteStepPNG shares the GIF/MP4 retained-byte budget. Limit admission stops sampling and finalizes valid partial outputs. Raw frame and codec transient overhead are separately bounded; maxBytes is the retained-media budget. Codec evidence and bounds are documented in windows-media.md.

Each run creates an exclusive temporary directory with a protected current-user/SYSTEM ACL. Only opaque artifact IDs, SHA-256, dimensions, timing and bounded metadata are returned. Chunk reads require exact run/owner, integer range and at most 1 MiB. They echo runId and artifactId. Files become inaccessible after one hour and are deleted lazily on the next artifact access/publication or service shutdown; global retained storage is bounded to 256 MiB. Valid sibling artifacts survive another encoder's failure.

## Native verification checklist

All items remain unverified until the exact candidate is built and exercised.

- [ ] Required shared helper and codec follow-up revisions integrated.
- [ ] Release build uses pinned CEF bootstrap/sandbox and matching runtime assets; no warnings.
- [ ] Native owner-scope/HTTP test, existing native tests and compositor/codec checks pass.
- [ ] Direct HTTP, direct MCP and CLI MCP alias run the same strict workflow.
- [ ] Native Stop, remote same-owner abort and status/download remain responsive during capture/finalize.
- [ ] Another grant/listener, invalid/revoked token, forged body owner and rotated grant fail.
- [ ] Unique semantic button/label succeeds; duplicates, missing, obscured, disabled, moved and replaced targets refuse safely.
- [ ] Trusted down-to-replacement/cancel releases native pressed state; next run works.
- [ ] Fill/type cannot cross to another focused field and never echo values in progress/status/errors.
- [ ] Zero-duration pointer and both S/C curves work; no page hover from presentation.
- [ ] Native marker color/radius/wobble/fade matches GIF, MP4 and step PNG pixels.
- [ ] Navigation tap PNG has the prior document generation; new-document frames have no old marker.
- [ ] Final fade and real elapsed timing survive decode/playback.
- [ ] Viewport/DPR resize, tall viewport, duration/byte limits and backpressure return truthful partial media.
- [ ] Screenshot-only scripts enforce default limits and explicit steps without capture block.
- [ ] Empty/failed/partial encoder finalization preserves valid siblings, cleans owned scratch and allows a next run.
- [ ] Actual changed native recording state has matching base/final screenshot evidence when Computer Use is cleared.

## Build plan

Use Maxis only, one Ninja compile job, a dedicated D:/BuildArtifacts/kelpie/capture-windows-20261104 output and D:/Temp/capture-windows-20261104 TEMP/TMP. Estimated incremental compiler/link headroom is 2–3 GiB, plus existing CEF/app memory for machine-interface verification. Reuse the pinned sandbox CEF SDK and matching /MT wrapper read-only after resource ownership is confirmed. Link Windows system libraries already supplied by the SDK: WIC, Media Foundation, crypt32, ole32 and GDI+. No new third-party runtime dependency is introduced.

Do not launch, replace an existing browser, build or use headed input until the coordinator grants the relevant resource/window ownership. No full-app capture runtime result is claimed at this checkpoint.

### First native compile checkpoint (4 November 2026)
- Maxis Release Ninja, sandboxed CEF152 pinned SDK, static /MT wrapper and app.
- Capture-focused KELPIE_LOCAL_LLM=OFF compiled all capture sources after fixing the Vista SDK declaration baseline to Windows7 and explicitly extracting the artifact run ID string for MSVC C++20 comparison.
- Final link exposed existing OFF-configuration missing LocalInference destructor/Execute/Cancel definitions. No stub was added. Next verification uses shipping KELPIE_LOCAL_LLM=ON; OFF is not a release or functional acceptance.
- Idle get-script-status exposes supportedVersions:[1] without past run state; owned running/terminal status also carries the marker.
- Overlay UI-thread Show/timer checks remain active during frozen capture latches, hide for another foreground or modal owner, and preserve owner/global Z order. Actual foreground/minimize/modal UI verification remains pending; Computer Use is paused.

### Compiled implementation evidence
- Shipping Release KELPIE_LOCAL_LLM=ON app build passed, including kelpie.dll and matching CEF bootstrap/runtime assets. Capture source emitted no compiler warning. Pinned llama dependency emitted C4068/C4244; test assertion enabling emitted inherited D9025 NDEBUG override diagnostics.
- Native CTest media encode/decode, compositor, typed output redaction and HTTP/generic-MCP owner tests pass. Owner test verifies bearer scope, body-owner spoof refusal, same listener grant across HTTP/MCP, invalid bearer401 and a separate listener nonce even with the same test-token spelling. This uses fixture handlers and is not actual browser-action acceptance.
- The initial owner fixture incorrectly read canonical MCP results outside value; test now checks the actual gateway envelope. No production bypass was added.
- Native redaction includes raw, URI-component and form-encoded sensitive value representations; protocol metadata stays outside the output-only scrubber.
- Media CTest uses a newly randomized owned evidence directory on every invocation. Generated media are preserved under the ignored build directory for inspection.

## Windows requirement ledger

Every canonical requirement is tracked here. Focused unit/source evidence does not close the corresponding real public-flow requirement. LP and managed-session rows are CLI/backend flavor checks; releases remain coordinated by root.

| ID | Windows status |
|---|---|
| OBS-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| OBS-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| OBS-03 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| EXT-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| EXT-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| EXT-03 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| EXT-04 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| RDY-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| RDY-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| OWN-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| OWN-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| WFL-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| WFL-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| WFL-03 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| WFL-04 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| WFL-05 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| TGT-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| TGT-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| TGT-03 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| TGT-04 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| TGT-05 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| PTR-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| PTR-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| VIS-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| VIS-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-03 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-04 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-05 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-06 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-07 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| CAP-08 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| ART-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| ART-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| ART-03 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| ART-04 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| SEC-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| SEC-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| DIF-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| LP-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| LP-02 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| WEB-01 | Pending native actual-API probe/grant binding; current catalogue fails closed. |
| WEB-02 | Pending native actual-API probe/grant binding; current catalogue fails closed. |
| DOC-01 | Pending public native/CLI flow; focused tests/source evidence listed above. |
| UI-01 | Blocked for native UI evidence: Computer Use paused; hidden API checks cannot close this row. |
| REL-01 | Pending integrated release/sign/install by root. |
| REL-02 | Pending integrated release/sign/install by root. |

### Percent-escape redaction follow-up
Raw sensitive text stays case-sensitive. Only hex digits inside encoded URI/form percent triplets compare case-insensitively. Mixed/lowercase hex, plain-text case differences and raw percent-literal regressions pass in native test_desktop_script_redaction on Maxis. The running8423 candidate is unchanged; app relink and public secret-path rerun remain pending.

### Movie cadence follow-up
Mandatory action PNGs may sample between nominal movie slots. Movie admission coalesces those milestones to at most the requested FPS; the nominal sampler deadline is not advanced for an early milestone wake. A1000-event burst cadence test passes at15FPS, and the affected sampler/service translation units compile on Maxis. Actual post-relink burst media evidence remains pending.

### Encoded navigation evidence and terminal status
A navigation tap with GIF or MP4 holds marker progress at zero until every requested movie encoder has retained the matching prior-document frame. The acknowledgment counts complete GIF source images and retained H.264 samples, not raw frame/MFT input acceptance. A bounded 18-record FIFO maps the common committed prefix to marker action/document identity. PNG-only workflows complete their sampled step without a movie acknowledgment. Each step PNG is written once.

This pre-input dwell is additional to the configured wobble/fade duration, which begins after acknowledgment. Sampling continues at the configured FPS; a10s evidence deadline, capture duration/byte limit, cancellation or grant revocation can refuse input and finalize partial media. Exact target/document/geometry is checked again before trusted input, whose CDP sequence still has an asynchronous gap.

Authorized v1 status queries always return success:true and strict metadata, including supportedVersions:[1], state and terminal runSuccess/runError. They never return action literals or outputs. Enter/printable trusted keydown carries CDP text; Control/Alt/Meta combinations do not insert text.

Maxis shipping LOCAL_LLM=ON/staticCRT/pinned sandbox CEF build and six focused native tests passed on 5 November 2026: media full decode/faults, compositor, encoded-prefix decode/budget/finalization, owner HTTP/MCP, redaction and key planner. Normal prefix test observed retained output before Finish and compared all acknowledged counts to native decoded media. Actual low-FPS movie pixel and final public-flow rerun remain pending at this checkpoint. Native overlay/Stop/foreground UI remains unverified under the explicit Computer Use hold.
