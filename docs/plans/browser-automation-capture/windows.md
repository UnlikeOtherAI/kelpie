# Windows native automation capture

## Checkpoint

This implementation checkpoint has compiled on Maxis with shipping local inference enabled, pinned sandboxed CEF152 and static CRT. Dedicated worktree: D:/Worktrees/kelpie/capture-windows-20261104, branch codex/capture-windows-20261104. Base9b939695 (including main195eb90f); merged-main shipping rerun passed; actual HTTP/MCP/CLI browser capture flows are recorded below for 9333ff50. Computer Use is paused, so no native chrome or foreground-switch UI acceptance is claimed.

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

Exact candidate 9333ff50 has the machine-interface/media evidence below. Remaining physical UI and release gates stay open.

- [x] Required shared helper and codec follow-up revisions integrated.
- [ ] Release build uses pinned CEF bootstrap/sandbox and matching runtime assets; no warnings.
- [x] Native owner-scope/HTTP test, existing native tests and compositor/codec checks pass.
- [x] Direct HTTP, direct MCP and CLI MCP alias run the same strict workflow.
- [x] Native Stop via standard UIA, remote same-owner abort and status/download work during capture; physical clicking is unclaimed.
- [ ] Another grant/listener, invalid/revoked token, forged body owner and rotated grant fail.
- [x] Unique semantic button/label succeeds; duplicates, missing, obscured, disabled, moved and replaced targets refuse safely.
- [x] Trusted down-to-replacement/cancel releases native pressed state; next run works.
- [x] Fill/type cannot cross to another focused field and never echo values in progress/status/errors.
- [ ] Zero-duration pointer and both S/C curves work; no page hover from presentation.
- [ ] Native marker color/radius/wobble/fade matches GIF, MP4 and step PNG pixels.
- [x] Navigation tap PNG has the prior document generation; new-document frames have no old marker.
- [ ] Final fade and real elapsed timing survive decode/playback.
- [ ] Viewport/DPR resize, tall viewport, duration/byte limits and backpressure return truthful partial media.
- [x] Screenshot-only scripts enforce default limits and explicit steps without capture block.
- [x] Empty/failed/partial encoder finalization preserves valid siblings, cleans owned scratch and allows a next run.
- [ ] Actual changed native recording state has matching base/final screenshot evidence when Computer Use is cleared.

## Build plan

Use Maxis only, one Ninja compile job, a dedicated D:/BuildArtifacts/kelpie/capture-windows-20261104 output and D:/Temp/capture-windows-20261104 TEMP/TMP. Estimated incremental compiler/link headroom is 2–3 GiB, plus existing CEF/app memory for machine-interface verification. Reuse the pinned sandbox CEF SDK and matching /MT wrapper read-only after resource ownership is confirmed. Link Windows system libraries already supplied by the SDK: WIC, Media Foundation, crypt32, ole32 and GDI+. No new third-party runtime dependency is introduced.

Do not launch, replace an existing browser, build or use headed input until the coordinator grants the relevant resource/window ownership. The 9333ff50 hidden candidate has actual app-runtime evidence below; headed input remains prohibited.

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
| OBS-01 | Passed real value-free private-canary snapshot. |
| OBS-02 | Passed real scoped, prioritized, stable bounded snapshots. |
| OBS-03 | Passed real truncation and response bounds. |
| EXT-01 | Passed real scalar/missing/ambiguous extraction. |
| EXT-02 | Passed real ordered nested product records. |
| EXT-03 | Passed real allowlisted publisher metadata; forbidden JSON-LD absent. |
| EXT-04 | Passed real extraction URL/heading/source attribution across navigation; unavailable document revision remains explicitly unavailable. |
| RDY-01 | Passed real DOM status versus delayed task diagnostics. |
| RDY-02 | Passed canonical immediate readiness and unique-selector refusal. |
| OWN-01 | External worker managed-context isolation belongs to backend flavor; native supplied session IDs refuse before mutation. |
| OWN-02 | Real BUSY/admission and pressed-child replacement recovery passed; forced late timeout callback remains pending. |
| WFL-01 | Passed real malformed version/unknown keys/late action/limits/1001 steps zero-mutation refusal. |
| WFL-02 | Passed public alias typed input and secret binding; unresolved native refs refuse. |
| WFL-03 | Passed ordered readiness/assert/scroll/extract and failed assertion stopping later navigation. |
| WFL-04 | Windows had no working legacy runner; unversioned legacy remains explicit zero-mutation refusal. |
| WFL-05 | Passed real child replacement and focus races with uncertainty and next-run recovery; no replay. |
| TGT-01 | Passed real unique button/label, duplicate, hidden and disabled cases. |
| TGT-02 | Passed real clipped-center hit geometry and covered refusal. |
| TGT-03 | Clipped/scrolled centers passed at measured638x662 and 1042x662 with CSS zoom 1/1.5; actual DPR/visual scale1 only. Browser zoom/other DPR remain unclaimed. |
| TGT-04 | Passed moving/replaced/focus/navigation and added movie-hold rechecks. |
| TGT-05 | Passed fixture trusted=true and reported asynchronous CDP gap. |
| PTR-01 | Actual GIF/MP4 C and S pixel trajectories and endpoints passed; no page hover during presentation. Zero duration also passed. |
| PTR-02 | Numeric parity and composited media observed; displayed-native versus export comparison blocked. |
| VIS-01 | Actual PNG/GIF/MP4 red marker pixels inspected; native displayed overlay remains blocked. |
| VIS-02 | Actual early marker and clean faded endpoint inspected; native wobble/fade display remains blocked. |
| CAP-01 | Passed real GIF/MP4/step PNG and independent every-frame decode. |
| CAP-02 | GIF full decode/count/delay/dimension and native loop metadata checks passed. |
| CAP-03 | MP4 full decode, monotonic PTS, dimensions and duration passed. |
| CAP-04 | Step PNGs decoded; prior-document marker PNG inspected, including GIF-only explicit PNG. |
| CAP-05 | Actual old/new-document movie pixels passed; actual native viewport resize race remains pending. |
| CAP-06 | Passed duration/bytes/width/FPS/preflight bounds; main15FPS min intervals GIF70ms/MP470.534ms, FPS1 >=1s. |
| CAP-07 | Natural15FPS overrun passed:18retained+15dropped=33nominal slots over2166.5ms,351.6ms gap preserved. Encoder prefix/FIFO bounds tested; no forced MFT stall claimed. |
| CAP-08 | Passed native Stop via standard Session1 UIA InvokePattern, remote abort/failed status, partial decode and next-run recovery. Physical clicking unclaimed. |
| ART-01 | Passed separate Minis authenticated ID/chunk download of30 artifacts; all hashes and decoded frames match. |
| ART-02 | Passed same-grant API/MCP, invalid bearer and old-listener revocation; current grant immutable until listener drain. |
| ART-03 | Passed actual wrong run/pathlike ID/negative/string/oversized/zero range refusals. |
| ART-04 | Passed strict manifests/chunks and independent MIME/size/hash/duration/partial checks. |
| SEC-01 | Passed real native and CLI marked-secret encoded output redaction/status exclusion; capture refs preflight-refused. |
| SEC-02 | Passed malicious page instructions/forbidden metadata remaining untrusted observation text. |
| DIF-01 | Native corpus reports available; cross-renderer normalized comparison belongs to acceptance. |
| LP-01 | No Windows binary Lightpanda port; restricted external CLI worker evidence belongs to backend flavor. |
| LP-02 | External worker isolation/refusal evidence belongs to backend flavor. |
| WEB-01 | Actual CEF document.modelContext absent and native UNSUPPORTED observed. |
| WEB-02 | Native WebMCP stays fail-closed without trusted origin/API binding; no supported-native call claim. |
| DOC-01 | Public strict recipe/MCP examples exercised; candidate guarantee/limits documented. |
| UI-01 | Native Stop accessibility passed; actual owned-window After pixels await reviewed PrintWindow attempt. No CUA/desktop capture or matching screenshot claim. |
| REL-01 | Root owns integrated PR/version/release; pending. |
| REL-02 | Root owns signed published artifact/install verification; pending. |

### Percent-escape redaction follow-up
Raw sensitive text stays case-sensitive. Only hex digits inside encoded URI/form percent triplets compare case-insensitively. Mixed/lowercase hex, plain-text case differences and raw percent-literal regressions pass in native test_desktop_script_redaction on Maxis. The running8423 candidate is unchanged; app relink and public secret-path rerun remain pending.

### Movie cadence follow-up
Mandatory action PNGs may sample between nominal movie slots. Movie admission coalesces those milestones to at most the requested FPS; the nominal sampler deadline is not advanced for an early milestone wake. A1000-event burst cadence test passes at15FPS, and the affected sampler/service translation units compile on Maxis. Actual post-relink burst media evidence remains pending.

### Encoded navigation evidence and terminal status
A navigation tap with GIF or MP4 holds marker progress at zero until every requested movie encoder has retained the matching prior-document frame. The acknowledgment counts complete GIF source images and retained H.264 samples, not raw frame/MFT input acceptance. A bounded 18-record FIFO maps the common committed prefix to marker action/document identity. PNG-only workflows complete their sampled step without a movie acknowledgment. Each step PNG is written once.

This pre-input dwell is additional to the configured wobble/fade duration, which begins after acknowledgment. Sampling continues at the configured FPS; a10s evidence deadline, capture duration/byte limit, cancellation or grant revocation can refuse input and finalize partial media. Exact target/document/geometry is checked again before trusted input, whose CDP sequence still has an asynchronous gap.

Authorized v1 status queries always return success:true and strict metadata, including supportedVersions:[1], state and terminal runSuccess/runError. They never return action literals or outputs. Enter/printable trusted keydown carries CDP text; Control/Alt/Meta combinations do not insert text.

Maxis shipping LOCAL_LLM=ON/staticCRT/pinned sandbox CEF build and six focused native tests passed on 5 November 2026: media full decode/faults, compositor, encoded-prefix decode/budget/finalization, owner HTTP/MCP, redaction and key planner. Normal prefix test observed retained output before Finish and compared all acknowledged counts to native decoded media. Actual low-FPS movie pixel and final public-flow rerun remain pending at this checkpoint. Native overlay/Stop/foreground UI remains unverified under the explicit Computer Use hold.

Actual c852 FPS1 navigation runs exposed a compositor defect: encoder acknowledgment retained the marked presentation metadata, but drawing rejected its future start timestamp and produced no marker pixels. Both PNG and movie failure evidence is preserved under client .cache/capture-evidence/native-navigation-c852. Drawing now uses the same shared clamped progress as admission; a future-start pixel regression matches progress-zero pixels exactly. The bounded app/compositor relink and pixel test passed on Maxis. Real replay remains required before visual acceptance.

## Exact candidate and real interface results (5 November 2026)

Source 9333ff507ec91d06d86e338b1d2d9378daca2ac5, candidate version 0.1.15 (unsigned private verification build), sandboxed CEF152. EXE SHA-256: 54C8BE31E003853947182C9461755BF4E7BE5F91A2C64FCFB97ED5DA1A32D755; runtime DLL SHA-256: 27A474291206310A64E17CCE27F6F9C50836AF55B997B275D5F31E0FC71BCA8C. The DLL identifies the changed implementation. Public CLI package source e71364364db94a6212f556aa7b5ca9efb09ac003, package SHA-256: 3b686f74b3c29be62b531220112ab3a6ee745ceeeaebd534dcb5e422e8e24f73.

Supported browser register/launch --hidden created alias capture-9333 with an isolated profile. PID 29076 / start 2026-11-05T00:59:57.3753648Z, launch ID 932fe542158649e4e541ef75704c475686447c03c77ac0f93f05c558cab34dbd and exact socket 28420 were pinned and authenticated; MainWindowHandle0. No Computer Use or OS pointer input occurred. Other owners app/profile were preserved.

Permanent tests/windows harnesses exercised 34 native workflow cases (29 core plus 3 security, ordered actions and strict malformed admission), 10 canonical observation cases and 4 public alias CLI/MCP cases. All passed. Reports are under D:/BuildArtifacts/kelpie/capture-windows-20261104: native-flow-9333/report.json, native-security-9333-fixed/report.json, native-actions-9333/report.json, native-preflight-9333/report.json, native-observations-9333.json and alias-flow-9333-secrets/report.json. Earlier harness-only assertions were corrected to read CLI result wrappers and case-normalized redaction markers; their failure reports remain preserved.

Thirty native artifacts were retrieved by authenticated opaque IDs/chunks across an SSH forward to Minis. Every GIF/MP4 frame and every PNG decoded independently with single-thread Gyan FFmpeg; sizes, hashes, PTS, dimensions and duration match manifests. Client evidence directory: C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/native-flow-9333. cross-host-decode-report.json SHA-256: a7f42f1bc785b191a8e05a1233785249659686559da3a6355d35b96a0ad12963; marker-pixel-report.json SHA-256: f7dab46512b74c8aad49df4e4b626603f7a0bc409aa44fa502fd831c149dcc75.

FPS1 navigation with PNG run b380398683bca4af274a845639fe21aa838def10c21abf38 and movies-only run 918a92c63189a0134b3bfd584539bca08fda0f52698d19c1 each retained four GIF/MP4 frames. Actual source frames contain the red circle at the link center; destination frames contain no old marker. Movies-only MP4 78130e6d41df829566e8b968ad0c4da1c2659c0b6eed3adc-all-0002.png and -all-0004.png were visually inspected. Added-hold duration, abort and replacement all refused input and permitted the next run.

Physical native Stop, foreground/minimize/modal behavior, alternate DPR/zoom, forced encoder throttle and viewport-resize race remain unclaimed. No signed release/install or complete cross-platform acceptance is claimed.

### Evidence preservation and cleanup
The 6 final public alias recipe artifacts and 3 security-case artifacts were also fetched across the authenticated ID/chunk interface and fully decoded: 39 final-candidate artifacts total. The permanent tests/capture/verify-native-media.mjs replay passed for all 30 core artifacts and separately for all 5 FPS1 navigation artifacts with --red-marker. The native security corpus additionally passed actual encoded secret output/status redaction, malformed artifact identity/range admission and BUSY mutation versus responsive abort/status.

Normal CLI browser stop capture-9333 succeeded. PID 29076 exited; socket 28420, readiness and the CLI running record cleared without manual edits. The unrelated installed app PID 52960 remained intact. The owned SSH tunnel ended. Exact EXE/DLL/identity files are archived at D:/BuildArtifacts/kelpie/capture-windows-20261104/candidates/source-9333ff50.

The 48-record canonical ledger D:/BuildArtifacts/kelpie/capture-windows-20261104/windows-evidence-9333.json passes tests/capture/evidence.mjs. It retains pending or blocked rows rather than upgrading source/unit checks to native UI or release success. Preserve both assigned worktrees and ignored media/build evidence until the coordinator archives it; source is pushed, but these files contain unique verification output.

## Additional measured geometry, media and native accessibility

Supported hidden starts requested 640x1000 and 1600x1400, but actual native/page viewports were 638x662 and 1042x662. These measured values are the tested cases; no tall viewport or alternate DPR/browser zoom is inferred. Semantic clipped-center trusted hits passed at CSS zoom 1 and 1.5. CSS zoom is a page layout condition, not browser zoom. Extraction URL/heading/source attribution also passed across navigation. Reports: native-geometry-640x1000-9333/report.json (4 checks), native-geometry-1600x1400-9333-final/report.json (6 checks) under the Maxis artifact root. Twenty artifacts were retrieved by authenticated IDs across hosts and all frames decoded.

The permanent motion verifier independently recovered 40 C-path and 37 S-path pointer positions per format. C stayed on one side of its chord (23.65 to 60.53CSSpx); S crossed it (-22.82 to 22.80CSSpx). Final endpoint offset was 0x/0.326y CSSpx. Page events confirmed no hover dispatch before configured motion elapsed. Blue radius 12/fade-disabled and red radius 30/fade-enabled marker pixels were present, with clean final frames. These are media measurements, not native-window screenshots.

Absolute client contact sheets, also visually inspected:
- C: C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/native-geometry-1600x1400-9333-final/2c0cdc8991f33142edabce742196b9f32639cf3ecd90f717-motion-contact.png
- S: C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/native-geometry-1600x1400-9333-final/32bc5d03bec2e71a607cc5a347c853f7323a11e1c61729d5-motion-contact.png
- Prior-document marker: C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/native-flow-9333/78130e6d41df829566e8b968ad0c4da1c2659c0b6eed3adc-all-0002.png
- Destination without old marker: C:/Users/ondre/.codex/worktrees/capture-windows-client-20261104/.cache/capture-evidence/native-flow-9333/78130e6d41df829566e8b968ad0c4da1c2659c0b6eed3adc-all-0004.png

Existing public resize-viewport/reset-viewport calls returned BUSY during active capture; the native viewport stayed unchanged and abort/recovery passed. No arbitrary CDP, DPR or browser-zoom setter is exposed. The native resize implementation lacks NOACTIVATE, so it was not called live outside the admission-refusal test. An OS resize/foreground/minimize/modal transition remains a separate UI test.

The authorized Interactive/Limited on-demand task ran in Session1 through normal public CLI launch. Test source 4ec1496e0ad5b4305c2575a72b41072f1e499665, native source 9333, process 50156 / start 2026-11-05T01:52:44.9304340Z. Exactly one visible enabled own Button named Stop script under KelpieScriptStop exposed InvokePattern; one accessibility invocation aborted capture. Partial outputs passed ID/hash retrieval and all 3 files independently decoded; a new workflow succeeded. The public CLI closed the app and cleared readiness/socket/running record. The exact task was exported, verified and unregistered. Other-owner PID 52960 remained intact. No SetFocus, OS input, cursor, CUA or other window interaction occurred.

Raw evidence: D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-session1-9333/report.json and uia-task-9333-definition.xml/result.json/cleanup.json. The report records actual EXE/DLL/CLI/UIA-client/test-source hashes and protocol identities. The 3 UIA partial files were transferred by SCP of existing same-host authenticated downloads, not claimed as additional cross-host API proof. Source-only PrintWindow plan is windows-native-window-capture.md; no native-window screenshot result is claimed yet.
