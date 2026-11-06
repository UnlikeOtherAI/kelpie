# macOS automation capture

## Scope and revision

- Owned worktree: /Volumes/External/Projects/kelpie-worktrees/capture-macos-20261104
- Branch: codex/capture-macos-20261104
- Original draft base: c01b2038bdb663cb9d5c7add134d587635da17ca; current integration prerequisite: 84b886b6333f741ac72adf2acc49e58189743e71
- Platforms required: macOS WebKit and CEF.
- Status: shared codec/redaction/gateway helpers checked; complete macOS adapter is in progress. Swift lint, exact native-core relink and Tuist generation passed. Full app compilation and installed WebKit/CEF flows remain unclaimed. Computer Use is disabled; no existing app process has been replaced.

## Existing behavior and defect

ScriptHandler forwards action dictionaries to existing routes, supports local Stop and remote abort/status, and writes screenshot responses to temporary files. It has no GIF/video encoder or remote artifact retrieval. HandlerContext injects temporary DOM markers. RendererEngine.takeSnapshot captures the renderer; CEF normally takes its accelerated surface, which excludes native overlays. Saving that image alone cannot prove a native marker appeared in exported media.

## Implementation

ScriptPresentation renders a hit-test-transparent NSView scoped to the renderer. Pointer motion is presentation only and does not send hover events to the page. Capture composites that same marker/pointer model into renderer frames. It does not depend on screen-recording permission or external ffmpeg.

ScriptCapture bounds PNG intermediate frames separately from retained outputs; the shared streaming GIF encoder admits complete frame units under the aggregate output cap. ScriptVideoWriter uses AVAssetWriter for MP4/H.264. Dimensions are even and bounded; the initial viewport is fixed. Resize terminates capture with CAPTURE_VIEWPORT_CHANGED. A document change during snapshot refuses the mixed frame. Between documents, previous markers are cleared. Encoder backpressure drops presentation frames and retains monotonic timestamps.

ScriptArtifactStore returns opaque IDs, SHA-256, MIME type and bounded chunks. It retains no public file paths. Download requires the immutable authenticated transport owner copied at admission. A listener incarnation, authenticated client and bearer digest form a private owner scope; neither digest nor authority is supplied by request JSON. Rotation makes old artifacts inaccessible. Revocation is enforced by normal transport authentication before each request. Outbound Nessie requests without admitted owner context fail closed.

## Input guarantee

RendererEngine exposes evaluateJS/evaluateBrowserControlJS and makeView, but no trusted pointer injection. Existing InteractionHandler.tapScript uses elementFromPoint and synthetic MouseEvent/PointerEvent sequences. New shared semantic dispatch must atomically recheck target identity, document, visible eligible bounds and hit-tested center before synthetic coordinate dispatch. Its guarantee is synthetic-coordinate, never trusted OS input. Presentation sends no pointer events.

## Verification checklist

Unchecked items are requirements, not completed evidence.

- [ ] Generate Tuist project, lint Swift, build with no warnings.
- [ ] Record exact tested revision, macOS version, WebKit/CEF versions and executable path.
- [ ] Stop stale Kelpie only after window/resource ownership is granted; launch one known candidate.
- [ ] Direct HTTP and direct MCP: strict v1 script, semantic button/label resolution, visible center dispatch.
- [ ] CLI MCP alias: same script and bounded artifact download.
- [ ] Unique target success; missing, duplicate, obscured, disabled and moved target refuse before dispatch.
- [ ] Navigation and resize during presentation refuse stale coordinates.
- [ ] Native pointer S/C curve, ease in/out; no hover change from presentation.
- [ ] Circle color/radius/wobble/fade appear in native view and exported screenshots/GIF/MP4.
- [ ] Decode and play GIF and MP4, inspect timing and overlay frames.
- [ ] Step screenshot taken before marker disappears.
- [ ] Local Stop and same-owner remote cancel finalize playable partial outputs.
- [ ] Another owner, rotated/revoked grant and listener restart cannot read/status/cancel a run.
- [ ] Failure during encode clears recording UI, preserves terminal metadata and allows next run.
- [ ] Duration/byte budget, encoder backpressure, viewport resize stay bounded and truthful.
- [ ] Match before/after screenshots only for visibly changed states, on actual base and final revision.
- [ ] Repeat the relevant flows on WebKit and CEF.

## Commands and evidence

Source-only focused SwiftLint was run on the four initial capture modules. Initial formatting issues were corrected. Full lint, generated build, XCTest and manual native verification remain pending resource ownership and shared contract integration. No screenshots or playable outputs have been claimed.

## Source checkpoint (not a native verification result)

The strict adapter is drafted against kelpie_browser_validate_script and kelpie_browser_script_target_expression, pending the shared generator/native ABI commit. It preflights before acquiring playback state. fill/type use shared atomic identity-bound editing; assert/wait-ready use shared observation mode. press-key is explicitly refused in full preflight because the current Mac renderer exposes no supported key-dispatch method; synthetic KeyboardEvent does not implement browser default actions.

HTTPServer establishes a private TaskLocal owner only after normal authentication. V1 copies this owner before awaiting. Legacy callers cannot reset the v1 owner while it is active. The recording gate remains held through encoding and final cleanup. GIF final encoding runs off MainActor so native Stop remains responsive. Current tests cover chunk ownership/ranges, deterministic path endpoints/bends and the finalizing gate, but have not run because native compilation remains held.

Focused SwiftLint passed on the changed Mac source checkpoint. No native build, XCTest, live HTTP/MCP, export playback or UI success is claimed. No commit has been made while required checks are pending. Source remains safely in the assigned worktree.

## Adapter invariants and remaining evidence

A versioned workflow is fully validated before admission. Supplied session IDs are refused with SESSION_UNSUPPORTED before any action until a real native owner-bound resolver exists. Admission acquires the existing browser lease and recording gate atomically, then releases the short lease for canonical inner extraction/readiness. Pending renderer callbacks retain the same fence until actual completion or renderer termination; uncertain input is never replayed.

Frames use script-only renderer capture: WebKit native snapshot callbacks, Chromium fixed Page.captureScreenshot commands. There is no OS-window crop, shell resize or cached-view fallback. The initial native and CSS visual viewport is fixed; resize or document transition during a sample refuses the mixed frame. The native overlay and exported overlay share one numeric drawing model.

At low FPS a real marker is held at progress zero until the next legal movie sample admits it. Its fade clock starts only after admission, followed immediately by exact token/document/viewport recheck and atomic synthetic-coordinate input. This dwell is internal, cancellable and absent for screenshots-only runs; it does not add a public timing field. Complete GIF/MP4 all-frame pixel evidence, especially a movies-only one-FPS navigation, remains required.

Every explicit screenshot step produces PNG even without a capture block or when authored formats only request GIF/video. Only the originally requested screenshots format enables automatic per-step PNGs. Pointed automatic PNGs occur before input with the native marker; other steps occur after their action.

The app links inference through the existing pinned native CMake llama bootstrap, not unidentified vendor binaries. Darwin enables CPU/Metal/Accelerate; other platforms keep their existing backend defaults. Actual ai-status and small supported inference smoke remain required after app handoff.

The MAC-APP-BUILD-1 helper resource admission initially printed saturated CPU readings but incorrectly proceeded to its bounded codec check. That check passed; it is not evidence that the admission rule was respected. Subsequent phases fail before any command unless all three CPU samples show at least 30 percent idle and memory has headroom.

## First complete compiled candidate

At source prerequisite bb12bf7e plus this adapter, macOS 27.0 / Xcode 27 SDK compiled both renderer paths and the XCTest target with build-for-testing, one nice-10 compiler. Full make lint-swift passed for iOS and 322 Mac files; Tuist generation used --no-open. Native CMake rebuilt all six core libraries from this worktree. The first app attempt stopped at missing Swift module llama; a permanent thin module map now imports the pinned bootstrap headers and the rebuilt candidate succeeded. Build logs are retained under .cache/mac-app-build.

The native dependency is llama source 8345f333951c661d166b00e6f9362e553768f292. GGML_METAL and GGML_BLAS are ON only for Darwin; iOS/Windows/Android/Linux retain OFF. CEF header and linked framework both report 149.0.6 / Chromium149.0.7827.201; existing CEF148 assets were not reused. AppReveal uses clean committed source3a28e56e5e72aa2a1f0b241cac63140e5906c8b4, without another worktree's dirty edits.

Warnings remain in unchanged AppReveal concurrency declarations, existing native categories/callbacks, deprecated UI calls, build phases without output declarations and the optional absent Gecko helper. The new ScriptCapture category declaration matches its implementation and no new workflow-file warning was reported. This is not a warning-free release claim.

No XCTest has executed and no app has launched yet. The known candidate is apps/macos/.build/Build/Products/Debug/Kelpie.app. Existing favorites app12718 and DeviceHub545 remain untouched. Actual owner-authorized app handoff, WebKit+CEF forms/extraction/readiness/session refusal, exact-socket CLI/MCP transfers, low-FPS all-frame GIF/MP4/PNG inspection, Stop/failure recovery and ai-status/inference smoke are still required. Named MCP script profile enablement is coordinated with the common registry owner after this checkpoint.

## Runtime plan after authorized app handoff

Computer Use stays off. Stop/replace favorites app12718 only after its owner hands over; reuse DeviceHub545. Pin the exact candidate executable/framework revision and one known listener before sending any command. The DEBUG app-owned AppReveal server on8421 provides documented list_windows, screenshot, tap_element and click_menu_item; failed bind or ambiguous target means no native-UI proof.

1. Pair through the normal UI with app-owned controls, then exercise direct protected HTTP, named/generic MCP and the CLI against that same pinned socket/grant. Capture state/status before play and verify explicit supportedVersions admission. Old/legacy active status must block v1 admission and recover automatically after legacy finishes.
2. Run WebKit and Chromium separately on a fixture with role/name, label, selector, clipped and ambiguous targets. Prove exact hit coordinates and field identity from fixture events; retry no uncertain mutation. Cover changed/obscured/replaced targets, viewport/document changes, hidden tabs, readonly/password fields, foreign session IDs and unresolved inputs before earlier mutations.
3. Exercise S/C movement, ease endpoints, configured color/radius/wobble/fade and presentation-only hover behavior. With wobble/fade disabled for a stable pixel comparison, capture the actual native overlay through the supported AppReveal screenshot and match its center/color/extent to decoded exported PNG/GIF/MP4 frames on the same document. Record timestamp and viewport mappings; unavailable native pixel source leaves this proof pending.
4. For each engine, run one-FPS movies-only navigation and all-formats navigation. Decode every GIF and MP4 frame and inspect the tap-colored region on the pre-navigation fixture document. Each requested successful movie must actually retain the critical marker; a raw-buffer acknowledgement alone fails acceptance. Check post-navigation document colors and ensure no later annotation fabricates pre-navigation evidence.
5. Verify screenshot-only defaults, explicit screenshot with GIF-only formats, automatic per-step PNG selection, screenshot-only duration expiry during a wait, FPS/dimension/duration/aggregate-byte caps, finalization byte refusal, cancellation, valid partial prefixes and a successful subsequent run. Any failed finalization must report failure/partial without claiming a guaranteed successful output.
6. Use native Stop through its app-owned UI identifier while sampling/finalizing; verify public metadata-only status remains responsive and same-owner artifact chunks recover actual bytes. Try foreign bearer/listener/run/artifact IDs, malformed offsets, revocation and interrupted downloads without leaking paths, outputs or secrets.
7. Exercise canonical readiness/assertions and named structured extraction/provenance, then compare direct HTTP/MCP/CLI output. Demonstrate sensitive input refusal/redaction, including short secrets and dynamic output keys, with no literal or reflected secret in public status/errors.
8. Query actual ai-status, load the smallest already-supported model through existing controls, run a bounded inference smoke with the pinned CPU/Metal/Accelerate graph, and unload through supported APIs. No unidentified vendor library substitutes or inference-disabled success are allowed.

Focused active-capture deadline regression is reproducible with bash scripts/testing/apple-script-deadline.sh. It verifies exact limit admission, refusal immediately beyond the limit, invalid elapsed values and separate stopped/finalization grace. The running workflow now checks this independently of whether a continuous movie sampler exists.

## Hosted compile evidence

[Run 41950256231](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41950256231) completed successfully on 2026-11-05 at 01:50:14 UTC for root 28426edc2fe9faffefea4a3df508786d5107bc15. The native job took 8 minutes 10 seconds on stable macos-26 ARM64: Xcode 26.6/17F113, macOS SDK 26.5, CEF 149.0.6, GGML_METAL=ON and GGML_BLAS=ON. Scope tests, pinned bootstrap, Swift lint, all six core/inference libraries, Tuist and full app/XCTest build-for-testing passed.

Diagnostics are retained as the run's macos-build-diagnostics artifact and locally under .cache/mac-ci-41950256231. build.log SHA-256 is 529feff5be14b40b4e989b90ffbadc1f68fb49aaf421b4314be191a5dcd30353. Existing warnings remain, including AppReveal concurrency/optional coercion, native categories/callbacks, deprecated UI calls, script output declarations, optional Gecko, absent accent asset and duplicate C++ linker flag. No warning was attributed to the new workflow source files. This is a successful compile, not a zero-warning, test-execution, app-launch, signed-release or runtime acceptance claim. No run was re-dispatched and no local app was replaced.

## Current-surface snapshot correction and bounded source admission

A focused protocol review reproduced an offset-only CDP clip defect after document scrolling. The pinned [Chromium 149 screenshot handler](https://github.com/chromium/chromium/blob/149.0.7827.201/content/browser/devtools/protocol/page_handler.cc#L1334) forwards clip coordinates into a viewport override. [Blink's transform](https://github.com/chromium/chromium/blob/149.0.7827.201/third_party/blink/renderer/core/inspector/dev_tools_emulator.cc#L418) accounts for root and visual scroll and reverses page scale. Layout-relative visual offsets alone do not identify the scrolled document region.

Two isolated, sandboxed Chrome 156.0.8078.4 probes used one synthetic page each, with no installed app or OS input. The first retained its Playwright emulation metrics, including a 400x200 CSS viewport versus 500x113 native surface and clip-induced resize effects. The second used viewport:null and a fresh native window: no-clip output matched the actual 800x513 surface and preserved scroll/scale. At scrollY 600 the no-clip and document-origin controls returned the expected cyan center; offset-only clip returned white. At page scale 2 the no-clip center was magenta and scale remained 2; clip variants reset observed scale to 1. This is independent protocol evidence, not exact CEF 149 app acceptance.

Original metrics, all PNGs and the initial failed default-browser lookup are preserved under .cache/cdp-clip-review and .cache/cdp-native-clip-review. The lookup failed before any browser launched; existing Chrome 156 was selected explicitly without installation. The durable regression tests/macos/cdp-viewport.mjs selects an existing executable through KELPIE_CHROMIUM_EXECUTABLE, records pixels/viewport/scroll/resize state and closes its owned browser. It checks the no-clip invariant and keeps the old offset path as a negative control.

The corrected bridge requests only the current compositor surface with fromSurface:true and captureBeyondViewport:false, without clip or viewport emulation. Before dispatch it checks native backing dimensions: maximum 8192 per axis and 8,388,608 pixels total. Source PNG allowance is 68 MiB, conservatively covering RGBA16 plus framing/compression overhead; base64 has a separate derived finite character limit. Dimensions and byte limits are checked again before ImageIO thumbnail decoding. Thumbnail and final output stay within requested maxWidth and 1920 maximum height.

These are separate allowances, not one total memory budget: native source raster/protocol buffers, one decoded thumbnail/composition, queued PNGs 64 MiB, GIF scratch 16 MiB and retained user artifacts (default 64 MiB, hard 256 MiB) have distinct bounds. No-clip does not admit arbitrary page-content-sized capture, and an oversized native backing viewport is refused before the screenshot command. Native resize/document/scroll during a sample is rejected; legal scroll or visual panning between samples is not a resize. CSS client offsets remain the pointer transform, while document page origin participates in before/after coherence.

Focused source-bound and geometry checks use scripts/testing/apple-script-snapshot.sh. Exact MacCEF scrolled/pinched native pixels, admitted-source stress and native-overlay/export comparison remain pending authorized app handoff.

Verification on prerequisite 881f066b: source-limit C++ checks, pure Swift viewport/deadline checks, the durable Chrome 156 protocol regression and full Swift lint passed. Incremental core-MCP/profile dependencies rebuilt 16 targets with registry/gateway/extensions 3/3 passed; CPU/Metal/BLAS flags were retained without rebuilding llama. Tuist and the final app/XCTest build-for-testing passed. Raw source-limit helper, codec and protocol evidence remain under .cache/mac-app-build and the recorded artifact directories; no app or simulator launched.

## GIF-only abort retention

A Mac caller that started GIF finalization after abort previously returned false before the first frame. It now snapshots that state and permits at most 2 seconds to retain a valid prefix, matching the shared Apple invariant; a new abort during normal 45 second finalization still interrupts between frames. The existing encoder's aggregate byte checks remain authoritative. A byte-limited result, expired finalization grace and abort are classified separately; failed/aborted artifacts remain partial.

Codec regression uses the actual caller policy, shared GIF encoder, full frame decode and artifact store: already-aborted grace retains three valid frames as partial, a newly arriving abort interrupts normal finalization, and the next GIF succeeds. Runtime acceptance must additionally run GIF-only capture, abort after frames are collected, retrieve and fully decode its partial GIF, then complete a fresh run without manual state repair. Native Stop and remote abort both need this flow through the pinned authenticated listener.

The abort-prefix codec suite passed in .cache/apple-codec-kmPkt9 with peak private footprint 75.3 MB. ImageIO decoded every retained frame; independent FFmpeg/ffprobe fully decoded already-aborted, newly-aborted and recovered GIFs, each 3 frames at 160x90 with 0.1 second duration. This checks the production finalization policy/encoder/artifact-store seam, not native GIF-only Stop acceptance.


## Explicit hosted runtime entry point

The macOS workflow now accepts manual runtime_acceptance (default false). After the existing verified compilation, it can test-sign and launch only its own candidate on a dedicated hosted runner. The source driver and current coverage/gaps are documented in tests/macos/README.md. No local app handoff or global input is used. This tranche adds the concrete inferred-sensitive prior-output regression for both renderers and pins failure-time media disposal independently of redaction success. Hosted execution and remaining canonical coverage are pending; syntax/lint/fixture checks are not native acceptance.


## First hosted runtime attempt: preparation failure

Run 41963343846 at source 589e31a3ca6513b16c3144dfbcdad8e299486d01 passed full app/XCTest compilation, then failed strict ad-hoc test signature verification before launch. The embedded KelpieTests.xctest had a linker code signature without a sealed bundle resource envelope. No renderer, pairing or capture flow ran; no runtime media exists for this denominator. Downloaded build.log SHA-256: a73bcd67cad31ba1c8fd69ee24c2617517c3c28419b12fc6595b5d2bc4e98188.

The first corrective checkpoint a96d3f28 sealed debug dylibs and XCTest bundles before their containing app, retaining deep/strict verification. This historical fix was superseded by the clean app-only product below after the second hosted attempt exposed additional copied SDK test frameworks. The same failure was reproduced on the owner's cached compiled bundle. On an isolated ignored copy, the corrected helper passed actual deep/strict verification; the original launcher d9dd958ecb2eea670cce5bc434a8d7d73bc5a84fc5a1819984f79dea8646a13e and debug library dc986bb2eefe19342eae7abdc65d33f5e21a58f914fb3b4c93a95f97a16185ee remained unchanged. This was signature verification only, with no local app launch or installed-app replacement. Preparation now writes a fixed structured evidence report before optional runtime dependency/signing work and records its failing exit code, so a pre-launch failure does not lose its evidence artifact.


## Clean app-only runtime candidate

Second run 41965358436 at b3f2d93ee42a758b065e38df8742bfa416d21d64 again passed full app/XCTest compilation, then stopped before launch. Its copied XCUIAutomation.framework retained an Apple resource seal naming Headers/Modules that Xcode strips when embedding test frameworks. Preparation.json correctly retained state failed and exitCode 1; there are no native screenshots/media for this denominator. Its build.log SHA-256 is 3172ca16051dea75d5282bda2ed8ec3e83e9fe5f8bba0fd70d72570e0f217345.

Runtime verification does not use XCTest. Preparation now builds the same app scheme with the ordinary build action into a separate ignored apps/macos/.build-runtime derived-data directory. The existing build-for-testing product/log remains separate compilation evidence. The signer and driver use only the app-only path, reject XCTest/XCUI/Testing bundles before signing, and retain deep/strict verification of the actual CEF/helpers/app. No SDK framework seal is repaired or verification weakened.

On the owner's Mac, the authorized app-only xcodebuild build passed at jobs 1/nice 10, without a native-core rebuild or app launch. Admission samples were CPU 38.74/34.06/30.73 percent busy and memory_pressure 41 percent free; no compiler was active. The build log contains 30 warning lines, including existing AppReveal/UI/build warnings; this is not a zero-warning claim. The actual clean bundle contained no test bundles/frameworks. On a fresh ignored copy, the normal signer passed codesign --verify --deep --strict --verbose=2. Original launcher e657b1b8728176ff45296c3b7f872207bad04d2f7ab0821b4124a0aacac6b339 and debug library bd8a8d2505bb4942954e068ccc8f52cf6e0bd05ed78673dd05103bc0faa5f386 hashes stayed unchanged. Logs/copy are under .cache/mac-app-build/runtime-app-only.log and .cache/mac-sign-preflight-app-only-41965358436. These checks prove the product/signing invariant only; exact hosted native flows remain pending.


## First native process bootstrap attempt

Third run 41967316667 at c71aeabd513c4d19c5088cbae7202cd59fbb95f6 passed both compile products, clean app-only checks and strict test signing. It spawned owned PID 20936, then timed out after 30 seconds before pairing or any renderer corpus. No native screenshots or media were created. Pinned launcher SHA-256: 535dfa42ca8ea56acd6b12f8515931054b83d78fd01cc4c86d81a3c662023073; debug library: 0cffbcf1d4b6d291ae70bfc34209c0d4b0333eb08e214a17aaf3d247e1d9038a; CEF version 149.0.6+g0d0eeb6+chromium-149.0.7827.201. Build log b331922243402503454ee61a803531ddb32cbeb5d4ce0b056f33464b9c75ac5f and app-only log 2d57ced3bd29ec4880db494cf75ce0be2ed4049501dc44ec0729e0fcd688edbe are preserved under .cache/mac-runtime-41967316667. Preparation reported ready; child/listeners were released, but the original report lacked early exit and port-transition detail. Zero stdout bytes does not establish where native startup stopped.

Startup diagnostics now record exact exit code/signal/phase, bounded listener-state changes, owned executable/debug-library mappings and owned listen ports. If the exact executable is still alive before pairing, the standard sample utility runs for one second; only bounded sanitized function symbols enter the report. Matching fresh crash reports retain fixed exception/termination fields and sanitized stack symbols, with exact PID/path checks. Raw samples/crash text are not uploaded. Missing-PID spawn failures skip process cleanup and retain their primary error. The no-child guard and actual owned Node-process executable/sample path were checked without launching a browser app; the latter yielded 41 bounded symbols. Native bootstrap root cause remains unclaimed until those diagnostics run. No launch-method or signing change was made on this incomplete evidence.


## AppReveal-only startup failure and integration correction

Fourth run 41971404738 at 8a2ecc5571e64e4bce872c3ef2cc130c5c561458 passed preparation. Exact owned PID 18337 mapped the expected executable/debug library, entered the AppKit event loop and owned native HTTP port 28420 by 1.5 seconds. AppReveal 8421 never appeared. The process remained alive at timeout; it exited only by the driver's cleanup SIGTERM, with no matching crash. No pairing, renderer corpus or media ran. This establishes an AppReveal-only failure, not a failed native app launch.

The pinned SDK's docs/macos.md requires NSBonjourServices _appreveal._tcp, which the app omitted. Its public start schedules a fresh listener every time; Kelpie's init/onAppear startup calls could therefore overlap before bind completed. The source now declares the required service and latches a DEBUG start request before scheduling the SDK. Existing launch, SDK revision, strict signing and ordinary pairing stay in place. NSUnbufferedIO is set only on the owned hosted child, and a pre-pairing parser retains fixed startup/error labels without raw log text. Listener recovery still needs the next exact hosted result; these source defects do not establish that both caused the observed failure.

Plist validation, driver syntax, fixed-label/fixture tests 4/4 and full SwiftLint (0 violations) passed. The first local incremental-build admission refused CPU readings 97.16/83.34/71.35 percent busy before xcodebuild. No compiler, core rebuild, app launch or other-owner process change occurred. Per coordinator authorization this is an explicitly compile-deferred source checkpoint; the next hosted build must validate it before any runtime claim.

### Hosted startup result: 41977980924

Exact source `bd2c36ae861ba98b4fbd37a54d0e0075f3b659b3` compiled and passed app-only preparation/signing. Owned PID21286 exposed HTTP at2558ms and AppReveal at3061ms. Normal native pairing, AppReveal WK renderer selection/screenshot (900×544), and direct/generic strict capability checks passed. First fixture navigation failed `FIXTURE_NAVIGATION`; no workflow, media, inference or Chromium runtime acceptance is claimed. Both owned listeners and child were released.

Original sanitized report SHA256 `801f038bf5844fd6eaff45234fa77881beea570e905956133e63508984140edd`; original native screenshot `c13ed028abef404b27cefe3cd39aae595fdff61f0f2d4df4cd7b82c7e44fc230`. The next candidate adds DEBUG-only allowlisted native navigation outcome labels; no URLs/error messages leave the parser, and navigation behavior is unchanged. This run predates the late-sensitivity consumer checkpoint.

## Hosted normal-build intake: 42122266746

[Run 42122266746](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42122266746) exercised exact source `455d1923677d7b143bbb0e13719546827af221e4` on the owned hosted macOS app with the default CEF pump. It failed overall; neither renderer has full acceptance. The original report SHA-256 is `ac4c46985f00aa6afec648efa3a407786350fbbf8a3484682c654928ab9fbbdc`. Executable SHA-256 `27818adc83efcfee3d9c37d8f97120d643a2bf32add43af8b92ea3ab6cf02574`; debug library `cad38d8d8999ffe6b7a5af6cce1cc5750639e79f50cc85411563cde8323d3781`; CEF 149.0.6 framework `84ea6deaad0a7609a377c4e0eca6ec6f860688a0303eb12495a2505bcd807970`. The owned child exited and both listeners were released. The Mac owner retained original runtime and build artifacts under `.cache/runtime-42122266746/` and `.cache/build-42122266746/`.

Both WK and CEF passed no-capture and PNG-only retained-marker checks: the marker remained visible after the response and retired on a new run or expiry. Both retained visible chrome while the native Stop control aborted each run and the next run recovered. The accessibility tap reported success for disabled More, but the renderer menu did not open and playback remained active. The hosted admission suite ran 19 tests with zero failures, including the retained-accessibility and movie-only policy cases. These are scoped checks, not proof of every keyboard or drag interaction.

The original changed-state running PNGs for no-capture and PNG-only were identical within each renderer: WK `43c17616502e9fbf3c78186d4ff1cefa7608ca2953ecfc5dee6f21049b336919`; CEF `0bef449a35f76979649e330b1f5c10260ee8914ee454b4b486da83cbbd7444a1`. They are final-state images only. Exact base-revision pairs remain a separate PR screenshot requirement.

Both engines passed early and prefix GIF Stop/recovery, both 1 fps navigation format combinations, and the scrollbar-edge PNG check (WK 0.68 px error; CEF 0.77 px). WK's combined GIF/MP4 omitted-duration motion passed with six intermediate samples, 80 ms maximum gap and 350 ms fits 5.49/5.86 px versus 500 ms fits 99.00/93.82 px. WK's separate video-only acquisition was `FAST_INSUFFICIENT_CADENCE`. CEF's two omitted-duration acquisitions were `FAST_INSUFFICIENT_SAMPLES`. WK's two-second C/S curves passed; CEF's C/S checks returned `CURVE_INTERMEDIATE_SAMPLES` and `CONFIGURED_MARKER_COLOR_AND_END`.

WK dense G08 GIF passed for C and S; both MP4s were insufficient because the pre-dispatch baseline was unstable. All four CEF dense G08 format/curve cases were insufficient for dense motion samples. The original media and analysis reports are retained; no lossy-codec cause or dense pass is inferred. The separate same-host pump experiment in run 42117517204 remains test-only and did not satisfy the 350 ms export oracle.


## Isolated CEF stream diagnostic checkpoints

These compile-gated synthetic-fixture experiments are not production capture acceptance. Each used the owned hosted macOS app and default CEF pump; no local shared app or global input was used.

[Run 42127069319](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42127069319), source `43dee192b7f5ba79f62c9685c3cb1cff3d1b5bd6`, failed app/XCTest compilation because the test-only fixture origin serializer referenced a nonexistent method. No app or stream ran. The retained build log SHA-256 is `252805b0f2bfadf7a32584dcd799ecd6a0c891288c29356ac40545dddeb60d33`.

[Run 42128235784](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42128235784), source `b24bca642df007c4b69a8d4e8ad9f37c329e496b`, compiled and reached the owned CEF renderer. Synthetic cadence failed `STREAM_EVENTS`: both attempts started and were discarded, with no admitted samples exposed. The document-transition check reported a discard, but that alone did not establish its cause. The child exited and owned listeners were released. Report SHA-256: `ebe1dd7d73972ff4511627a0575a84aeb824c1f47d370b88adf18eaa93b4f53e`.

[Run 42130153534](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42130153534), source `41d8d86e81731bb0fe036f68918b0f6df155c184`, added bounded refusal facts. The positive fixture received and consumed 54 events: 27 were submitted for decode, 26 dropped while a decode was pending, and one requested a fence stop. No malformed event, metadata mismatch, ACK failure, decode failure, ingress overflow, agent detach, admission identity failure or nonfinite protocol timestamp was reported. Stop succeeded, but final seal refused and no samples were exposed; cadence remains unproven. The document-transition attempt received two events and was discarded on the final authority path. Its negative check passed without exposing frames. Both listeners were released and the child exited. Report SHA-256: `2ec308bfef380164871f59c4372ae9802b84246f8fb72bdf81fe5d44e5ad6d97`.

Original reports and build diagnostics remain in the Mac owner's `.cache/runtime-42128235784/`, `.cache/build-42127069319/`, `.cache/build-42128235784/`, `.cache/runtime-42130153534/` and `.cache/build-42130153534/`. A later first-cause diagnostic is separate; these results do not identify why the positive seal refused.


[Run 42131949014](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42131949014), source `2427efdb835b12e3c796ac04260ac0a4560bbc38`, identified a finite protocol timestamp regression as the positive fixture's fence stop and invalidation. The seal refused and no samples were exposed. The document-transition case discarded on the authority path, and the owned listeners and child were released. Report SHA-256: `3c9975ee4262152b7b515866861df659a9354abf18b1ae936b428f3a046f7bb9`. This identifies this run's cause only, not 421301's.

[Run 42133759390](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42133759390), source `770a0cab2ec528d76dfc5ee6c027c84fdf52ed19`, passed its isolated synthetic stream scope. Of 65 received events, the 64 accounted before the cap included 38 submitted for decode and 26 dropped while decoding; no stale timestamp appeared. The 38 exposed synthetic moving-square samples spanned 2,360 ms, with a maximum 277 ms receipt gap and 341 px range. The separate existing snapshot-based MP4 decoded six frames with timestamps from 0.753 to 3.417 seconds. The document-transition case discarded on the authority path with no samples exposed; owned listeners and child were released. Report SHA-256: `ceea67715590b32bae2b5e1624e974c8054ac5d787662453544a7033f456cc39`. The stream and MP4 are separate paths; this experiment does not establish production export cadence or 350 ms acceptance. Original runtime and build diagnostics for both runs are retained in the Mac owner's `.cache/runtime-42131949014/`, `.cache/build-42131949014/`, `.cache/runtime-42133759390/` and `.cache/build-42133759390/`.


[Run 42138642421](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42138642421), source `3f1bd3cb86310f734889169f62f2ae658d76bd7e`, compiled the app and executed the isolated hosted `cef-overlay` scope. Its animated-fixture C check failed the unchanged `CURVE_INTERMEDIATE_SAMPLES` oracle. The separate navigation-change negative passed, discarded on the authority path, and exposed no new private output. The owned child exited and listeners were released. This is not static-page, 350 ms or production acceptance.

The nonce-bound diagnostic MP4 decoded 77 frames, with PTS 0.787–7.740 s, SHA-256 `b18736da96e51f607a976bfbfb8e458af8da100992835ec2bcbcb769b02f1473`. The separately recorded normal snapshot MP4 decoded 11 frames, PTS 1.268–7.733 s, SHA-256 `d7b3c76b9da90fff5dbf56074e2cd5900b5e1ab91a5f873df944b9476c52544c`. The stream received 161 events, consumed 160, admitted 77 decodes and dropped 83, including 10 stale timestamps; it stopped without reaching a cap and recorded no metadata, decode, ACK or ingress failure. Report SHA-256: `dfc4d816ff5b23ef6a4b385801c36984895deceaf2cdcd96a0979fc51a41002a`. Original media/report and build diagnostics are retained in the Mac owner's `.cache/runtime-42138642421/` and `.cache/build-42138642421/`.

An exploratory connected-component read of the retained diagnostic MP4 found that dark edge pixels from the animated page square contaminate the existing oracle's global dark-pixel bounding box. At PTS 5.580 s, the pointer-shaped 54-pixel component at (173,169) shared a frame with a thin 22-pixel component at (273,85), producing a 100×98 global box that the oracle rejects. Pointer-shaped components also appeared at ten distinct intermediate positions between 5.315 and 6.130 s, and near the inferred CSS endpoint at 6.348 s. The exact click-event receipt was not retained, so this analysis does not prove trajectory, timing or acceptance; its bounded facts are retained separately as `component-analysis.json` beside the original report.


[Run 42140865567](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42140865567), source `230b05376029da081d949cf1a3634db30b1311c3`, passed the isolated animated-fixture C overlay diagnostic and its independent navigation-disposal case. The unchanged C oracle observed 70 pointer samples, a normal range of 23.79–59.91 px and endpoint error 2.13 px. Measured click centers were (55,245) and (555,75) in a 900×700 viewport, with 3,085 ms between clicks. The navigation-change case detected identity loss and discarded on the authority path without publishing a new private output. Owned listeners were released and the child exited.

The nonce-bound stream MP4 decoded 81 frames, PTS 0.807–8.020 s, SHA-256 `3fd5fd062565d8f1d47806a2cfabc5a3249c2163456959bf55a70fa1f091ab34`. The separately captured normal snapshot MP4 decoded 13 frames, PTS 1.510–8.028 s, SHA-256 `da48660f8ea8fbfe3edd0875b567033b49d5ac7eff3b15c0e83083a062cf8dc9`. Of 166 received stream events, 165 were consumed: 81 decoded and 84 dropped, including seven stale timestamps; no metadata, ACK, decode or ingress failure was reported. The hosted H.264 positive/negative classifier control and native diagnostic controls passed. Report SHA-256: `d7c54da9fa29c52ef243a5d14729f1e984e7b681b06be77fc8d0f91d24d72406`. Original runtime and build artifacts remain in the Mac owner's `.cache/runtime-42140865567/` and `.cache/build-42140865567/`. These are animated-fixture results, not static-page, S-curve, omitted-duration 350 ms, or production-stream acceptance.

[Run 42142944187](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42142944187), source `ac7fa34982d6b5161fbca109cc9a51920481c59f`, passed the isolated static-fixture observation. The per-run non-auth visual nonce was checked on admitted stream frames. The fixture reported no CSS or Web Animations at document load and both ordinary synthetic clicks; the recorded click centers were (55,245) and (555,75) in a 900×700 viewport, 2,913 ms apart. These three checks and the static fixture source do not prove that every page pixel remained unchanged throughout the run.

The CEF observer received and consumed 18 events, decoded 17 and dropped one, with no stale timestamp, metadata, ACK, decode or ingress failure. The actual nonce-bound stream MP4 contained 17 decoded frames, PTS 0.828–8.033 s, SHA-256 `b14dd3a1be427ad4c4ca1427441be18fc9f3a7b514e2182054ef550d872b2dac`; the separate normal snapshot MP4 contained 16 frames, PTS 1.157–7.898 s, SHA-256 `c2fdd751605539eed5c6a1aff1fc07e009c612db6c08ae628531685428b9fccd`. A real stream file was produced: the sparse/no-placeholder branch was not exercised by this run. Owned listeners were released and the child exited. Report SHA-256: `12c98b4d50c05fafae1d63bb058ba71fd22eebf0ac860fa79d7c8b168b9705d6`.

A bounded local decode of the retained stream video compared two fixed regions away from the pointer path. The 80×100 white background region was byte-identical across all 17 decoded frames; the 11×11 square interior differed by at most two RGB levels. These encoded-video observations do not distinguish source repaint from codec variation and do not establish whole-page pixel identity. The raw stream events are not evidence that every event is a fresh page observation. Original report and both MP4s, rehashed after copying, are retained in the isolated Minis worktree under `.cache/runtime-42142944187/`.

The stream experiments are not ready for production use. A production design still needs a trusted binding between each admitted frame and its document/paint identity, or a separately disclosed presentation policy for reusing the last validated page image, with explicit invalidation and no claim that repeats are fresh page observations. Static-page, S-curve and omitted-duration 350 ms production capture remain unverified.

## WebKit dense MP4 calibration review

The retained [run 42122266746](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42122266746), source `455d1923677d7b143bbb0e13719546827af221e4`, contains pre-dispatch baseline samples for both WebKit MP4s. Reconstructing the unchanged G08 selector from its retained measurements yields 16 C candidates at 7,536.667–8,475 ms and 14 S candidates at 7,606.667–8,375 ms. Their measured pointer coordinate was stationary at (480,248) and marker alpha was zero. The verifier rejected both MP4s as `INSUFFICIENT_EVIDENCE unstable pre-dispatch baseline`; their paired GIFs passed. The same run's separate combined-format omitted-duration 350 ms case passed, while its video-only case was insufficient. Neither result establishes dense MP4 acceptance.

A bounded RGB decode of the exact 97×97 calibration ROI, limited to 7.6–8.37 s, found two distinct ROI byte patterns in each MP4: 11 C frames and 14 S frames, with up to 160 changed pixels per frame and a maximum six-level channel difference. All differing pixels were confined to encoded-frame coordinates x476–496 and y244–266, around the stationary pointer. The corresponding sampled GIF ROIs each had one byte-identical pattern. The exact equality oracle therefore explains the reported refusal; these observations do not determine whether the MP4 difference originated in native rendering or encoding. They do not justify changing the oracle or claiming an MP4 pass.

The original report SHA-256 is `ac4c46985f00aa6afec648efa3a407786350fbbf8a3484682c654928ab9fbbdc`; its G08 analysis is `b90976cc088ec6ca681b9c96b65d514991c023178a71dd773fad68dc1d42901e`. C MP4/GIF hashes are `784677651fbbae18129e31cdbb31fdb83d724f573b5d138f615c8892b59a3ceb` / `8bb92e75d3a6b202ee4c1abc396efa032ec004b257bc0e0f2d020d947df28028`; S MP4/GIF hashes are `ed8b40aa1859f7a18b7a270382860ea59f368d4c69c5f7ec1d0e325e2a7833ee` / `d36b13c273b0667d4f068707252cdbbdbfe8f9fc5776d41e146ef4cb45ae4b73`. The bounded derived ROI receipt SHA-256 is `4c37dbc1f388379a5cee7a9f1a74753230226b486fa56b7cf2e019e8168460f0`; original artifacts and receipt are retained in the isolated Minis worktree under `.cache/runtime-42122266746/`.

A discriminating follow-up would instrument the existing fixture-gated capture path to retain a bounded pre-encode calibration ROI hash and timestamp for each writer-accepted source frame, then match committed records to actual decoded MP4 frame PTS. An independent controlled H.264 encode of identical source frames would establish that encoder's behavior on the same owned host. Identical source ROI hashes with differing decoded MP4 ROI bytes would isolate the change to the encoding/decoding path; varying source hashes would require examining rendering and presentation first. The exact RGB oracle and original receipts remain unchanged; this is a test plan, not an executed native result.

## Standalone identical-source writer calibration

[Run 42147677381](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42147677381), source `4ce9675826b4ba83d4b7ce848cd47d22208cd62c`, ran only the opt-in synthetic writer calibration on hosted macOS arm64; the ordinary app input and build jobs were skipped and no app was launched. The frozen pointer-on-white source produced one source ROI hash across all 40 accepted frames, but 12 decoded H.264 ROI hashes. The intentionally shifted-pointer negative produced two source ROI hashes and 14 decoded hashes. All 40 accepted ticks in each case matched decoded PTS exactly at the declared `1/600` track time base; no append or segment rejection was reported. The result demonstrates decoded ROI variation after a fixed synthetic CGImage enters this writer path. It does not identify the cause of the separate native 421222 WebKit capture, whose pre-encode frames were not retained, and does not change the exact-RGB oracle or establish a dense MP4 pass.

Input manifest SHA-256: `ffe65abd486c9725976131fb193fb573f79e557ca5ec9276f5d6a1a93ffd51d9`; result manifest: `28da8a71bc1b834a676a180aa65ee6fda1eb0d15f9b032f5a1d3b28f18503346`; stable MP4: `24d84af91d1789793604aea050ccef3d33282a5e611eed3603365ecf563cfb65`; varying MP4: `dedb505dcd6791c4ed6a459dbac001577d2b214b5939b3434c5c71ee99a557bf`. The result records the exact Swift compiler and FFmpeg/ffprobe versions and binary hashes. All four original files are retained in the isolated Minis worktree under `.cache/writer-calibration-42147677381/`.

## Synthetic faint-marker controls

[Run 42149248875](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42149248875), source `235070395032b1d1ae0ee6d889fee2829382414f`, ran only the standalone hosted synthetic writer calibration; the ordinary macOS input and app-build jobs were skipped. Each of six independently encoded cases accepted and decoded all 40 frames, with exact matched 1/600-second PTS and no append rejection. The fixed test-only metric sums positive red-channel excess over the larger green/blue value in the 97×97 ROI. The clean training maximum and independently encoded clean holdout maximum were both zero.

All three predeclared red marker regimes, centered on the synthetic pointer tip, were **insufficient** under that fixed metric. Radius 3 px / alpha 0.02 was marker-indistinguishable: its minimum marker score was zero and its clean-tail maximum was zero. Radius 3 px / alpha 0.10 and radius 8 px / alpha 0.02 failed the clean control, with tail maxima 142 and 79; their minimum marker scores were also zero. At exact accepted ticks, the first two and first one marker frames respectively scored zero in those latter cases, and their first four clean-tail frames retained the cited nonzero scores. No startup, GOP or delayed frame was excluded. These synthetic observations do not establish the mechanism or prove native marker retirement; no tolerance, primary-oracle change or retrospective native MP4 pass follows.

Input and result manifest SHA-256 values are `0d8efcbc417a783e14f35440b2ca2f00d2fe3e6af5a886dc0c2080d5cd837b5e` and `87a8706ce030e5329429438776b25ba7d6f707e9caf0f195a2c445e2175d164e`. Stable, varying and held-out clean MP4 hashes are `acc281dda9494fc6a8f583a45523f2e1c59f3d280ba5ac9926b65b23acb35ae0`, `dfa69b4acf20da530988782136d39ee3dd7af25c33051a44c0c714ed900f64de`, and `323ea36e76b3bf0de5b9d6c27454e7f0303de95fd0f600de5d35b4d5ec2244f9`. Small-faint, small-visible and medium-faint hashes are `07a1c2a10b6bbbd88c382f6c0cde68f3cef682b4f74fd16d42e96cc0c959bf50`, `fa84d6f84b3e40da00c3f379b6b3d764b860075277f1234dd770527a43e60f69`, and `f890f4ca70e01c8b687715d1c16b5405c3cbef8e29e3b662ab0e96526813b758`. The result includes the exact compiler and decoder identities; all eight original files are retained in the isolated Minis worktree under `.cache/writer-calibration-42149248875/`.

### Standalone all-intra writer control

[Run 42150392876](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42150392876), source `c66f8cc7de78f661295f3c81d1b651fd3cca6357`, compared the same six synthetic inputs through the existing writer and a scratch-only copy requesting a keyframe for every frame. The hosted standalone job ran without an app build or launch. Both arms accepted and decoded 40 frames per case, with exactly aligned source and decoded PTS and no drops. Each default output contained 9 key I-frames and 31 P-frames; every candidate output contained 40 key I-frames. Candidate files were 11,858–12,375 bytes versus 5,591–5,697 bytes for default, approximately 2.1 times larger.

With the predeclared red-excess metric, all-intra removed the observed clean-tail residual in the two synthetic regimes where it appeared under default encoding. However, none of the three all-intra marker regimes distinguished every positive frame from the clean boundary: each remained `marker-indistinguishable`. This control does not establish the cause of the original native capture result, prove native marker retirement, or justify changing the exact-RGB oracle or shipping encoder settings.

The comparison manifest SHA-256 is `add3e4c33e3c8fa2b1f79b581e1ee621c243ee230c42729f0b692290c9bfe40e`; default and candidate result manifests are `33d76472cfd0bdf330803550acedb9e32bad68970b14570e94ac32d61c5b9047` and `07e1144abb4058a6fabe9063c75c70e1a76784b9c5ed8056dafea3a53cd276a8`. Both input manifests, all twelve MP4s, and the comparison are retained under `.cache/writer-calibration-42150392876/` in the isolated Minis evidence worktree. The serial default and candidate processes respectively recorded 28.02 and 31.38 seconds elapsed, with approximately 49.6 MB peak resident memory each; these single-run readings are not a performance benchmark.
